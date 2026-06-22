<#
.SYNOPSIS
    KillLine.ps1 を 30 分ごとに実行するタスクをタスクスケジューラに登録 / 解除します。

.DESCRIPTION
    KillLine.ps1 を 30 分間隔で繰り返し実行するスケジュールタスクを作成します。
    コンソールを開いておく必要はなく、バックグラウンド (非表示) で実行されます。

    タスクが参照する KillLine.ps1 は、既定で $PROFILE 配下の配置先
    (<$PROFILE のフォルダ>\tools\KillLine.ps1) です。
    dev リポジトリは開発環境とし、配置先へコピーして運用する想定のため、
    この登録スクリプトを dev から実行しても、タスクは配置先を指すようにします。

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

.PARAMETER ScriptPath
    タスクが実行する KillLine.ps1 のパス。
    既定値: <$PROFILE のフォルダ>\tools\KillLine.ps1

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
    [string]$ScriptPath = (Join-Path (Split-Path -Parent $PROFILE) 'tools\KillLine.ps1'),
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
if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw ("KillLine.ps1 が見つかりません: $ScriptPath`n" +
           "dev リポジトリから配置先へコピーしてください " +
           "(例: Copy-Item .\KillLine.ps1 '$ScriptPath')。")
}

# 実行する PowerShell の本体 (pwsh 優先、なければ Windows PowerShell)
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) {
    $pwsh = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

# KillLine.ps1 へ渡す引数。パスにスペースを含むため内側を二重引用符で囲む。
$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
             "-File `"$ScriptPath`" -IdleThresholdMs $IdleThresholdMs -Quiet"

# schtasks の /TR は 261 文字制限があり長いパスで超過するため、XML 定義を
# /Create /XML で取り込む方式にする (Arguments に文字数制限はない)。
function ConvertTo-XmlText {
    param([string]$Text)
    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

$startBoundary = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
$interval = "PT${IntervalMinutes}M"
$description = "LINE.exe を ${IntervalMinutes} 分ごとに終了 (使用中はスキップ)"

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>$(ConvertTo-XmlText $description)</Description>
  </RegistrationInfo>
  <Triggers>
    <TimeTrigger>
      <StartBoundary>$startBoundary</StartBoundary>
      <Enabled>true</Enabled>
      <Repetition>
        <Interval>$interval</Interval>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
    </TimeTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>$(ConvertTo-XmlText $pwsh)</Command>
      <Arguments>$(ConvertTo-XmlText $arguments)</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$xmlPath = Join-Path ([System.IO.Path]::GetTempPath()) "KillLineTask.xml"
# XML プロローグの encoding="UTF-16" に合わせ Unicode (UTF-16 LE BOM) で書き出す
[System.IO.File]::WriteAllText($xmlPath, $xml, [System.Text.Encoding]::Unicode)

try {
    schtasks.exe /Create /TN $TaskName /XML $xmlPath /F
    if ($LASTEXITCODE -ne 0) {
        throw "タスク '$TaskName' の登録に失敗しました (schtasks 終了コード: $LASTEXITCODE)。"
    }
} finally {
    Remove-Item -LiteralPath $xmlPath -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "タスク '$TaskName' を登録しました (${IntervalMinutes} 分間隔)。"
Write-Host "  実行ファイル : $pwsh"
Write-Host "  スクリプト   : $ScriptPath"
Write-Host ""
Write-Host "確認     : schtasks /Query /TN '$TaskName' /V /FO LIST"
Write-Host "手動実行 : schtasks /Run /TN '$TaskName'"
Write-Host "解除     : .\Register-KillLineTask.ps1 -Unregister"
