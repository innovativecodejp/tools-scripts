# PowerShell スクリプト集

Windows 環境向けの PowerShell 自動化ツールです。

## 動作環境

| 環境 | PowerShell | 備考 |
|---|---|---|
| 開発環境 | **7.6 以上**（推奨） | UTF-8 がデフォルト、BOM 不要 |
| 客先環境 | 5.1 以上 | Windows 標準搭載、スクリプトはどちらでも動作 |

> PS 7 は `winget install Microsoft.PowerShell` で導入できます。

## ツール一覧

### converter — ファイル変換ツール

| スクリプト | 概要 | 詳細 |
|---|---|---|
| [MdToPdf.ps1](converter/MdToPdf.ps1) | Mermaid ダイアグラムを含む Markdown を PDF に一括変換。`-AiMermaid` で自然言語→Mermaid自動生成に対応 | [仕様書](converter/MdToPdf.md) / [AI機能仕様](docs/AiMermaid.md) |
| [Set-AiConfig.ps1](converter/Set-AiConfig.ps1) | Claude API のキーとモデルをユーザー環境変数に保存（`-AiMermaid` 使用前に一度だけ実行） | [仕様書](docs/Set-AiConfig.md) |

## 共通の使い方

PowerShell を開き、スクリプトのあるディレクトリへ移動してから実行してください。

```powershell
# 実行ポリシーの確認（初回のみ）
Get-ExecutionPolicy

# 必要に応じて実行ポリシーを緩和
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## ツール詳細

### MdToPdf.ps1

Mermaid ダイアグラム・シンタックスハイライトに対応した Markdown → PDF 変換スクリプトです。  
Node.js（`marked` / `puppeteer` / `mermaid.js` / `highlight.js`）を内部で使用します。  
初回実行時に npm パッケージを自動インストールします（Chromium 約 170 MB を含む）。

```powershell
# カレントディレクトリの全 .md を変換
.\converter\MdToPdf.ps1 -Pattern "*.md"

# サブディレクトリを再帰検索して ./pdf/ に出力
.\converter\MdToPdf.ps1 -Pattern "docs\*.md" -Recurse -OutputDir ".\pdf" -Force

# AI Mermaid 自動生成を有効化（事前に Set-AiConfig.ps1 の実行が必要）
.\converter\MdToPdf.ps1 -Pattern "*.md" -AiMermaid

# 厳格モード + 中間ファイル保存（学習用）
.\converter\MdToPdf.ps1 -Pattern "*.md" -AiMermaid -AiStrict -AiDebug
```

詳細なパラメーター説明・動作フローは [MdToPdf.md](converter/MdToPdf.md) を参照してください。

### Set-AiConfig.ps1

`-AiMermaid` を使用する前に一度だけ実行し、Claude API の設定を保存します。

```powershell
.\converter\Set-AiConfig.ps1
```

---

## Overview (English)

PowerShell automation scripts for Windows.  
Currently includes **MdToPdf.ps1**, which batch-converts Markdown files (including Mermaid diagrams) to PDF using Node.js and Puppeteer.  
Requires PowerShell 7.6+ (recommended) or 5.1+, and Node.js; npm dependencies are installed automatically on first run.
