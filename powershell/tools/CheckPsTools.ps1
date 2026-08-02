<#
.SYNOPSIS
    converter / excel / file / tools 配下のスクリプトが $PROFILE ディレクトリ配下に
    インストールされ、内容も最新かを検査します（コピーは一切行いません）。

.DESCRIPTION
    リポジトリ（ソース）と $PROFILE のディレクトリ（インストール先）を突き合わせ、
    次の 4 点をチェックします。

      ① 各カテゴリ（converter / excel / file / tools）配下のスクリプトが
         インストール先に配置されているか（存在）、および SHA256 が一致するか（内容）
      ② 未インストール／内容不一致のスクリプト名を一覧表示
      ③ $PROFILE 本体とリポジトリの Microsoft.PowerShell_profile.ps1 が一致するか
      ④ リポジトリ内の .ps1 が「BOM なし + LF」に揃っているか

    ① の内容比較は、スクリプトを修正したあと配置し忘れる事故を検出するためのものです。
    「配置済みだが古い」状態は存在チェックだけでは分からないため、SHA256 で照合します。

    ④ は PowerShell 7 の既定（BOM なし UTF-8）に合わせるためのチェックです。
    BOM や CRLF が混在すると差分が汚れ、エディタによっては書き戻しで形式が
    揺れるため、リポジトリ全体を再帰的に検査します。

    本スクリプトは読み取り専用です。インストール先へのコピーは絶対に行いません。

.PARAMETER Categories
    チェック対象のカテゴリディレクトリ名。既定は converter / excel / file / tools。

.PARAMETER SourceRoot
    リポジトリ（ソース）のルート。既定はこのスクリプトの 1 つ上（powershell/）。

.EXAMPLE
    .\tools\CheckPsTools.ps1
#>
# コメントベースヘルプより前に置くと Get-Help が拾えなくなるため、ここへ置く。
#Requires -Version 7.0

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

# ① ② 各カテゴリのスクリプトが配置済みか（存在）、内容が最新か（SHA256）を検査します。
$missing = New-Object System.Collections.Generic.List[string]
$stale   = New-Object System.Collections.Generic.List[string]
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
    $catStale   = New-Object System.Collections.Generic.List[string]
    foreach ($script in $scripts) {
        $totalChecked++
        $dstPath = Join-Path $dstDir $script.Name

        if (-not (Test-Path -LiteralPath $dstPath)) {
            $catMissing.Add($script.Name)
            $missing.Add(('{0}\{1}' -f $cat, $script.Name))
            continue
        }

        # 配置済みでも内容が古い場合があるため、SHA256 で照合する。
        $srcHash = (Get-FileHash -LiteralPath $script.FullName -Algorithm SHA256).Hash
        $dstHash = (Get-FileHash -LiteralPath $dstPath -Algorithm SHA256).Hash
        if ($srcHash -ne $dstHash) {
            $catStale.Add($script.Name)
            $stale.Add(('{0}\{1}' -f $cat, $script.Name))
        }
    }

    if ($catMissing.Count -eq 0 -and $catStale.Count -eq 0) {
        Write-Host ("[{0}] OK ({1} 件すべてインストール済み・最新)" -f $cat, $scripts.Count) -ForegroundColor Green
    }
    else {
        if ($catMissing.Count -gt 0) {
            Write-Host ("[{0}] 未インストール {1}/{2} 件:" -f $cat, $catMissing.Count, $scripts.Count) -ForegroundColor Red
            foreach ($name in $catMissing) {
                Write-Host ("    - {0}" -f $name) -ForegroundColor Red
            }
        }
        if ($catStale.Count -gt 0) {
            Write-Host ("[{0}] 内容不一致 {1}/{2} 件:" -f $cat, $catStale.Count, $scripts.Count) -ForegroundColor Yellow
            foreach ($name in $catStale) {
                Write-Host ("    - {0}  (配置先が古い可能性があります)" -f $name) -ForegroundColor Yellow
            }
        }
    }
}

Write-Host ''
if ($missing.Count -eq 0 -and $stale.Count -eq 0) {
    Write-Host ("スクリプト: 全 {0} 件インストール済み・最新" -f $totalChecked) -ForegroundColor Green
}
else {
    if ($missing.Count -gt 0) {
        Write-Host ("未インストールのスクリプト: {0} 件" -f $missing.Count) -ForegroundColor Red
    }
    if ($stale.Count -gt 0) {
        Write-Host ("内容が一致しないスクリプト: {0} 件" -f $stale.Count) -ForegroundColor Yellow
        Write-Host '  再配置するには次を実行してください:' -ForegroundColor Gray
        foreach ($rel in $stale) {
            Write-Host ("      InstallPsScript {0} -c" -f $rel) -ForegroundColor Gray
        }
    }
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

# ④ リポジトリ内の .ps1 が「BOM なし + LF」に揃っているかを検査します。
Write-Host ''
Write-Host '=== エンコーディングチェック (BOM なし + LF) ===' -ForegroundColor Cyan

$sourceFull = (Resolve-Path -LiteralPath $SourceRoot).Path
$encodingIssues = New-Object System.Collections.Generic.List[object]
$psFiles = @(Get-ChildItem -LiteralPath $sourceFull -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue)

foreach ($file in $psFiles) {
    $bytes  = [System.IO.File]::ReadAllBytes($file.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $crlf   = [regex]::Matches([System.IO.File]::ReadAllText($file.FullName), "`r`n").Count

    if (-not $hasBom -and $crlf -eq 0) { continue }

    $reasons = @()
    if ($hasBom) { $reasons += 'BOM あり' }
    if ($crlf -gt 0) { $reasons += ('CRLF {0} 箇所' -f $crlf) }

    $encodingIssues.Add([PSCustomObject]@{
        Path   = $file.FullName.Substring($sourceFull.Length).TrimStart('\', '/')
        Reason = ($reasons -join ' / ')
    })
}

if ($encodingIssues.Count -eq 0) {
    Write-Host ("OK ({0} 件すべて BOM なし + LF)" -f $psFiles.Count) -ForegroundColor Green
}
else {
    Write-Host ("要修正 {0}/{1} 件:" -f $encodingIssues.Count, $psFiles.Count) -ForegroundColor Red
    foreach ($issue in $encodingIssues) {
        Write-Host ("    - {0}  ({1})" -f $issue.Path, $issue.Reason) -ForegroundColor Red
    }
}

# 呼び出し側で判定に使えるよう、結果オブジェクトを返します（コピーは行いません）。
[PSCustomObject]@{
    InstallRoot        = $installRoot
    CheckedCount       = $totalChecked
    MissingCount       = $missing.Count
    Missing            = $missing.ToArray()
    StaleCount         = $stale.Count
    Stale              = $stale.ToArray()
    ProfileEqual       = $profileEqual
    EncodingIssueCount = $encodingIssues.Count
    EncodingIssues     = $encodingIssues.ToArray()
}
