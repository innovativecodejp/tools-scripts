#Requires -Version 5.1
<#
.SYNOPSIS
    converter / excel / file / tools 配下のスクリプトが $PROFILE ディレクトリ配下に
    インストールされているかを検査します（コピーは一切行いません）。

.DESCRIPTION
    リポジトリ（ソース）と $PROFILE のディレクトリ（インストール先）を突き合わせ、
    次の 3 点をチェックします。

      ① 各カテゴリ（converter / excel / file / tools）配下のスクリプトが
         インストール先に配置されているか
      ② 未インストールのスクリプト名を一覧表示
      ③ $PROFILE 本体とリポジトリの Microsoft.PowerShell_profile.ps1 が一致するか

    本スクリプトは読み取り専用です。インストール先へのコピーは絶対に行いません。

.PARAMETER Categories
    チェック対象のカテゴリディレクトリ名。既定は converter / excel / file / tools。

.PARAMETER SourceRoot
    リポジトリ（ソース）のルート。既定はこのスクリプトの 1 つ上（powershell/）。

.EXAMPLE
    .\tools\CheckPsTools.ps1
#>
[CmdletBinding()]
param(
    [string[]]$Categories = @('converter', 'excel', 'file', 'tools'),

    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot)
)

# ── 重要 ──────────────────────────────────────────────────────────────
# このスクリプトはチェック専用です。
# Copy-Item / Move-Item など、インストール先へ書き込む処理は一切含めません。
# ─────────────────────────────────────────────────────────────────────

# $PROFILE のディレクトリ（＝インストール先のルート）を求めます。
if ([string]::IsNullOrWhiteSpace($PROFILE)) {
    Write-Error '$PROFILE が解決できませんでした。PowerShell 上で実行してください。'
    return
}
$installRoot = Split-Path -Parent $PROFILE

Write-Host ''
Write-Host '=== インストール状況チェック ===' -ForegroundColor Cyan
Write-Host ("ソース      : {0}" -f $SourceRoot)
Write-Host ("インストール先: {0}" -f $installRoot)
Write-Host ''

# ① ② 各カテゴリのスクリプトがインストール先に存在するか検査します。
$missing = New-Object System.Collections.Generic.List[string]
$totalChecked = 0

foreach ($cat in $Categories) {
    $srcDir = Join-Path $SourceRoot $cat
    $dstDir = Join-Path $installRoot $cat

    # ソース側のカテゴリディレクトリが存在しない場合は警告して次へ。
    if (-not (Test-Path -LiteralPath $srcDir)) {
        Write-Host ("[{0}] ソースディレクトリが見つかりません: {1}" -f $cat, $srcDir) -ForegroundColor Yellow
        continue
    }

    # ソース側の .ps1 を列挙（無ければスキップ）。
    $scripts = @(Get-ChildItem -LiteralPath $srcDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
    if ($scripts.Count -eq 0) {
        Write-Host ("[{0}] 対象スクリプトなし" -f $cat) -ForegroundColor DarkGray
        continue
    }

    $catMissing = New-Object System.Collections.Generic.List[string]
    foreach ($script in $scripts) {
        $totalChecked++
        $dstPath = Join-Path $dstDir $script.Name
        if (-not (Test-Path -LiteralPath $dstPath)) {
            $catMissing.Add($script.Name)
            $missing.Add(('{0}\{1}' -f $cat, $script.Name))
        }
    }

    if ($catMissing.Count -eq 0) {
        Write-Host ("[{0}] OK ({1} 件すべてインストール済み)" -f $cat, $scripts.Count) -ForegroundColor Green
    }
    else {
        Write-Host ("[{0}] 未インストール {1}/{2} 件:" -f $cat, $catMissing.Count, $scripts.Count) -ForegroundColor Red
        foreach ($name in $catMissing) {
            Write-Host ("    - {0}" -f $name) -ForegroundColor Red
        }
    }
}

Write-Host ''
if ($missing.Count -eq 0) {
    Write-Host ("スクリプト: 全 {0} 件インストール済み" -f $totalChecked) -ForegroundColor Green
}
else {
    Write-Host ("未インストールのスクリプト: {0} 件" -f $missing.Count) -ForegroundColor Red
}

# ③ $PROFILE 本体とリポジトリのプロファイル管理ファイルを比較します。
Write-Host ''
Write-Host '=== プロファイル比較 ===' -ForegroundColor Cyan

$repoProfile = Join-Path $SourceRoot 'Microsoft.PowerShell_profile.ps1'
$installedProfile = $PROFILE

Write-Host ("リポジトリ側: {0}" -f $repoProfile)
Write-Host ("`$PROFILE   : {0}" -f $installedProfile)

$profileEqual = $false
if (-not (Test-Path -LiteralPath $repoProfile)) {
    Write-Host ("リポジトリ側のプロファイルが見つかりません: {0}" -f $repoProfile) -ForegroundColor Yellow
}
elseif (-not (Test-Path -LiteralPath $installedProfile)) {
    Write-Host ("`$PROFILE 本体が未配置です: {0}" -f $installedProfile) -ForegroundColor Red
}
else {
    # ハッシュで内容一致を判定します（改行・エンコードの差異も検出）。
    $repoHash = (Get-FileHash -LiteralPath $repoProfile -Algorithm SHA256).Hash
    $instHash = (Get-FileHash -LiteralPath $installedProfile -Algorithm SHA256).Hash
    $profileEqual = ($repoHash -eq $instHash)

    if ($profileEqual) {
        Write-Host 'プロファイル: 一致' -ForegroundColor Green
    }
    else {
        Write-Host 'プロファイル: 不一致（内容が異なります）' -ForegroundColor Red
    }
}

# 呼び出し側で判定に使えるよう、結果オブジェクトを返します（コピーは行いません）。
[PSCustomObject]@{
    InstallRoot   = $installRoot
    CheckedCount  = $totalChecked
    MissingCount  = $missing.Count
    Missing       = $missing.ToArray()
    ProfileEqual  = $profileEqual
}
