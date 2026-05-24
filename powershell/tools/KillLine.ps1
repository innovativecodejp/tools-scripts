<#
.SYNOPSIS
    LINE.exe が実行中であれば無条件に終了します。

.EXAMPLE
    .\KillLine.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$lineProcess = Get-Process -Name 'LINE' -ErrorAction SilentlyContinue

if ($null -ne $lineProcess) {
    Stop-Process -Name 'LINE' -Force -ErrorAction SilentlyContinue
}
