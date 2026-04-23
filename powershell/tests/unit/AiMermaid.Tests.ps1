<#
    Invoke-AiMermaid のユニットテスト（Pester v5）
    実行: Invoke-Pester .\tests\unit\AiMermaid.Tests.ps1 -Output Detailed
#>

BeforeAll {
    . "$PSScriptRoot\..\..\converter\AiMermaid.ps1"

    $FixturesDir = "$PSScriptRoot\..\fixtures"

    # テスト用ダミーファイルパス（実ファイル不要、名前のみ使用）
    $DummyFilePath = 'C:\dummy\test.md'
}

# ──────────────────────────────────────────────────────────────────────────────
Describe 'ブロック抽出' {

    It 'ai-mermaidブロックがなければ元のコンテンツをそのまま返す' {
        $content = Get-Content "$FixturesDir\no-ai-block.md" -Raw
        $inTokens  = 0
        $outTokens = 0

        $result = Invoke-AiMermaid `
            -MarkdownContent   $content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $result   | Should -Be $content
        $inTokens | Should -Be 0
    }

    It 'simple.md から1ブロックを抽出してAPIに渡す' {
        $content = Get-Content "$FixturesDir\simple.md" -Raw

        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                content = @([PSCustomObject]@{
                    text = '[{"id":"BLOCK_1","status":"ok","mermaid":"flowchart LR\n    A[ユーザー] --> B[APIサーバー]"}]'
                })
                usage   = [PSCustomObject]@{ input_tokens = 100; output_tokens = 50 }
            }
        }

        $inTokens  = 0
        $outTokens = 0
        $result = Invoke-AiMermaid `
            -MarkdownContent   $content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $result    | Should -Match '```mermaid'
        $result    | Should -Not -Match '```ai-mermaid'
        $inTokens  | Should -Be 100
        $outTokens | Should -Be 50
    }

    It 'multiple.md から3ブロックをすべて検出する' {
        $content = Get-Content "$FixturesDir\multiple.md" -Raw
        $blockCount = ([regex]::Matches($content, '```ai-mermaid')).Count
        $blockCount | Should -Be 3
    }

    It 'typed.md の種別指定（:sequence, :flowchart）を正しく抽出する' {
        $content = Get-Content "$FixturesDir\typed.md" -Raw
        $pattern = '```ai-mermaid(?::([a-zA-Z]+))?'
        $m = [regex]::Matches($content, $pattern)

        $m[0].Groups[1].Value | Should -Be 'sequence'
        $m[1].Groups[1].Value | Should -Be 'flowchart'
    }
}

# ──────────────────────────────────────────────────────────────────────────────
Describe 'トークン集計' {

    It '複数ファイル処理時にトークンが累積される' {
        $content = Get-Content "$FixturesDir\simple.md" -Raw

        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                content = @([PSCustomObject]@{
                    text = '[{"id":"BLOCK_1","status":"ok","mermaid":"flowchart LR\n    A --> B"}]'
                })
                usage = [PSCustomObject]@{ input_tokens = 80; output_tokens = 30 }
            }
        }

        $inTokens  = 0
        $outTokens = 0

        # 1回目
        $null = Invoke-AiMermaid `
            -MarkdownContent   $content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        # 2回目
        $null = Invoke-AiMermaid `
            -MarkdownContent   $content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $inTokens  | Should -Be 160
        $outTokens | Should -Be 60
    }
}

# ──────────────────────────────────────────────────────────────────────────────
Describe 'API失敗時の挙動' {

    BeforeEach {
        $script:content = Get-Content "$FixturesDir\simple.md" -Raw
    }

    It '-AiStrict なし: API失敗でも元コンテンツを返す' {
        Mock Invoke-RestMethod { throw 'Connection refused' }

        $inTokens  = 0
        $outTokens = 0
        $result = Invoke-AiMermaid `
            -MarkdownContent   $script:content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $result | Should -Be $script:content
    }

    It '-AiStrict あり: API失敗で $null を返す' {
        Mock Invoke-RestMethod { throw 'Connection refused' }

        $inTokens  = 0
        $outTokens = 0
        $result = Invoke-AiMermaid `
            -MarkdownContent   $script:content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $true `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $result | Should -BeNullOrEmpty
    }

    It '-AiStrict なし: ブロック生成失敗でblockquoteにフォールバックする' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                content = @([PSCustomObject]@{
                    text = '[{"id":"BLOCK_1","status":"error","error":"変換できませんでした"}]'
                })
                usage = [PSCustomObject]@{ input_tokens = 50; output_tokens = 10 }
            }
        }

        $inTokens  = 0
        $outTokens = 0
        $result = Invoke-AiMermaid `
            -MarkdownContent   $script:content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $result | Should -Match '> ⚠️ AI Mermaid生成失敗'
        $result | Should -Not -Match '```mermaid'
    }

    It '-AiStrict あり: ブロック生成失敗で $null を返す' {
        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                content = @([PSCustomObject]@{
                    text = '[{"id":"BLOCK_1","status":"error","error":"変換できませんでした"}]'
                })
                usage = [PSCustomObject]@{ input_tokens = 50; output_tokens = 10 }
            }
        }

        $inTokens  = 0
        $outTokens = 0
        $result = Invoke-AiMermaid `
            -MarkdownContent   $script:content `
            -FilePath          $DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $true `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $result | Should -BeNullOrEmpty
    }
}

# ──────────────────────────────────────────────────────────────────────────────
Describe '-AiDebug: 中間ファイル保存' {

    It '成功時に .ai.md ファイルが生成される' {
        $content  = Get-Content "$FixturesDir\simple.md" -Raw
        $tempFile = Join-Path $env:TEMP "pester-test-$(Get-Random).md"

        Mock Invoke-RestMethod {
            [PSCustomObject]@{
                content = @([PSCustomObject]@{
                    text = '[{"id":"BLOCK_1","status":"ok","mermaid":"flowchart LR\n    A --> B"}]'
                })
                usage = [PSCustomObject]@{ input_tokens = 80; output_tokens = 30 }
            }
        }

        $inTokens  = 0
        $outTokens = 0
        $null = Invoke-AiMermaid `
            -MarkdownContent   $content `
            -FilePath          $tempFile `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $true `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $debugFile = "$tempFile.ai.md"
        $debugFile | Should -Exist

        # 後始末
        Remove-Item $debugFile -ErrorAction SilentlyContinue
    }
}
