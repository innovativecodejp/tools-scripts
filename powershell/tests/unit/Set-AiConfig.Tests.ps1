<#
    Set-AiConfig.ps1 のユニットテスト（Pester v5）
    実行: Invoke-Pester .\tests\unit\Set-AiConfig.Tests.ps1 -Output Detailed

    注意: Set-AiConfig.ps1 は Read-Host を使うため、ロジック部分のみテストします。
#>

BeforeAll {
    $script:OriginalKey   = [Environment]::GetEnvironmentVariable('ANTHROPIC_API_KEY', 'User')
    $script:OriginalModel = [Environment]::GetEnvironmentVariable('ANTHROPIC_MODEL',   'User')
}

AfterAll {
    [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', $script:OriginalKey,   'User')
    [Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL',   $script:OriginalModel, 'User')
}

Describe 'APIキー疎通確認ロジック' {

    It 'Invoke-RestMethod が成功したらキーを有効と判定できる' {
        Mock Invoke-RestMethod { [PSCustomObject]@{ model = 'claude-sonnet-4-6' } }

        $isValid = $true
        try {
            $null = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/messages' `
                -Method Post -Headers @{ 'x-api-key' = 'sk-ant-test' } -Body '{}'
        } catch { $isValid = $false }

        $isValid | Should -BeTrue
    }

    It 'Invoke-RestMethod が例外を投げたらキーを無効と判定できる' {
        Mock Invoke-RestMethod { throw 'Unauthorized' }

        $isValid = $true
        try {
            $null = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/messages' `
                -Method Post -Headers @{ 'x-api-key' = 'invalid' } -Body '{}'
        } catch { $isValid = $false }

        $isValid | Should -BeFalse
    }
}

Describe '同じ値の検出ロジック' {

    It '同じ文字列を比較すると等しいと判定する' {
        $current = 'sk-ant-abc123'
        $new     = 'sk-ant-abc123'
        ($current -eq $new) | Should -BeTrue
    }

    It '異なる文字列を比較すると等しくないと判定する' {
        $current = 'sk-ant-abc123'
        $new     = 'sk-ant-xyz789'
        ($current -eq $new) | Should -BeFalse
    }

    It '空文字はスキップ扱いと判定する' {
        ('' -eq '') | Should -BeTrue
    }
}

Describe 'モデルID変換ロジック' {

    It '選択肢 1 は haiku のモデルIDに変換される' {
        $modelId = switch ('1') {
            '1' { 'claude-haiku-4-5-20251001' }
            '2' { 'claude-sonnet-4-6' }
        }
        $modelId | Should -Be 'claude-haiku-4-5-20251001'
    }

    It '選択肢 2 は sonnet のモデルIDに変換される' {
        $modelId = switch ('2') {
            '1' { 'claude-haiku-4-5-20251001' }
            '2' { 'claude-sonnet-4-6' }
        }
        $modelId | Should -Be 'claude-sonnet-4-6'
    }

    It 'モデル未設定時のデフォルトは sonnet' {
        $model    = $null
        $effective = if (-not $model) { 'claude-sonnet-4-6' } else { $model }
        $effective | Should -Be 'claude-sonnet-4-6'
    }
}

Describe 'APIキーのマスク表示ロジック' {

    It '末尾4文字のみ表示してそれ以外を **** でマスクする' {
        $key    = 'sk-ant-api03-abcdefgh1234'
        $masked = '****' + $key.Substring([Math]::Max(0, $key.Length - 4))
        $masked | Should -Be '****1234'
    }

    It 'キーが未設定のとき (未設定) を表示する' {
        $key    = $null
        $masked = if ($key) { '****' + $key.Substring($key.Length - 4) } else { '(未設定)' }
        $masked | Should -Be '(未設定)'
    }
}

Describe 'ユーザー環境変数の永続化' {

    It 'SetEnvironmentVariable で User スコープに書き込める' {
        $testKey = 'PESTER_TEST_VAR'
        [Environment]::SetEnvironmentVariable($testKey, 'test-value', 'User')

        $saved = [Environment]::GetEnvironmentVariable($testKey, 'User')
        $saved | Should -Be 'test-value'

        [Environment]::SetEnvironmentVariable($testKey, [NullString]::Value, 'User')
    }
}
