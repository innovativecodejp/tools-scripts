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
    ラッパー関数の共通処理。実体スクリプトを実行し、-Help 系の引数は
    実体スクリプトのヘルプ表示へ回します。

.DESCRIPTION
    ラッパー関数は & で実体スクリプトを呼ぶだけのため、Get-Help <関数名> では
    ラッパー自身の SYNOPSIS 1 行しか出ず、実体スクリプトの DESCRIPTION /
    PARAMETER / EXAMPLE が届きません。日常の呼び出し口はラッパー側なので、
    -Help / --help / -h / /? を受け取ったら実体スクリプトのコメントベースヘルプを
    表示してこの差を埋めます。

    実体スクリプト側は -Help を定義していないため、素通しすると
    「パラメーターが見つかりません」で失敗します。必ずここで捕まえます。

    -? は対象外です。コメントベースヘルプを持つ関数では PowerShell 自身が
    -? を横取りして関数側のヘルプを表示するため、ここまで届きません
    (ヘルプの無い単純関数でのみ $args に入ります)。そのためラッパーの
    SYNOPSIS には -Help の案内を書き、-? でも辿れるようにしています。
#>
function Invoke-ToolScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [object[]]$Arguments = @()
    )

    # スクリプト未配置の状態で実行された場合は明示的に停止します。
    if (-not (Test-Path $ScriptPath)) {
        throw "Script not found: $ScriptPath"
    }

    # ヘルプ要求は実体スクリプトへ渡さず、ここで Get-Help に振り替えます。
    foreach ($a in $Arguments) {
        if ($a -is [string] -and $a -in @('-Help', '--help', '-h', '/?')) {
            Get-Help $ScriptPath -Full
            return
        }
    }

    # 実体スクリプトを実行します(引数はそのまま渡します)。
    & $ScriptPath @Arguments
}

<#
.SYNOPSIS
    tools\KillLine.ps1 を実行して LINE.exe を終了します。
    -s で定期実行の登録、-e で解除、-Status で状況表示を行います。
    -Help で実体スクリプトのヘルプを表示します。
#>
function KillLine {
    Invoke-ToolScript -ScriptPath ($Global:ToolsDir + 'KillLine.ps1') -Arguments $args
}

# converter\MdToPdf.ps1 をドットソースで読み込み、MdToPdf 関数を登録します。
$mdToPdfPath = $Global:ConverterDir + 'MdToPdf.ps1'
if (Test-Path $mdToPdfPath) {
    # 関数をセッションに登録するため、& ではなくドットソースで読み込みます。
    . $mdToPdfPath
}

<#
.SYNOPSIS
    tools\InstallPsScript.ps1 を実行します。-Help でヘルプを表示します。
#>
function InstallPsScript {
    Invoke-ToolScript -ScriptPath ($Global:ToolsDir + 'InstallPsScript.ps1') -Arguments $args
}

# 組み込みエイリアス Diff (Compare-Object) は関数より優先されるため解除します。
if (Test-Path Alias:Diff) {
    Remove-Item -LiteralPath Alias:Diff -Force
}

<#
.SYNOPSIS
    tools\Diff.ps1 を実行します。-Help でヘルプを表示します。
#>
function Diff {
    Invoke-ToolScript -ScriptPath ($Global:ToolsDir + 'Diff.ps1') -Arguments $args
}

<#
.SYNOPSIS
    tools\CheckPsTools.ps1 を実行します。-Help でヘルプを表示します。
#>
function CheckPsTools {
    Invoke-ToolScript -ScriptPath ($Global:ToolsDir + 'CheckPsTools.ps1') -Arguments $args
}
