<#
.SYNOPSIS
    Claude API の設定（APIキー・モデル）をユーザー環境変数に保存します

.DESCRIPTION
    ANTHROPIC_API_KEY と ANTHROPIC_MODEL をユーザー環境変数として永続保存します。
    既存の設定がある場合は表示した上で変更を促します。
    Enterキーでスキップすると現在の値を維持します。

.EXAMPLE
    .\Set-AiConfig.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Ok   { param([string]$Msg) Write-Host "[v] $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "[~] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "[x] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Gray }

# ─── 現在の設定を取得 ────────────────────────────────────────────────────────
$currentKey   = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'User')
$currentModel = [Environment]::GetEnvironmentVariable('ANTHROPIC_MODEL',   'User')

if (-not $currentModel) { $currentModel = 'claude-sonnet-4-6' }

# ─── 現在の設定を表示 ────────────────────────────────────────────────────────
$maskedKey = if ($currentKey) {
    $visible = $currentKey.Substring([Math]::Max(0, $currentKey.Length - 4))
    "****$visible"
} else {
    '(未設定)'
}

$modelLabel = switch ($currentModel) {
    'claude-haiku-4-5-20251001' { 'haiku' }
    'claude-sonnet-4-6'         { 'sonnet' }
    default                     { $currentModel }
}

Write-Host ''
Write-Info "現在の設定: モデル=$modelLabel / APIキー=$maskedKey"
Write-Host ''

# ─── APIキー入力 ─────────────────────────────────────────────────────────────
$newKeyRaw = Read-Host 'APIキーを入力してください (Enterでスキップ)'
$newKey    = $newKeyRaw.Trim()

# ─── モデル選択 ──────────────────────────────────────────────────────────────
$newModelRaw = Read-Host 'モデルを選択 [1:haiku / 2:sonnet] (Enterでスキップ)'
$newModelRaw = $newModelRaw.Trim()

$newModel = switch ($newModelRaw) {
    '1'  { 'claude-haiku-4-5-20251001' }
    '2'  { 'claude-sonnet-4-6' }
    ''   { $null }
    default {
        Write-Fail "無効な選択です: '$newModelRaw'。1 または 2 を入力してください。"
        exit 1
    }
}

Write-Host ''

# ─── APIキーの処理 ───────────────────────────────────────────────────────────
$keyToSave = $currentKey

if ($newKey -eq '') {
    # スキップ
} elseif ($newKey -eq $currentKey) {
    Write-Skip 'APIキー: 変更なし（同じ値です）'
} else {
    # 疎通確認
    Write-Host '[*] APIキーを確認中...' -ForegroundColor Cyan

    $testModel = if ($newModel) { $newModel } else { $currentModel }

    try {
        $body = @{
            model      = $testModel
            max_tokens = 16
            messages   = @(@{ role = 'user'; content = 'Hi' })
        } | ConvertTo-Json -Depth 3

        $response = Invoke-RestMethod `
            -Uri    'https://api.anthropic.com/v1/messages' `
            -Method Post `
            -Headers @{
                'x-api-key'         = $newKey
                'anthropic-version' = '2023-06-01'
                'content-type'      = 'application/json'
            } `
            -Body $body

        $confirmedModel = $response.model
        Write-Ok "接続成功 ($confirmedModel)"
        $keyToSave = $newKey
    } catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 401) {
            Write-Fail 'APIキーが無効です。設定を中止します。'
        } else {
            Write-Fail "接続エラー (HTTP $status): $($_.Exception.Message)"
        }
        exit 1
    }
}

# ─── モデルの処理 ────────────────────────────────────────────────────────────
$modelToSave = $currentModel

if ($null -eq $newModel) {
    # スキップ
} elseif ($newModel -eq $currentModel) {
    Write-Skip "モデル: 変更なし（同じ値です）"
} else {
    $modelToSave = $newModel
}

# ─── 保存 ────────────────────────────────────────────────────────────────────
$saved = $false

if ($newKey -ne '' -and $newKey -ne $currentKey) {
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $keyToSave, 'User')
    $env:ANTHROPIC_API_KEY = $keyToSave
    Write-Ok 'APIキー: 更新しました'
    $saved = $true
}

if ($null -ne $newModel -and $newModel -ne $currentModel) {
    [Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL', $modelToSave, 'User')
    $env:ANTHROPIC_MODEL = $modelToSave
    $newLabel = switch ($modelToSave) {
        'claude-haiku-4-5-20251001' { 'haiku' }
        'claude-sonnet-4-6'         { 'sonnet' }
        default                     { $modelToSave }
    }
    Write-Ok "モデル: $newLabel に変更しました"
    $saved = $true
}

if (-not $saved) {
    Write-Info '設定に変更はありませんでした。'
} else {
    Write-Host ''
    Write-Info '設定はユーザー環境変数に保存されました（次回以降も有効です）。'
}

Write-Host ''
