<#
.SYNOPSIS
    指定したスクリプトを $PROFILE 配下へ複写し、拡張子なしで起動できるよう
    リポジトリのプロファイルへ関数定義を追加してインストールします。

.DESCRIPTION
    次の手順でインストールします。

      ② <script-file.ps1> を $PROFILE のあるディレクトリ配下(同じ相対パス)へ複写する。
      ③ リポジトリの Microsoft.PowerShell_profile.ps1 に、拡張子なしで起動できる
         ラッパー関数の定義を追加する。本体は共通ヘルパー Invoke-ToolScript の
         呼び出し 1 行で、未配置チェックと -Help によるヘルプ転送を担う。
         関数名と同名のエイリアスが存在する場合
         (例: Diff → 組み込みの diff = Compare-Object) は、エイリアスの方が
         優先されて関数が呼ばれないため、解除する行も併せて追加する。
      ④ Microsoft.PowerShell_profile.ps1 と $PROFILE を比較し、差分が③の追加のみ
         (＝$PROFILE がリポジトリの追加前バージョンと一致)であれば $PROFILE を上書きする。
         それ以外はバージョンが異なるため $PROFILE を更新せず、赤字で通知する。

    -CopyOnly を指定すると ② だけを行い、③ ④ をスキップします。
    既にインストール済みのスクリプトを修正し、配置先へ置き直したいだけの場合に
    使用してください(③ を走らせる必要がないため)。

    また、ファイル全体が関数定義だけで構成された「関数ライブラリ形式」の
    スクリプト(例: converter\MdToPdf.ps1 / converter\AiMermaid.ps1)を検出した
    場合は、③ ④ を自動的にスキップします。この形式は & で実行しても関数が
    子スコープで消えるだけで何も起きないため、ラッパー関数を作ると
    ドットソースで登録された本体を上書きして機能しなくなります。
    プロファイルには手動でドットソース( . $path )を記述してください。

.PARAMETER ScriptFile
    インストールするスクリプト(.ps1)。リポジトリルート配下のパスを指定する。
    例: converter\Foo.ps1 / tools\Bar.ps1

.PARAMETER SourceRoot
    リポジトリ(ソース)のルート。既定はこのスクリプトの 1 つ上(powershell/)。

.PARAMETER CopyOnly
    ② の複写のみを行い、③ 関数定義の追加と ④ $PROFILE の同期をスキップする。
    エイリアス: -c

.EXAMPLE
    .\tools\InstallPsScript.ps1 tools\KillLine.ps1

.EXAMPLE
    .\tools\InstallPsScript.ps1 tools\KillLine.ps1 -c
#>
# コメントベースヘルプより前に置くと Get-Help が拾えなくなるため、ここへ置く。
#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScriptFile,

    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),

    [Alias('c')]
    [switch]$CopyOnly
)

$ErrorActionPreference = 'Stop'

# ── 関数ライブラリ形式の判定 ─────────────────────────────────────────
# トップレベルに param(...) が無く、実行文が関数定義だけで構成されている
# スクリプトを「関数ライブラリ」とみなす(例: MdToPdf.ps1 / AiMermaid.ps1)。
#
# この形式は実行しても関数を定義するだけで、& による呼び出しでは子スコープで
# 定義が消えるため何も起きない。ラッパー関数を作るとドットソースで登録された
# 本体を後から上書きしてしまい、エラーも出ずに無反応になる。
function Test-FunctionLibrary {
    param([string]$Path)

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
    if (-not $ast) { return $false }

    # トップレベルに param ブロックがあるなら、実行して動く通常のスクリプト。
    if ($ast.ParamBlock) { return $false }
    if (-not $ast.EndBlock) { return $false }

    $statements = @($ast.EndBlock.Statements)
    if ($statements.Count -eq 0) { return $false }

    # 実行文が 1 つでもあれば通常のスクリプト。すべて関数定義ならライブラリ。
    foreach ($statement in $statements) {
        if ($statement -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) {
            return $false
        }
    }
    return $true
}

# ── パス解決 ─────────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($PROFILE)) {
    Write-Error '$PROFILE が解決できませんでした。PowerShell 上で実行してください。'
    return
}

if (-not (Test-Path -LiteralPath $ScriptFile)) {
    Write-Error "スクリプトが見つかりません: $ScriptFile"
    return
}

$srcFull  = (Resolve-Path -LiteralPath $ScriptFile).Path
$rootFull = (Resolve-Path -LiteralPath $SourceRoot).Path

if ([System.IO.Path]::GetExtension($srcFull) -ne '.ps1') {
    Write-Error "対象は .ps1 ファイルである必要があります: $srcFull"
    return
}

# ソースルート配下にあることを確認し、相対パス(カテゴリを含む)を求める。
if (-not $srcFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Error "スクリプトはリポジトリ($rootFull)配下に置いてください: $srcFull"
    return
}
$relative = $srcFull.Substring($rootFull.Length).TrimStart('\', '/')
$category = ($relative -split '[\\/]')[0]
$name     = [System.IO.Path]::GetFileNameWithoutExtension($srcFull)

$installRoot   = Split-Path -Parent $PROFILE
$repoProfile   = Join-Path $rootFull 'Microsoft.PowerShell_profile.ps1'
$destPath      = Join-Path $installRoot $relative

# 関数ライブラリ形式なら、ラッパー関数を作ってはいけないので複写のみに切り替える。
$isLibrary = Test-FunctionLibrary -Path $srcFull

Write-Host ''
Write-Host '=== スクリプトのインストール ===' -ForegroundColor Cyan
Write-Host ("対象      : {0}" -f $relative)
Write-Host ("関数名    : {0}" -f $(if ($CopyOnly -or $isLibrary) { '(登録しません)' } else { $name }))
Write-Host ("複写先    : {0}" -f $destPath)
Write-Host ''

# ── ② スクリプトを $PROFILE 配下へ複写 ───────────────────────────────
$destDir = Split-Path -Parent $destPath
if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}
Copy-Item -LiteralPath $srcFull -Destination $destPath -Force
Write-Host ("② 複写完了: {0}" -f $destPath) -ForegroundColor Green

# ── ③ ④ をスキップする条件 ─────────────────────────────────────────
if ($isLibrary) {
    Write-Host ''
    Write-Host ("関数ライブラリ形式のため、③ 関数定義の追加と ④ `$PROFILE の同期は行いません。" ) -ForegroundColor Yellow
    Write-Host ('  (トップレベルが関数定義のみ。& で実行しても子スコープで消えるため') -ForegroundColor Gray
    Write-Host ('   ラッパー関数を作るとドットソース済みの本体を上書きしてしまいます)') -ForegroundColor Gray
    Write-Host ('  プロファイルには手動でドットソースを記述してください:') -ForegroundColor Gray
    Write-Host ("      . (`$Global:{0}Dir + '{1}.ps1')" -f (Get-Culture).TextInfo.ToTitleCase($category), $name) -ForegroundColor Gray
    return
}

if ($CopyOnly) {
    Write-Host ''
    Write-Host ("-CopyOnly が指定されたため、③ 関数定義の追加と ④ `$PROFILE の同期は行いません。") -ForegroundColor Yellow
    return
}

# ── ③ リポジトリのプロファイルへラッパー関数を追加 ───────────────────
if (-not (Test-Path -LiteralPath $repoProfile)) {
    Write-Error "リポジトリのプロファイルが見つかりません: $repoProfile"
    return
}

# 元ファイルの改行コード・BOM を検出して保持する。
$repoBytes = [System.IO.File]::ReadAllBytes($repoProfile)
$hasBom    = ($repoBytes.Length -ge 3 -and $repoBytes[0] -eq 0xEF -and $repoBytes[1] -eq 0xBB -and $repoBytes[2] -eq 0xBF)
$repoBefore = [System.IO.File]::ReadAllText($repoProfile)
$nl = if ($repoBefore.Contains("`r`n")) { "`r`n" } else { "`n" }

# カテゴリ → プロファイルで定義済みのディレクトリ変数へのマッピング。
$dirVarMap = @{
    converter = '$Global:ConverterDir'
    tools     = '$Global:ToolsDir'
    file      = '$Global:FileDir'
    mail      = '$Global:MailDir'
    docs      = '$Global:DocsDir'
    excel     = '$Global:ExcelDir'
}
$catKey = $category.ToLowerInvariant()
if ($dirVarMap.ContainsKey($catKey)) {
    $dirExpr = "{0} + '{1}.ps1'" -f $dirVarMap[$catKey], $name
}
else {
    # 未知のカテゴリは ProfileDir から組み立てる。
    $dirExpr = "`$Global:ProfileDir + '\{0}\{1}.ps1'" -f $category, $name
}

# 既に同名関数が定義済みなら追加しない(二重定義防止)。
$alreadyDefined = $repoBefore -match ("(?m)^\s*function\s+{0}\b" -f [regex]::Escape($name))

if ($alreadyDefined) {
    Write-Host ("③ 関数 {0} は既に定義済みのため追加しません。" -f $name) -ForegroundColor Yellow
    $repoAfter = $repoBefore
}
else {
    # PowerShell のコマンド解決順は Alias > Function > Cmdlet > Application のため、
    # 関数名と同名のエイリアス(例: diff → Compare-Object)があると関数は呼ばれない。
    # 該当する場合は解除行を関数定義の前に出力する。
    # ReadOnly なエイリアスも Remove-Item -Force で解除できる(Constant は不可)。
    $shadowAlias = Get-Alias -Name $name -ErrorAction SilentlyContinue

    # KillLine と同じスタイルのラッパー関数を生成する。
    $blockLines = @('')

    if ($shadowAlias) {
        $blockLines += @(
            ("# 組み込みエイリアス {0} ({1}) は関数より優先されるため解除します。" -f $name, $shadowAlias.Definition)
            ("if (Test-Path Alias:{0}) {{" -f $name)
            ("    Remove-Item -LiteralPath Alias:{0} -Force" -f $name)
            '}'
            ''
        )
    }

    # 未配置チェックとヘルプ転送はプロファイルの Invoke-ToolScript に集約済み。
    $blockLines += @(
        '<#'
        '.SYNOPSIS'
        ("    {0}\{1}.ps1 を実行します。-Help でヘルプを表示します。" -f $category, $name)
        '#>'
        ("function {0} {{" -f $name)
        ("    Invoke-ToolScript -ScriptPath ({0}) -Arguments `$args" -f $dirExpr)
        '}'
    )
    $block = ($blockLines -join $nl)

    # 末尾に改行が無ければ補ってから追記する。
    $repoAfter = $repoBefore
    if (-not $repoAfter.EndsWith($nl)) { $repoAfter += $nl }
    $repoAfter += $block + $nl

    $enc = New-Object System.Text.UTF8Encoding($hasBom)
    [System.IO.File]::WriteAllText($repoProfile, $repoAfter, $enc)
    Write-Host ("③ 関数 {0} をリポジトリのプロファイルに追加しました。" -f $name) -ForegroundColor Green
    if ($shadowAlias) {
        Write-Host ("   同名のエイリアス {0} ({1}) を解除する行も併せて追加しました。" -f $name, $shadowAlias.Definition) -ForegroundColor Yellow
    }
}

# ── ④ プロファイル比較 → 差分が③のみなら $PROFILE を上書き ───────────
Write-Host ''
Write-Host '=== プロファイル比較 ===' -ForegroundColor Cyan

function Get-NormalizedText([string]$s) {
    # 改行コードの差異・末尾空白を無視して比較するための正規化。
    return ($s -replace "`r`n", "`n").TrimEnd()
}

$installed = [System.IO.File]::ReadAllText($PROFILE)

# $PROFILE が「③の追加前のリポジトリ内容」と一致するなら、差分は③のみ。
if ((Get-NormalizedText $installed) -eq (Get-NormalizedText $repoBefore)) {
    Copy-Item -LiteralPath $repoProfile -Destination $PROFILE -Force
    Write-Host "④ 差分は③の追加のみ。`$PROFILE を上書きしました。" -ForegroundColor Green
    Write-Host ("   {0}" -f $PROFILE) -ForegroundColor Green
}
else {
    Write-Host "④ バージョンが異なるため `$PROFILE を更新していません。" -ForegroundColor Red
    Write-Host "   (Microsoft.PowerShell_profile.ps1 と `$PROFILE の差分が③の追加以外にもあります)" -ForegroundColor Red
}
