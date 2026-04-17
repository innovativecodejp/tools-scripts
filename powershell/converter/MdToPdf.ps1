<#
.SYNOPSIS
    Mermaidダイアグラムを含むMarkdownファイルをPDFに一括変換します

.DESCRIPTION
    Node.js（marked / puppeteer / mermaid.js / highlight.js）を使用して
    Markdownを日本語対応・シンタックスハイライト付きPDFに変換します。
    初回実行時にnpmパッケージをインストールします（確認あり / Chromium 約170MB含む）。

.PARAMETER Pattern
    変換対象のワイルドカードパターン (例: "*.md", "docs\*.md")

.PARAMETER Recurse
    サブディレクトリも再帰的に検索する（-Pattern 使用時のみ有効）

.PARAMETER FileList
    変換対象ファイルパスを1行1ファイルで記述したテキストファイルのパス

.PARAMETER OutputDir
    出力ディレクトリ（省略時は各入力ファイルと同じディレクトリ）

.PARAMETER Force
    既存のPDFファイルを上書きする

.PARAMETER FontSize
    本文フォントサイズ（pt）デフォルト: 12

.PARAMETER Margin
    ページ余白 デフォルト: "20mm"

.PARAMETER FontFamily
    フォントファミリー デフォルト: "Meiryo UI, Yu Gothic UI, Segoe UI, sans-serif"

.PARAMETER HeadingFontSize
    H1のフォントサイズ（em単位）デフォルト: 2.0（H2は1.5em、H3は1.2em）

.EXAMPLE
    .\MdToPdf.ps1 -Pattern "*.md"
    .\MdToPdf.ps1 -Pattern "docs\*.md" -Recurse -OutputDir ".\pdf" -Force
    .\MdToPdf.ps1 -FileList "files.txt" -FontSize 11 -Margin "15mm"
    .\MdToPdf.ps1 -Pattern "*.md" -FontFamily "Yu Gothic, sans-serif" -HeadingFontSize 1.8
#>

[CmdletBinding(DefaultParameterSetName = 'Pattern')]
param(
    [Parameter(ParameterSetName = 'Pattern', Mandatory = $true, Position = 0)]
    [string]$Pattern,

    [Parameter(ParameterSetName = 'Pattern')]
    [switch]$Recurse,

    [Parameter(ParameterSetName = 'FileList', Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$FileList,

    [string]$OutputDir,
    [switch]$Force,
    [int]$FontSize = 12,
    [string]$Margin = '20mm',
    [string]$FontFamily = 'Meiryo UI, Yu Gothic UI, Segoe UI, sans-serif',
    [double]$HeadingFontSize = 2.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── ヘルパー関数 ─────────────────────────────────────────────────────────────
function Write-Step { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[v] $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "[~] $Msg" -ForegroundColor Yellow }
function Write-Fail { param([string]$Msg) Write-Host "[x] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "    $Msg" -ForegroundColor Gray }

# ─── Node.js チェック ─────────────────────────────────────────────────────────
try {
    $null = Get-Command node -ErrorAction Stop
} catch {
    Write-Fail 'Node.js が見つかりません。https://nodejs.org からインストールしてください。'
    exit 1
}

# ─── ファイル収集 ─────────────────────────────────────────────────────────────
[System.Collections.ArrayList]$mdFiles = @()

if ($PSCmdlet.ParameterSetName -eq 'Pattern') {
    $searchDir    = Split-Path $Pattern -Parent
    $searchFilter = Split-Path $Pattern -Leaf
    if ([string]::IsNullOrEmpty($searchDir)) { $searchDir = '.' }

    $found = Get-ChildItem -Path $searchDir -Filter $searchFilter -Recurse:$Recurse -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Extension -ieq '.md' }
    foreach ($f in $found) { $null = $mdFiles.Add($f) }
} else {
    $lines = Get-Content $FileList | Where-Object { $_.Trim() -ne '' }
    foreach ($line in $lines) {
        $item = Get-Item $line.Trim() -ErrorAction SilentlyContinue
        if ($item) { $null = $mdFiles.Add($item) }
        else        { Write-Skip "見つかりません: $line" }
    }
}

if ($mdFiles.Count -eq 0) {
    Write-Fail '変換対象のMarkdownファイルが見つかりませんでした。'
    exit 1
}

# ─── 出力ディレクトリ作成 ────────────────────────────────────────────────────
if ($OutputDir) {
    $OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# ─── ファイルペア構築（上書き確認）──────────────────────────────────────────
[System.Collections.ArrayList]$filePairs = @()
$skipped = 0

foreach ($file in $mdFiles) {
    $outDir  = if ($OutputDir) { $OutputDir } else { $file.DirectoryName }
    $outPath = Join-Path $outDir ([System.IO.Path]::ChangeExtension($file.Name, '.pdf'))

    if ((Test-Path $outPath) -and -not $Force) {
        Write-Skip "$($file.Name) -> スキップ（既に存在。-Force で上書き）"
        $skipped++
        continue
    }
    $null = $filePairs.Add(@{ input = $file.FullName; output = $outPath })
}

if ($filePairs.Count -eq 0) {
    Write-Info "変換するファイルがありません（スキップ: $skipped 件）。"
    exit 0
}

Write-Step "$($filePairs.Count) 件のファイルを変換します（スキップ: $skipped 件）"

# ─── インストールディレクトリ（永続）────────────────────────────────────────
$installDir      = Join-Path $env:LOCALAPPDATA 'md-to-pdf-ps'
$puppeteerCheck  = Join-Path $installDir 'node_modules\puppeteer\package.json'

if (-not (Test-Path $puppeteerCheck)) {
    Write-Step '必要なnpmパッケージがインストールされていません。'
    Write-Info "インストール先: $installDir"
    Write-Info 'パッケージ: marked@9, marked-highlight, highlight.js, mermaid@10, puppeteer@21'
    Write-Info '           （Chromium 約170MB のダウンロードが発生します）'
    $answer = Read-Host 'インストールしますか？ [y/N]'
    if ($answer -notmatch '^[yY]') {
        Write-Info 'キャンセルしました。'
        exit 0
    }

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Set-Content -Path (Join-Path $installDir 'package.json') `
        -Value '{"name":"md-to-pdf-ps","version":"1.0.0","private":true}' -Encoding UTF8

    Write-Step 'パッケージをインストール中（しばらくお待ちください）...'
    Push-Location $installDir
    try {
        & npm install marked@9 marked-highlight highlight.js mermaid@10 puppeteer@21 --save-quiet
        if ($LASTEXITCODE -ne 0) { throw 'npm install に失敗しました' }
    } finally {
        Pop-Location
    }
    Write-Ok 'パッケージのインストール完了'
}

# ─── Node.js 変換スクリプト（インストールディレクトリに書き出し）─────────────
$nodeScript = @'
'use strict';

const fs        = require('fs');
const path      = require('path');
const { marked }          = require('marked');
const { markedHighlight } = require('marked-highlight');
const hljs      = require('highlight.js');
const puppeteer = require('puppeteer');

// ─── 設定読み込み ─────────────────────────────────────
const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf-8'));
const { files, style } = config;
const fileList = Array.isArray(files) ? files : [files];

// ─── marked + highlight.js セットアップ ──────────────
marked.use(markedHighlight({
  langPrefix: 'hljs language-',
  highlight(code, lang) {
    const language = hljs.getLanguage(lang) ? lang : 'plaintext';
    return hljs.highlight(code, { language }).value;
  }
}));

// ─── リソース読み込み ─────────────────────────────────
const hljsCss = fs.readFileSync(
  path.join(__dirname, 'node_modules/highlight.js/styles/github.css'), 'utf-8'
);

// mermaid.min.js は puppeteer 経由で注入するため文字列として読み込む
const mermaidJsPaths = [
  path.join(__dirname, 'node_modules/mermaid/dist/mermaid.min.js'),
  path.join(__dirname, 'node_modules/mermaid/dist/mermaid.js'),
];
let mermaidJs = '';
for (const p of mermaidJsPaths) {
  if (fs.existsSync(p)) { mermaidJs = fs.readFileSync(p, 'utf-8'); break; }
}
if (!mermaidJs) {
  process.stderr.write('警告: mermaid.min.js が見つかりません。Mermaidダイアグラムは描画されません。\n');
}

// ─── HTML 生成 ────────────────────────────────────────
function buildHtml(markdown, inputFile, style, hljsCss) {
  let body = marked.parse(markdown);

  // mermaid コードブロック → div.mermaid に変換
  body = body.replace(
    /<pre><code class="(?:hljs )?language-mermaid">([\s\S]*?)<\/code><\/pre>/gi,
    function(_, code) {
      const decoded = code
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'");
      return '<div class="mermaid">' + decoded.trim() + '</div>';
    }
  );

  // 相対パス解決用 <base>
  const baseHref = 'file:///' + path.dirname(inputFile).replace(/\\/g, '/') + '/';

  const h1em = style.headingFontSize;
  const h2em = (h1em * 0.75).toFixed(2);
  const h3em = (h1em * 0.60).toFixed(2);

  return [
    '<!DOCTYPE html>',
    '<html lang="ja">',
    '<head>',
    '<meta charset="UTF-8">',
    '<base href="' + baseHref + '">',
    '<style>',
    hljsCss,
    '@page { margin: ' + style.margin + '; }',
    '* { box-sizing: border-box; }',
    'body {',
    '  font-family: ' + style.fontFamily + ';',
    '  font-size: ' + style.fontSize + 'pt;',
    '  line-height: 1.7;',
    '  color: #333;',
    '}',
    'h1 { font-size: ' + h1em + 'em; border-bottom: 2px solid #444; padding-bottom: .3em; margin-top: 1.5em; }',
    'h2 { font-size: ' + h2em + 'em; border-bottom: 1px solid #ccc; padding-bottom: .2em; margin-top: 1.2em; }',
    'h3 { font-size: ' + h3em + 'em; margin-top: 1em; }',
    'h4, h5, h6 { margin-top: .8em; }',
    'pre {',
    '  background: #f6f8fa; border: 1px solid #e1e4e8;',
    '  border-radius: 4px; padding: 1em; overflow-x: auto; font-size: .9em;',
    '}',
    'code {',
    '  font-family: Consolas, "Courier New", monospace; font-size: .9em;',
    '  background: #f0f0f0; padding: .1em .4em; border-radius: 3px;',
    '}',
    'pre code { background: none; padding: 0; }',
    'table { border-collapse: collapse; width: 100%; margin: 1em 0; }',
    'th, td { border: 1px solid #ccc; padding: .5em 1em; }',
    'th { background: #f0f0f0; font-weight: bold; }',
    'blockquote {',
    '  border-left: 4px solid #ccc; margin: 1em 0;',
    '  padding: .5em 1em; color: #666; background: #fafafa;',
    '}',
    'img { max-width: 100%; height: auto; }',
    '.mermaid { text-align: center; margin: 1.5em 0; }',
    '.mermaid svg { max-width: 100%; height: auto; }',
    'hr { border: none; border-top: 1px solid #ddd; margin: 2em 0; }',
    '</style>',
    '</head>',
    '<body>',
    body,
    '</body>',
    '</html>'
  ].join('\n');
}

// ─── メイン処理 ───────────────────────────────────────
async function main() {
  const browser = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--allow-file-access-from-files']
  });

  try {
    for (const fileInfo of fileList) {
      const { input, output } = fileInfo;
      const page = await browser.newPage();
      try {
        const markdown = fs.readFileSync(input, 'utf-8');
        const html     = buildHtml(markdown, input, style, hljsCss);

        await page.setContent(html, { waitUntil: 'domcontentloaded', timeout: 30000 });

        // Mermaid.js を注入して実行
        if (mermaidJs) {
          await page.addScriptTag({ content: mermaidJs });
          await page.evaluate(function() {
            return new Promise(function(resolve) {
              mermaid.initialize({ startOnLoad: false, theme: 'default', securityLevel: 'loose' });
              var diagrams = document.querySelectorAll('.mermaid');
              if (diagrams.length === 0) { resolve(); return; }
              if (typeof mermaid.run === 'function') {
                mermaid.run({ querySelector: '.mermaid' }).then(resolve).catch(resolve);
              } else {
                mermaid.init(undefined, diagrams);
                setTimeout(resolve, 2000);
              }
            });
          });

          // SVG レンダリング完了まで待機（最大15秒）
          await page.waitForFunction(function() {
            var nodes = document.querySelectorAll('.mermaid');
            if (nodes.length === 0) return true;
            return Array.from(nodes).every(function(n) { return n.querySelector('svg') !== null; });
          }, { timeout: 15000 }).catch(function() {});
        }

        // 安定待機
        await new Promise(function(r) { setTimeout(r, 300); });

        await page.pdf({
          path:            output,
          format:          'A4',
          printBackground: true,
          margin: {
            top:    style.margin,
            bottom: style.margin,
            left:   style.margin,
            right:  style.margin
          }
        });

        process.stdout.write(JSON.stringify({ status: 'ok', input: input, output: output }) + '\n');
      } catch (err) {
        process.stdout.write(JSON.stringify({ status: 'error', input: input, output: '', error: err.message }) + '\n');
      } finally {
        await page.close();
      }
    }
  } finally {
    await browser.close();
  }
}

main().catch(function(err) {
  process.stderr.write(err.stack + '\n');
  process.exit(1);
});
'@

$nodeScriptPath = Join-Path $installDir 'convert.js'
Set-Content -Path $nodeScriptPath -Value $nodeScript -Encoding UTF8

# ─── 設定 JSON 作成 ──────────────────────────────────────────────────────────
$configObj = [PSCustomObject]@{
    files = [object[]]($filePairs | ForEach-Object { [PSCustomObject]$_ })
    style = [PSCustomObject]@{
        fontSize        = $FontSize
        margin          = $Margin
        fontFamily      = $FontFamily
        headingFontSize = $HeadingFontSize
    }
}
$configPath = Join-Path $env:TEMP "md-pdf-config-$(Get-Random).json"
$configObj | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Encoding UTF8

# ─── 変換実行 ────────────────────────────────────────────────────────────────
$total   = $filePairs.Count
$done    = 0
$success = 0
$failed  = 0

Write-Step '変換を開始します...'

try {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName               = 'node'
    $psi.Arguments              = "`"$nodeScriptPath`" `"$configPath`""
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    while (-not $proc.StandardOutput.EndOfStream) {
        $line = $proc.StandardOutput.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $result = $line | ConvertFrom-Json
            $done++
            $inName = Split-Path $result.input -Leaf
            if ($result.status -eq 'ok') {
                $outName = Split-Path $result.output -Leaf
                $success++
                Write-Ok "[$done/$total] $inName -> $outName"
            } else {
                $failed++
                Write-Fail "[$done/$total] $inName -> エラー: $($result.error)"
            }
        } catch {
            Write-Info $line
        }
    }

    $stderrOut = $proc.StandardError.ReadToEnd().Trim()
    $proc.WaitForExit()

    if ($proc.ExitCode -ne 0 -and $stderrOut) {
        Write-Fail "Node.js エラー:`n$stderrOut"
    }
} finally {
    Remove-Item $configPath -ErrorAction SilentlyContinue
}

# ─── 結果サマリー ────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '----------------------------------------' -ForegroundColor DarkGray
Write-Host "  成功:     $success 件" -ForegroundColor Green
if ($failed  -gt 0) { Write-Host "  失敗:     $failed 件"  -ForegroundColor Red }
if ($skipped -gt 0) { Write-Host "  スキップ: $skipped 件" -ForegroundColor Yellow }
Write-Host '----------------------------------------' -ForegroundColor DarkGray
