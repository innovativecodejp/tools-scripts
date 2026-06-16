# $PROFILE を基準に、各カテゴリのスクリプト配置先をまとめて定義します。
$Global:ProfileDir = Split-Path -Parent $PROFILE
$Global:ConverterDir = $Global:ProfileDir + '\converter\'
$Global:ToolsDir = $Global:ProfileDir + '\tools\'
$Global:FileDir = $Global:ProfileDir + '\file\'
$Global:MailDir = $Global:ProfileDir + '\mail\'
$Global:DocsDir = $Global:ProfileDir + '\docs\'
$Global:ExcelDir = $Global:ProfileDir + '\excel\'

<#
.SYNOPSIS
    tools\KillLine.ps1 を実行して LINE.exe を終了します。
#>
function KillLine {
    # tools 配下の実体スクリプトを組み立てます。
    $scriptPath = $Global:ToolsDir + 'KillLine.ps1'

    # スクリプト未配置の状態で実行された場合は明示的に停止します。
    if (-not (Test-Path $scriptPath)) {
        throw "Script not found: $scriptPath"
    }

    # 実体スクリプトを実行します。
    & $scriptPath
}

# converter\MdToPdf.ps1 をドットソースで読み込み、MdToPdf 関数を登録します。
$mdToPdfPath = $Global:ConverterDir + 'MdToPdf.ps1'
if (Test-Path $mdToPdfPath) {
    # 関数をセッションに登録するため、& ではなくドットソースで読み込みます。
    . $mdToPdfPath
}
