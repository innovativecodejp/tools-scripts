<#
.SYNOPSIS
    LINE.exe を終了します。ただし「使用中」とみなせる場合はスキップします。
    -s / -e でタスクスケジューラによる定期実行の登録・解除も行えます。

.DESCRIPTION
    引数なしで実行すると、LINE.exe を直ちに終了します。
    ただし LINE ウィンドウが最前面 (アクティブ) で、かつ直近にキーボード／マウス
    操作があった場合は「入力中」とみなして終了を見送ります。

    判定は Win32 API による近似です。
      - GetForegroundWindow : 最前面ウィンドウのハンドル
      - GetLastInputInfo    : 最後の入力からの経過時間 (OS全体)
    メッセージ入力欄の中身までは判定できないため、厳密な「文字入力中」の
    検出ではない点に注意してください。

    -Schedule (-s) を指定すると、本スクリプトを一定間隔 (既定 30 分) で
    繰り返し実行するタスクをタスクスケジューラに登録します。コンソールを
    開いておく必要はなく、バックグラウンド (非表示) で実行されます。
    登録直後に 1 回目が実行され、以降は指定間隔ごとに実行されます。

    タスクが参照する KillLine.ps1 は、既定で $PROFILE 配下の配置先
    (<$PROFILE のフォルダ>\tools\KillLine.ps1) です。
    dev リポジトリは開発環境とし、配置先へコピーして運用する想定のため、
    この登録を dev から実行しても、タスクは配置先を指すようにします。

    タスクは「ログオン中のみ・現在のユーザー権限」で実行されます
    (LINE のウィンドウ状態を判定できるようにするため)。管理者権限は不要です。

    内部では schtasks.exe を使用します
    (ScheduledTasks の CIM コマンドレットは環境によりアクセス拒否となるため)。

    -End (-e) を指定すると、登録済みタスクを削除して定期実行を停止します。
    -Status を指定すると、登録状況・次回実行時刻を表示します。

.PARAMETER Schedule
    定期実行タスクを登録します。エイリアス: -s

.PARAMETER End
    定期実行タスクを削除します。エイリアス: -e

.PARAMETER Status
    定期実行タスクの登録状況を表示します。

.PARAMETER IdleThresholdMs
    「直近の入力」とみなす最終入力からの経過時間 (ミリ秒)。
    LINE が最前面 かつ 経過がこの値未満 のとき、入力中とみなしてスキップします。
    -Schedule と併用すると、この値が登録するタスクへ引き継がれます。
    既定値: 3000 (3秒)

.PARAMETER Quiet
    指定すると、スキップ時のメッセージを出力しません。

.PARAMETER IntervalMinutes
    -Schedule 指定時の実行間隔 (分)。既定値: 30

.PARAMETER ScriptPath
    -Schedule 指定時、タスクが実行する KillLine.ps1 のパス。
    既定値: <$PROFILE のフォルダ>\tools\KillLine.ps1

.PARAMETER TaskName
    タスク名。既定値: KillLine

.EXAMPLE
    .\KillLine.ps1

.EXAMPLE
    .\KillLine.ps1 -IdleThresholdMs 5000

.EXAMPLE
    .\KillLine.ps1 -s

.EXAMPLE
    .\KillLine.ps1 -s -IntervalMinutes 15

.EXAMPLE
    .\KillLine.ps1 -e
#>

[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
    [Parameter(ParameterSetName = 'Schedule')]
    [Alias('s')]
    [switch]$Schedule,

    [Parameter(ParameterSetName = 'End')]
    [Alias('e')]
    [switch]$End,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,

    [int]$IdleThresholdMs = 3000,

    [Parameter(ParameterSetName = 'Run')]
    [switch]$Quiet,

    [Parameter(ParameterSetName = 'Schedule')]
    [ValidateRange(1, 1440)]
    [int]$IntervalMinutes = 30,

    [Parameter(ParameterSetName = 'Schedule')]
    [string]$ScriptPath,

    [string]$TaskName = 'KillLine'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# schtasks.exe を実行し、終了コードと出力をまとめて返す。
# native コマンドの stderr は $ErrorActionPreference = 'Stop' の下で
# NativeCommandError となり得るため、実行中だけ既定へ戻す。
function Invoke-Schtasks {
    param([string[]]$Arguments)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & schtasks.exe @Arguments 2>&1
        return [PSCustomObject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($output | Out-String).TrimEnd()
        }
    } finally {
        $ErrorActionPreference = $previous
    }
}

# ── 定期実行: 登録 (-Schedule / -s) ──────────────────────────────────
function Register-KillLineTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [int]$IntervalMinutes,
        [int]$IdleThresholdMs
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw ("KillLine.ps1 が見つかりません: $ScriptPath`n" +
               "dev リポジトリから配置先へコピーしてください " +
               "(例: .\InstallPsScript.ps1 tools\KillLine.ps1)。")
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
        $result = Invoke-Schtasks @('/Create', '/TN', $TaskName, '/XML', $xmlPath, '/F')
        if ($result.ExitCode -ne 0) {
            throw ("タスク '$TaskName' の登録に失敗しました " +
                   "(schtasks 終了コード: $($result.ExitCode))。`n$($result.Output)")
        }
    } finally {
        Remove-Item -LiteralPath $xmlPath -ErrorAction SilentlyContinue
    }

    Write-Host ""
    Write-Host "タスク '$TaskName' を登録しました (${IntervalMinutes} 分間隔)。"
    Write-Host "  実行ファイル : $pwsh"
    Write-Host "  スクリプト   : $ScriptPath"
    Write-Host ""
    Write-Host "確認 : KillLine -Status"
    Write-Host "停止 : KillLine -e"
}

# ── 定期実行: 解除 (-End / -e) ───────────────────────────────────────
function Unregister-KillLineTask {
    param([string]$TaskName)

    $result = Invoke-Schtasks @('/Delete', '/TN', $TaskName, '/F')
    if ($result.ExitCode -ne 0) {
        # 未登録でもエラーとせず警告に留める (何度実行しても安全にする)
        Write-Warning "タスク '$TaskName' の削除に失敗しました (未登録の可能性があります)。"
        Write-Verbose $result.Output
        return
    }

    Write-Host "タスク '$TaskName' を削除しました (定期実行を停止)。"
}

# ── 定期実行: 状況表示 (-Status) ─────────────────────────────────────
function Show-KillLineTaskStatus {
    param([string]$TaskName)

    $result = Invoke-Schtasks @('/Query', '/TN', $TaskName, '/FO', 'LIST')
    if ($result.ExitCode -ne 0) {
        Write-Host "タスク '$TaskName' は登録されていません (定期実行は停止中)。"
        Write-Host "登録 : KillLine -s"
        return
    }

    Write-Host $result.Output
}

# 特殊文字を XML のテキストとして安全な形へ変換する。
function ConvertTo-XmlText {
    param([string]$Text)
    $Text.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')
}

switch ($PSCmdlet.ParameterSetName) {
    'Schedule' {
        # 既定の登録先は $PROFILE 配下の配置先。dev リポジトリから実行しても
        # タスクが配置先を指すようにするため、$PSScriptRoot は使わない。
        if (-not $ScriptPath) {
            if ([string]::IsNullOrWhiteSpace($PROFILE)) {
                throw '$PROFILE が解決できませんでした。-ScriptPath で明示してください。'
            }
            $ScriptPath = Join-Path (Split-Path -Parent $PROFILE) 'tools\KillLine.ps1'
        }
        Register-KillLineTask -TaskName $TaskName -ScriptPath $ScriptPath `
            -IntervalMinutes $IntervalMinutes -IdleThresholdMs $IdleThresholdMs
        return
    }
    'End' {
        Unregister-KillLineTask -TaskName $TaskName
        return
    }
    'Status' {
        Show-KillLineTaskStatus -TaskName $TaskName
        return
    }
}

# ── 以降は既定 (Run) : LINE.exe を直ちに終了 ─────────────────────────
Add-Type -ErrorAction SilentlyContinue @'
using System;
using System.Runtime.InteropServices;

public static class KillLineNative
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO
    {
        public uint cbSize;
        public uint dwTime;
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    // 最後の入力からの経過時間 (ミリ秒) を返す
    public static long GetIdleMilliseconds()
    {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii))
        {
            return long.MaxValue; // 取得失敗時は「アイドル」とみなす
        }
        return (long)((uint)Environment.TickCount - lii.dwTime);
    }
}
'@

# LINE プロセス取得 (メインウィンドウを持つもの)
$lineProcess = Get-Process -Name 'LINE' -ErrorAction SilentlyContinue

if ($null -eq $lineProcess) {
    return
}

# 最前面ウィンドウが LINE のものか判定
$foreground = [KillLineNative]::GetForegroundWindow()
$isLineForeground = $false
foreach ($proc in $lineProcess) {
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero -and $proc.MainWindowHandle -eq $foreground) {
        $isLineForeground = $true
        break
    }
}

# 最終入力からの経過時間 (OS全体)
$idleMs = [KillLineNative]::GetIdleMilliseconds()

# LINE が最前面 かつ 直近に入力あり → 入力中とみなしスキップ
if ($isLineForeground -and $idleMs -lt $IdleThresholdMs) {
    if (-not $Quiet) {
        Write-Host "LINE は使用中 (最前面 / 最終入力 ${idleMs}ms 前) のため終了をスキップしました。"
    }
    return
}

Stop-Process -Name 'LINE' -Force -ErrorAction SilentlyContinue
