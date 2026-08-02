#Requires -Version 7.0
<#
.SYNOPSIS
    指定したファイル / フォルダの差分を TortoiseGit の GUI で開きます。

.DESCRIPTION
    TortoiseGitProc.exe を起動し、TortoiseGit の差分ビューア
    (既定では TortoiseGitMerge) を表示します。

    引数なし、またはファイルパスのみを指定した場合は、作業ツリーの内容と
    その BASE (HEAD) を比較します。

      Diff .\src\App.cs

    指定内容によって発行するコマンドを切り替えます。

      | -Path    | -Path2 | -StartRev / -EndRev | 発行コマンド   |
      |----------|--------|---------------------|----------------|
      | ファイル | なし   | なし                | diff           |
      | ファイル | あり   | -                   | diff (2ファイル)|
      | ファイル | なし   | あり                | diff (リビジョン指定) |
      | フォルダ | なし   | なし                | repostatus     |
      | フォルダ | なし   | あり                | showcompare    |
      | フォルダ | あり   | -                   | diff           |

    TortoiseGitProc.exe は次の順に探索します。

      1. -TortoiseGitProc パラメータ
      2. レジストリ (HKCU / HKLM / HKLM WOW6432Node の SOFTWARE\TortoiseGit)
      3. PATH 上の TortoiseGitProc.exe
      4. %ProgramFiles% / %ProgramFiles(x86)% の TortoiseGit\bin

    -Path2 を指定しない場合 (BASE との比較が必要な場合) のみ、対象が Git の
    管理下にあるかを確認します。判定は .git を親方向へ探す方式のため、
    git.exe が無い環境でも動作し、worktree / submodule (.git がファイル) にも
    対応します。

    GUI ツールのため既定では起動後すぐに制御を返します。-Wait を指定すると
    ウィンドウが閉じるまで待機します。

.PARAMETER Path
    比較対象のファイルまたはフォルダ。既定値: カレントディレクトリ

.PARAMETER Path2
    2 ファイル比較を行う場合の比較相手。指定するとリビジョン指定は使えません。

.PARAMETER StartRev
    比較元 (BASE 側) のリビジョン。エイリアス: -s
    例: HEAD~3 / master / 1a2b3c4

.PARAMETER EndRev
    比較先のリビジョン。エイリアス: -e

.PARAMETER Unified
    unified diff 形式で表示します。エイリアス: -u

.PARAMETER Line
    差分ビューアを開いた直後にスクロールする行番号。

.PARAMETER Wait
    TortoiseGit のウィンドウが閉じるまで待機します。

.PARAMETER TortoiseGitProc
    TortoiseGitProc.exe のパスを明示指定します。

.EXAMPLE
    .\Diff.ps1 .\src\App.cs

.EXAMPLE
    .\Diff.ps1 .\a.txt .\b.txt

.EXAMPLE
    .\Diff.ps1 .\src\App.cs -s HEAD~3 -e HEAD

.EXAMPLE
    .\Diff.ps1 .\src\App.cs -Unified -Line 120

.EXAMPLE
    .\Diff.ps1 .\src
#>

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Rev')]
param(
    [Parameter(Position = 0)]
    [string]$Path = '.',

    [Parameter(ParameterSetName = 'TwoPath', Position = 1, Mandatory = $true)]
    [string]$Path2,

    [Parameter(ParameterSetName = 'Rev')]
    [Alias('s')]
    [string]$StartRev,

    [Parameter(ParameterSetName = 'Rev')]
    [Alias('e')]
    [string]$EndRev,

    [Alias('u')]
    [switch]$Unified,

    [ValidateRange(1, 2147483647)]
    [int]$Line,

    [switch]$Wait,

    [string]$TortoiseGitProc
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── TortoiseGitProc.exe の解決 ───────────────────────────────────────
# 見つかった最初の実在パスを返す。全滅した場合は導入案内付きで停止する。
function Resolve-TortoiseGitProc {
    param([string]$Explicit)

    # ① 明示指定。誤りに気付けるよう、存在しなければ即座に停止する。
    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        if (Test-Path -LiteralPath $Explicit -PathType Leaf) {
            return (Resolve-Path -LiteralPath $Explicit).Path
        }
        throw "TortoiseGitProc.exe が見つかりません: $Explicit"
    }

    # ② レジストリ。ProcPath が空でキーだけ存在する環境があるため空判定は必須。
    $regKeys = @(
        'HKCU:\SOFTWARE\TortoiseGit'
        'HKLM:\SOFTWARE\TortoiseGit'
        'HKLM:\SOFTWARE\WOW6432Node\TortoiseGit'
    )
    foreach ($key in $regKeys) {
        if (-not (Test-Path -LiteralPath $key)) { continue }

        $props = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if (-not $props) { continue }

        $candidates = @()
        if ($props.PSObject.Properties.Name -contains 'ProcPath') {
            $candidates += $props.ProcPath
        }
        if ($props.PSObject.Properties.Name -contains 'Directory') {
            $dir = $props.Directory
            if (-not [string]::IsNullOrWhiteSpace($dir)) {
                $candidates += (Join-Path $dir 'bin\TortoiseGitProc.exe')
            }
        }

        foreach ($candidate in $candidates) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }

    # ③ PATH 上。
    $onPath = Get-Command 'TortoiseGitProc.exe' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($onPath) { return $onPath.Source }

    # ④ 既定のインストール先。
    $programDirs = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    foreach ($dir in $programDirs) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $candidate = Join-Path $dir 'TortoiseGit\bin\TortoiseGitProc.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    throw @'
TortoiseGitProc.exe が見つかりませんでした。
TortoiseGit をインストールするか、-TortoiseGitProc でパスを指定してください。
  winget install TortoiseGit.TortoiseGit
'@
}

# ── Git 作業ツリー判定 ───────────────────────────────────────────────
# 対象から親方向へ .git を探す。submodule / worktree では .git がファイルの
# ため、ディレクトリとファイルの両方を許容する。
function Test-GitWorkTree {
    param([string]$FullPath)

    $dir = if (Test-Path -LiteralPath $FullPath -PathType Container) {
        $FullPath
    }
    else {
        Split-Path -Parent $FullPath
    }

    while (-not [string]::IsNullOrWhiteSpace($dir)) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { return $true }

        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }

    return $false
}

# ── 引数の組み立て ───────────────────────────────────────────────────
# TortoiseGitProc へは 1 本の文字列として渡すため、公式ドキュメントの例と
# 同じく「コロンの後ろだけ」を引用してパスを埋め込む。
# (呼び出し演算子 & ではトークン全体が引用され、パーサ依存の挙動になる)
function Format-ProcPathOption {
    param([string]$Name, [string]$Value)

    return ('/{0}:"{1}"' -f $Name, $Value)
}

# ── パスの解決 ───────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "パスが見つかりません: $Path"
    return
}
$fullPath = (Resolve-Path -LiteralPath $Path).Path
$isDirectory = Test-Path -LiteralPath $fullPath -PathType Container

$fullPath2 = $null
if ($PSBoundParameters.ContainsKey('Path2')) {
    if (-not (Test-Path -LiteralPath $Path2)) {
        Write-Error "パスが見つかりません: $Path2"
        return
    }
    $fullPath2 = (Resolve-Path -LiteralPath $Path2).Path
}

# ── Git 管理下チェック ───────────────────────────────────────────────
# -Path2 指定時は 2 ファイルを直接比較するだけなので BASE を必要としない。
if (-not $fullPath2 -and -not (Test-GitWorkTree $fullPath)) {
    Write-Error "Git の管理下にありません (.git が見つかりません): $fullPath"
    return
}

# ── 発行するコマンドの決定 ───────────────────────────────────────────
$hasRev = $PSBoundParameters.ContainsKey('StartRev') -or $PSBoundParameters.ContainsKey('EndRev')

$command =
    if ($fullPath2) { 'diff' }
    elseif ($isDirectory -and $hasRev) { 'showcompare' }
    elseif ($isDirectory) { 'repostatus' }
    else { 'diff' }

# ── 引数文字列の生成 ─────────────────────────────────────────────────
$options = [System.Collections.Generic.List[string]]::new()
$options.Add("/command:$command")
$options.Add((Format-ProcPathOption -Name 'path' -Value $fullPath))

if ($fullPath2) {
    $options.Add((Format-ProcPathOption -Name 'path2' -Value $fullPath2))
}

switch ($command) {
    'diff' {
        # リビジョンは refs のため空白を含まない。引用は不要。
        if ($PSBoundParameters.ContainsKey('StartRev')) { $options.Add("/startrev:$StartRev") }
        if ($PSBoundParameters.ContainsKey('EndRev')) { $options.Add("/endrev:$EndRev") }
        if ($Unified) { $options.Add('/unified') }
        if ($PSBoundParameters.ContainsKey('Line')) { $options.Add("/line:$Line") }
    }
    'showcompare' {
        # showcompare は startrev/endrev ではなく revision1/revision2 を使う。
        if ($PSBoundParameters.ContainsKey('StartRev')) { $options.Add("/revision1:$StartRev") }
        if ($PSBoundParameters.ContainsKey('EndRev')) { $options.Add("/revision2:$EndRev") }
        if ($Unified) { $options.Add('/unified') }
    }
    'repostatus' {
        # 変更確認ダイアログは表示形式のオプションを受け付けない。
        if ($Unified) { Write-Warning 'フォルダ指定のため -Unified は無視されます。' }
        if ($PSBoundParameters.ContainsKey('Line')) { Write-Warning 'フォルダ指定のため -Line は無視されます。' }
    }
}

$arguments = ($options -join ' ')

# ── 実行 ─────────────────────────────────────────────────────────────
$procPath = Resolve-TortoiseGitProc -Explicit $TortoiseGitProc

Write-Host ''
Write-Host '=== TortoiseGit Diff ===' -ForegroundColor Cyan
Write-Host ("実行ファイル: {0}" -f $procPath)
Write-Host ("コマンド    : {0}" -f $command)
Write-Host ("対象        : {0}" -f $fullPath)
if ($fullPath2) {
    Write-Host ("比較相手    : {0}" -f $fullPath2)
}
Write-Host ("引数        : {0}" -f $arguments) -ForegroundColor Gray

$process = $null
if ($PSCmdlet.ShouldProcess($fullPath, ("TortoiseGitProc /command:{0}" -f $command))) {
    $startParams = @{
        FilePath     = $procPath
        ArgumentList = $arguments
        PassThru     = $true
    }
    if ($Wait) { $startParams['Wait'] = $true }

    $process = Start-Process @startParams
    Write-Host ("起動しました (PID: {0})" -f $process.Id) -ForegroundColor Green
}

# -WhatIf 時は $process が無いため、ID / 終了コードは null のまま返す。
$processId = $null
$exitCode = $null
if ($process) {
    $processId = $process.Id
    if ($Wait) { $exitCode = $process.ExitCode }
}

[PSCustomObject]@{
    Executable = $procPath
    Command    = $command
    Arguments  = $arguments
    Path       = $fullPath
    Path2      = $fullPath2
    ProcessId  = $processId
    ExitCode   = $exitCode
}
