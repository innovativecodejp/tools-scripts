<#
.SYNOPSIS
    KillLine.ps1 を一定間隔で繰り返し実行する監視ループです。

.DESCRIPTION
    既定で 30 分ごとに同じフォルダの KillLine.ps1 を呼び出し、LINE.exe の
    終了を試みます (使用中とみなせる場合は KillLine.ps1 側でスキップ)。
    Ctrl+C で停止できます。

    各実行ごとにタイムスタンプ付きのログを出力します。

.PARAMETER IntervalMinutes
    実行間隔 (分)。既定値: 30

.PARAMETER IdleThresholdMs
    KillLine.ps1 に渡す「直近の入力」とみなす経過時間 (ミリ秒)。既定値: 3000

.PARAMETER RunAtStart
    指定すると、最初の待機を行わず即座に 1 回目を実行します。

.EXAMPLE
    .\KillLineLoop.ps1

.EXAMPLE
    .\KillLineLoop.ps1 -IntervalMinutes 15 -RunAtStart
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 1440)]
    [int]$IntervalMinutes = 30,
    [int]$IdleThresholdMs = 3000,
    [switch]$RunAtStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$killLinePath = Join-Path $PSScriptRoot 'KillLine.ps1'
if (-not (Test-Path -LiteralPath $killLinePath)) {
    throw "KillLine.ps1 が見つかりません: $killLinePath"
}

$intervalSeconds = $IntervalMinutes * 60

Write-Host "KillLine 監視ループを開始します (間隔: ${IntervalMinutes} 分)。停止するには Ctrl+C を押してください。"

if (-not $RunAtStart) {
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] 次回実行まで待機します..."
    Start-Sleep -Seconds $intervalSeconds
}

while ($true) {
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    try {
        & $killLinePath -IdleThresholdMs $IdleThresholdMs
        Write-Host "[$timestamp] KillLine.ps1 を実行しました。"
    } catch {
        Write-Warning "[$timestamp] KillLine.ps1 の実行でエラー: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds $intervalSeconds
}
