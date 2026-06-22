<#
.SYNOPSIS
    KillLine.ps1 を 30 分ごとに実行するタスクをタスクスケジューラに登録 / 解除します。

.DESCRIPTION
    同じフォルダの KillLine.ps1 を、30 分間隔で繰り返し実行するスケジュール
    タスクを作成します。コンソールを開いておく必要はなく、バックグラウンド
    (非表示) で実行されます。

    タスクは「ログオン中のみ・現在のユーザー権限」で実行されます
    (LINE のウィンドウ状態を判定できるようにするため)。管理者権限は不要です。

    内部では schtasks.exe を使用します
    (ScheduledTasks の CIM コマンドレットは環境によりアクセス拒否となるため)。

    -Unregister を指定すると登録済みタスクを削除します。

.PARAMETER IntervalMinutes
    実行間隔 (分)。既定値: 30

.PARAMETER IdleThresholdMs
    KillLine.ps1 に渡す「直近の入力」とみなす経過時間 (ミリ秒)。既定値: 3000

.PARAMETER TaskName
    登録するタスク名。既定値: KillLine

.PARAMETER LogPath
    KillLine.ps1 に渡すログ出力先。既定値: <スクリプトと同じフォルダ>\logs\KillLine.log

.PARAMETER Unregister
    指定すると、登録済みタスクを削除します。

.EXAMPLE
    .\Register-KillLineTask.ps1

.EXAMPLE
    .\Register-KillLineTask.ps1 -IntervalMinutes 15

.EXAMPLE
    .\Register-KillLineTask.ps1 -Unregister
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 1440)]
    [int]$IntervalMinutes = 30,
    [int]$IdleThresholdMs = 3000,
    [string]$TaskName = 'KillLine',
    [string]$LogPath = (Join-Path $PSScriptRoot 'logs\KillLine.log'),
    [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 解除モード
if ($Unregister) {
    schtasks.exe /Delete /TN $TaskName /F
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "タスク '$TaskName' の削除に失敗しました (未登録の可能性があります)。"
    } else {
        Write-Host "タスク '$TaskName' を削除しました。"
    }
    return
}

# 登録モード
$killLinePath = Join-Path $PSScriptRoot 'KillLine.ps1'
if (-not (Test-Path -LiteralPath $killLinePath)) {
    throw "KillLine.ps1 が見つかりません: $killLinePath"
}

# 実行する PowerShell の本体 (pwsh 優先、なければ Windows PowerShell)
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
    $pwsh = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

# 実行コマンド。パスにスペースを含むため内側を二重引用符で囲む。
# PowerShell から native schtasks へ渡す際、内側の " は \" にエスケープされて
# schtasks が期待する形式になる。
$taskRun = "`"$pwsh`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
           "-File `"$killLinePath`" -IdleThresholdMs $IdleThresholdMs -Quiet " +
           "-LogPath `"$LogPath`""

schtasks.exe /Create `
    /TN $TaskName `
    /TR $taskRun `
    /SC MINUTE `
    /MO $IntervalMinutes `
    /F

if ($LASTEXITCODE -ne 0) {
    throw "タスク '$TaskName' の登録に失敗しました (schtasks 終了コード: $LASTEXITCODE)。"
}

Write-Host ""
Write-Host "タスク '$TaskName' を登録しました (${IntervalMinutes} 分間隔)。"
Write-Host "  実行ファイル : $pwsh"
Write-Host "  スクリプト   : $killLinePath"
Write-Host "  ログ         : $LogPath"
Write-Host ""
Write-Host "確認     : schtasks /Query /TN '$TaskName' /V /FO LIST"
Write-Host "手動実行 : schtasks /Run /TN '$TaskName'"
Write-Host "解除     : .\Register-KillLineTask.ps1 -Unregister"
