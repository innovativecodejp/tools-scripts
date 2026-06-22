#Requires -Version 5.1
<#
.SYNOPSIS
    指定したスクリプトを $PROFILE 配下へ複写し、拡張子なしで起動できるよう
    リポジトリのプロファイルへ関数定義を追加してインストールします。

.DESCRIPTION
    次の手順でインストールします。

      ② <script-file.ps1> を $PROFILE のあるディレクトリ配下(同じ相対パス)へ複写する。
      ③ リポジトリの Microsoft.PowerShell_profile.ps1 に、拡張子なしで起動できる
         ラッパー関数の定義を追加する。
      ④ Microsoft.PowerShell_profile.ps1 と $PROFILE を比較し、差分が③の追加のみ
         (＝$PROFILE がリポジトリの追加前バージョンと一致)であれば $PROFILE を上書きする。
         それ以外はバージョンが異なるため $PROFILE を更新せず、赤字で通知する。

.PARAMETER ScriptFile
    インストールするスクリプト(.ps1)。リポジトリルート配下のパスを指定する。
    例: converter\Foo.ps1 / tools\Bar.ps1

.PARAMETER SourceRoot
    リポジトリ(ソース)のルート。既定はこのスクリプトの 1 つ上(powershell/)。

.EXAMPLE
    .\tools\InstallPsScript.ps1 tools\KillLine.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$ScriptFile,

    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

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

Write-Host ''
Write-Host '=== スクリプトのインストール ===' -ForegroundColor Cyan
Write-Host ("対象      : {0}" -f $relative)
Write-Host ("関数名    : {0}" -f $name)
Write-Host ("複写先    : {0}" -f $destPath)
Write-Host ''

# ── ② スクリプトを $PROFILE 配下へ複写 ───────────────────────────────
$destDir = Split-Path -Parent $destPath
if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}
Copy-Item -LiteralPath $srcFull -Destination $destPath -Force
Write-Host ("② 複写完了: {0}" -f $destPath) -ForegroundColor Green

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
    # KillLine と同じスタイルのラッパー関数を生成する。
    $blockLines = @(
        ''
        '<#'
        '.SYNOPSIS'
        ("    {0}\{1}.ps1 を実行します。" -f $category, $name)
        '#>'
        ("function {0} {{" -f $name)
        ("    `$scriptPath = {0}" -f $dirExpr)
        ''
        '    # スクリプト未配置の状態で実行された場合は明示的に停止します。'
        '    if (-not (Test-Path $scriptPath)) {'
        '        throw "Script not found: $scriptPath"'
        '    }'
        ''
        '    # 実体スクリプトを実行します(引数はそのまま渡します)。'
        '    & $scriptPath @args'
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
