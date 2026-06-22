<#
.SYNOPSIS
    LINE.exe を終了します。ただし「使用中」とみなせる場合はスキップします。

.DESCRIPTION
    LINE ウィンドウが最前面 (アクティブ) で、かつ直近にキーボード／マウス操作が
    あった場合は「入力中」とみなして終了を見送ります。
    それ以外の場合は LINE を強制終了します。

    判定は Win32 API による近似です。
      - GetForegroundWindow : 最前面ウィンドウのハンドル
      - GetLastInputInfo    : 最後の入力からの経過時間 (OS全体)
    メッセージ入力欄の中身までは判定できないため、厳密な「文字入力中」の
    検出ではない点に注意してください。

.PARAMETER IdleThresholdMs
    「直近の入力」とみなす最終入力からの経過時間 (ミリ秒)。
    LINE が最前面 かつ 経過がこの値未満 のとき、入力中とみなしてスキップします。
    既定値: 3000 (3秒)

.PARAMETER Quiet
    指定すると、スキップ時のメッセージを出力しません。

.PARAMETER LogPath
    指定すると、実行結果 (終了 / スキップ / 未起動) をタイムスタンプ付きで
    このファイルに追記します。親フォルダが無い場合は作成します。

.EXAMPLE
    .\KillLine.ps1

.EXAMPLE
    .\KillLine.ps1 -IdleThresholdMs 5000

.EXAMPLE
    .\KillLine.ps1 -LogPath C:\logs\KillLine.log
#>

[CmdletBinding()]
param(
    [int]$IdleThresholdMs = 3000,
    [switch]$Quiet,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 実行結果をログファイルに追記する (LogPath 未指定なら何もしない)
function Write-KillLineLog {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($LogPath)) { return }
    try {
        $dir = Split-Path -Parent $LogPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    } catch {
        # ログ書き込み失敗で本処理を止めない
        if (-not $Quiet) { Write-Warning "ログ書き込みに失敗しました: $($_.Exception.Message)" }
    }
}

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
    Write-KillLineLog 'LINE は起動していません。'
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
    $msg = "LINE は使用中 (最前面 / 最終入力 ${idleMs}ms 前) のため終了をスキップしました。"
    if (-not $Quiet) {
        Write-Host $msg
    }
    Write-KillLineLog $msg
    return
}

Stop-Process -Name 'LINE' -Force -ErrorAction SilentlyContinue

# プロセス終了の反映を少し待ってから確認
Start-Sleep -Milliseconds 800
$still = Get-Process -Name 'LINE' -ErrorAction SilentlyContinue
if ($null -eq $still) {
    Write-KillLineLog 'LINE を終了しました。'
} else {
    Write-KillLineLog 'LINE の終了を試みましたが、まだ起動しています。'
}
