<#
    Invoke-AiMermaid のユニットテスト（Pester v5）
    実行: Invoke-Pester .\tests\unit\AiMermaid.Tests.ps1 -Output Detailed
#>

BeforeAll {
    . "$PSScriptRoot\..\..\converter\AiMermaid.ps1"
    $script:FixturesDir   = "$PSScriptRoot\..\fixtures"
    $script:DummyFilePath = 'C:\dummy\test.md'
}

Describe 'ブロック抽出' {

    It 'ai-mermaidブロックがなければ元のコンテンツをそのまま返す' {
        $content   = Get-Content "$($script:FixturesDir)\no-ai-block.md" -Raw -Encoding UTF8
        $inTokens  = 0
        $outTokens = 0

        $result = Invoke-AiMermaid `
            -MarkdownContent   $content `
            -FilePath          $script:DummyFilePath `
            -ApiKey            'dummy' `
            -Model             'claude-sonnet-4-6' `
            -Strict            $false `
            -Debug             $false `
            -TotalInputTokens  ([ref]$inTokens) `
            -TotalOutputTokens ([ref]$outTokens)

        $result   | Should -Be $content
        $inTokens | Should -Be 0
    }

    It 'simple.md から1ブロックを検出してmermaidブロックに置換する' {
        $content = Get-Content "$($script:FixturesDir)\simple.md" -Raw -Encoding UTF8

        Mock Invoke-RestMethod {
            $json = '[{"id":"BLOCK_1","status":"ok","mermaid":"flowchart LR\n    A --> B"}]'
            [PSCustomObject]@{
                content = @([PSCustomObject]@{ text = $json })
                usage   = [PSCustomObject]@{ input_tokens = 100; output_tokens = 50 }
            }
        }

        $inTokens  = 0
        $outTokens = 0
        $result = Invoke-AiMermaid `
            -MarkdownContent   $content `
            -FilePath          $script:DummyFilePath `
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
        $content    = Get-Content "$($script:FixturesDir)\multiple.md" -Raw -Encoding UTF8
        $blockCount = ([regex]::Matches($content, '```ai-mermaid')).Count
        $blockCount | Should -Be 3
    }

    It 'typed.md の種別指定（:sequence, :flowchart）を正しく抽出する' {
        $content = Get-Content "$($script:FixturesDir)\typed.md" -Raw -Encoding UTF8
        $pattern = '```ai-mermaid(?::([a-zA-Z]+))?'
        $m       = [regex]::Matches($content, $pattern)

        $m[0].Groups[1].Value | Should -Be 'sequence'
        $m[1].Groups[1].Value | Should -Be 'flowchart'
    }
}

Describe 'トークン集計' {

    It '複数ファイル処理時にトークンが累積される' {
        $content = Get-Content "$($script:FixturesDir)\simple.md" -Raw -Encoding UTF8

        Mock Invoke-RestMethod {
            $json = '[{"id":"BLOCK_1","status":"ok","mermaid":"flowchart LR\n    A --> B"}]'
            [PSCustomObject]@{
                content = @([PSCustomObject]@{ text = $json })
                usage   = [PSCustomObject]@{ input_tokens = 80; output_tokens = 30 }
            }
        }

        $inTokens  = 0
        $outTokens = 0

        $null = Invoke-AiMermaid -MarkdownContent $content -FilePath $script:DummyFilePath `
            -ApiKey 'dummy' -Model 'claude-sonnet-4-6' -Strict $false -Debug $false `
            -TotalInputTokens ([ref]$inTokens) -TotalOutputTokens ([ref]$outTokens)

        $null = Invoke-AiMermaid -MarkdownContent $content -FilePath $script:DummyFilePath `
            -ApiKey 'dummy' -Model 'claude-sonnet-4-6' -Strict $false -Debug $false `
            -TotalInputTokens ([ref]$inTokens) -TotalOutputTokens ([ref]$outTokens)

        $inTokens  | Should -Be 160
        $outTokens | Should -Be 60
    }
}

Describe 'API失敗時の挙動' {

    BeforeEach {
        $script:content = Get-Content "$($script:FixturesDir)\simple.md" -Raw -Encoding UTF8
    }

    It '-AiStrict なし: API失敗でも元コンテンツを返す' {
        Mock Invoke-RestMethod { throw 'Connection refused' }

        $inTokens  = 0; $outTokens = 0
        $result = Invoke-AiMermaid -MarkdownContent $script:content -FilePath $script:DummyFilePath `
            -ApiKey 'dummy' -Model 'claude-sonnet-4-6' -Strict $false -Debug $false `
            -TotalInputTokens ([ref]$inTokens) -TotalOutputTokens ([ref]$outTokens)

        $result | Should -Be $script:content
    }

    It '-AiStrict あり: API失敗で $null を返す' {
        Mock Invoke-RestMethod { throw 'Connection refused' }

        $inTokens  = 0; $outTokens = 0
        $result = Invoke-AiMermaid -MarkdownContent $script:content -FilePath $script:DummyFilePath `
            -ApiKey 'dummy' -Model 'claude-sonnet-4-6' -Strict $true -Debug $false `
            -TotalInputTokens ([ref]$inTokens) -TotalOutputTokens ([ref]$outTokens)

        $result | Should -BeNullOrEmpty
    }

    It '-AiStrict なし: ブロック生成失敗でblockquoteにフォールバックする' {
        Mock Invoke-RestMethod {
            $json = '[{"id":"BLOCK_1","status":"error","error":"変換できませんでした"}]'
            [PSCustomObject]@{
                content = @([PSCustomObject]@{ text = $json })
                usage   = [PSCustomObject]@{ input_tokens = 50; output_tokens = 10 }
            }
        }

        $inTokens  = 0; $outTokens = 0
        $result = Invoke-AiMermaid -MarkdownContent $script:content -FilePath $script:DummyFilePath `
            -ApiKey 'dummy' -Model 'claude-sonnet-4-6' -Strict $false -Debug $false `
            -TotalInputTokens ([ref]$inTokens) -TotalOutputTokens ([ref]$outTokens)

        $result | Should -Match '> .* AI Mermaid'
        $result | Should -Not -Match '```mermaid'
    }

    It '-AiStrict あり: ブロック生成失敗で $null を返す' {
        Mock Invoke-RestMethod {
            $json = '[{"id":"BLOCK_1","status":"error","error":"変換できませんでした"}]'
            [PSCustomObject]@{
                content = @([PSCustomObject]@{ text = $json })
                usage   = [PSCustomObject]@{ input_tokens = 50; output_tokens = 10 }
            }
        }

        $inTokens  = 0; $outTokens = 0
        $result = Invoke-AiMermaid -MarkdownContent $script:content -FilePath $script:DummyFilePath `
            -ApiKey 'dummy' -Model 'claude-sonnet-4-6' -Strict $true -Debug $false `
            -TotalInputTokens ([ref]$inTokens) -TotalOutputTokens ([ref]$outTokens)

        $result | Should -BeNullOrEmpty
    }
}

Describe '-AiDebug: 中間ファイル保存' {

    It '成功時に .ai.md ファイルが生成される' {
        $content  = Get-Content "$($script:FixturesDir)\simple.md" -Raw -Encoding UTF8
        $tempFile = Join-Path $env:TEMP "pester-test-$(Get-Random).md"

        Mock Invoke-RestMethod {
            $json = '[{"id":"BLOCK_1","status":"ok","mermaid":"flowchart LR\n    A --> B"}]'
            [PSCustomObject]@{
                content = @([PSCustomObject]@{ text = $json })
                usage   = [PSCustomObject]@{ input_tokens = 80; output_tokens = 30 }
            }
        }

        $inTokens  = 0; $outTokens = 0
        $null = Invoke-AiMermaid -MarkdownContent $content -FilePath $tempFile `
            -ApiKey 'dummy' -Model 'claude-sonnet-4-6' -Strict $false -Debug $true `
            -TotalInputTokens ([ref]$inTokens) -TotalOutputTokens ([ref]$outTokens)

        "$tempFile.ai.md" | Should -Exist
        Remove-Item "$tempFile.ai.md" -ErrorAction SilentlyContinue
    }
}
