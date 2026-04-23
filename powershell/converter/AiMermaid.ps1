<#
.SYNOPSIS
    Invoke-AiMermaid — ai-mermaid ブロックを Claude API で Mermaid 構文に変換します
#>

function Invoke-AiMermaid {
    param(
        [string]$MarkdownContent,
        [string]$FilePath,
        [string]$ApiKey,
        [string]$Model,
        [bool]$Strict,
        [bool]$Debug,
        [ref]$TotalInputTokens,
        [ref]$TotalOutputTokens
    )

    $fileName = Split-Path $FilePath -Leaf

    # ai-mermaid ブロックを抽出（種別付き: ```ai-mermaid:type または ```ai-mermaid）
    $blockPattern = '(?s)```ai-mermaid(?::([a-zA-Z]+))?\r?\n(.*?)```'
    $matches = [regex]::Matches($MarkdownContent, $blockPattern)

    if ($matches.Count -eq 0) { return $MarkdownContent }

    Write-Host "[AI]  $fileName`: $($matches.Count)ブロックを生成中..." -ForegroundColor Magenta

    # ブロックをリスト化
    $blocks = @()
    for ($i = 0; $i -lt $matches.Count; $i++) {
        $blocks += [PSCustomObject]@{
            Id       = "BLOCK_$($i + 1)"
            Type     = $matches[$i].Groups[1].Value  # 空文字 = AI判断
            Text     = $matches[$i].Groups[2].Value.Trim()
            Original = $matches[$i].Value
            Line     = ($MarkdownContent.Substring(0, $matches[$i].Index) -split "`n").Count
        }
    }

    # プロンプト構築
    $blocksJson = $blocks | ForEach-Object {
        $typeHint = if ($_.Type) { " 種別ヒント: $($_.Type)" } else { '' }
        "{ `"id`": `"$($_.Id)`",$typeHint `"text`": $(($_.Text | ConvertTo-Json)) }"
    }
    $blocksArray = "[$($blocksJson -join ', ')]"

    $systemPrompt = @'
あなたはMermaid記法の専門家です。
ユーザーが渡す各ブロックのテキストをMermaid構文に変換してください。

ルール:
- 種別ヒントがある場合はその種別を使用する。ない場合はテキストから最適な種別を判断する
- 生成した構文が正しいMermaid構文であることを必ず自己確認してから返す
- コードブロック記号（```）は含めない。Mermaid構文のみを返す
- 結果は必ず以下のJSON配列形式で返す（他のテキストは一切含めない）:
[{"id":"BLOCK_1","status":"ok","mermaid":"..."},{"id":"BLOCK_2","status":"error","error":"理由"}]
'@

    $userPrompt = "以下のブロックをMermaid構文に変換してください:`n$blocksArray"

    $body = [ordered]@{
        model      = $Model
        max_tokens = 2048
        system     = @(
            @{
                type          = 'text'
                text          = $systemPrompt
                cache_control = @{ type = 'ephemeral' }
            }
        )
        messages   = @(@{ role = 'user'; content = $userPrompt })
    } | ConvertTo-Json -Depth 6

    # API呼び出し
    try {
        $response = Invoke-RestMethod `
            -Uri     'https://api.anthropic.com/v1/messages' `
            -Method  Post `
            -Headers @{
                'x-api-key'         = $ApiKey
                'anthropic-version' = '2023-06-01'
                'anthropic-beta'    = 'prompt-caching-2024-07-31'
                'content-type'      = 'application/json'
            } `
            -Body $body
    } catch {
        Write-Host "[AI~] $fileName`: API呼び出し失敗: $($_.Exception.Message)" -ForegroundColor Yellow
        if ($Strict) { return $null }
        return $MarkdownContent
    }

    # トークン集計
    $inputTokens  = $response.usage.input_tokens
    $outputTokens = $response.usage.output_tokens
    $TotalInputTokens.Value  += $inputTokens
    $TotalOutputTokens.Value += $outputTokens

    # レスポンス解析
    $rawText = $response.content[0].text.Trim()
    try {
        $results = $rawText | ConvertFrom-Json
    } catch {
        Write-Host "[AI~] $fileName`: レスポンス解析失敗" -ForegroundColor Yellow
        if ($Strict) { return $null }
        return $MarkdownContent
    }

    # mermaid.parse() 検証用 Node.js スクリプト
    $installDir         = Join-Path $env:LOCALAPPDATA 'md-to-pdf-ps'
    $validateScript     = @'
const fs = require('fs');
const input = JSON.parse(fs.readFileSync(process.argv[2], 'utf-8'));
async function validate() {
  const results = [];
  for (const item of input) {
    if (item.status !== 'ok') { results.push({ id: item.id, valid: false, error: item.error || 'AI生成失敗' }); continue; }
    try {
      const { default: mermaid } = await import('./node_modules/mermaid/dist/mermaid.esm.min.mjs').catch(() => ({ default: null }));
      if (mermaid && typeof mermaid.parse === 'function') {
        await mermaid.parse(item.mermaid);
      }
      results.push({ id: item.id, valid: true });
    } catch(e) {
      results.push({ id: item.id, valid: false, error: e.message || String(e) });
    }
  }
  process.stdout.write(JSON.stringify(results) + '\n');
}
validate().catch(e => { process.stderr.write(e.stack); process.exit(1); });
'@
    $validateScriptPath = Join-Path $env:TEMP "ai-validate-$(Get-Random).mjs"
    $validateInputPath  = Join-Path $env:TEMP "ai-validate-input-$(Get-Random).json"
    $results | ConvertTo-Json -Depth 3 | Set-Content $validateInputPath -Encoding UTF8
    Set-Content $validateScriptPath -Value $validateScript -Encoding UTF8

    try {
        $validateOutput = & node $validateScriptPath $validateInputPath 2>$null
        $validations    = $validateOutput | ConvertFrom-Json
    } catch {
        $validations = $null
    } finally {
        Remove-Item $validateScriptPath, $validateInputPath -ErrorAction SilentlyContinue
    }

    # ブロックごとに置換
    $output   = $MarkdownContent
    $hasError = $false

    foreach ($block in $blocks) {
        $aiResult   = $results     | Where-Object { $_.id -eq $block.Id } | Select-Object -First 1
        $validation = if ($validations) {
            $validations | Where-Object { $_.id -eq $block.Id } | Select-Object -First 1
        } else { $null }

        $succeeded = $aiResult -and $aiResult.status -eq 'ok' -and
                     (-not $validation -or $validation.valid)

        if ($succeeded) {
            $replacement = "``````mermaid`n$($aiResult.mermaid.Trim())`n``````"
            $output = $output.Replace($block.Original, $replacement)
        } else {
            $errMsg = if ($validation -and -not $validation.valid) { $validation.error } `
                      elseif ($aiResult -and $aiResult.error)      { $aiResult.error } `
                      else                                          { '不明なエラー' }
            Write-Host "[AI~] $fileName`: $($block.Id)（$($block.Line)行目付近）構文エラー: $errMsg" -ForegroundColor Yellow
            $hasError = $true

            if (-not $Strict) {
                $fallback = "> ⚠️ AI Mermaid生成失敗 ($($block.Id)): $($block.Text)"
                $output   = $output.Replace($block.Original, $fallback)
            }
        }
    }

    if ($Strict -and $hasError) { return $null }

    Write-Host "[AI✓] $fileName`: $($matches.Count)ブロック生成完了 (入力 $inputTokens / 出力 $outputTokens tokens)" -ForegroundColor Magenta

    if ($Debug) {
        $debugPath = $FilePath + '.ai.md'
        Set-Content -Path $debugPath -Value $output -Encoding UTF8
        Write-Host "    → $debugPath に保存しました" -ForegroundColor Gray
    }

    return $output
}
