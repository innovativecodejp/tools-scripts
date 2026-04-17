# PowerShell スクリプト集

Windows 環境向けの PowerShell 自動化ツールです。

## 動作環境

- Windows 10 / 11
- PowerShell 5.1 以上

## ツール一覧

### converter — ファイル変換ツール

| スクリプト | 概要 | 詳細 |
|---|---|---|
| [MdToPdf.ps1](converter/MdToPdf.ps1) | Mermaid ダイアグラムを含む Markdown を PDF に一括変換 | [仕様書](converter/MdToPdf.md) |

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
```

詳細なパラメーター説明・動作フローは [MdToPdf.md](converter/MdToPdf.md) を参照してください。

---

## Overview (English)

PowerShell automation scripts for Windows.  
Currently includes **MdToPdf.ps1**, which batch-converts Markdown files (including Mermaid diagrams) to PDF using Node.js and Puppeteer.  
Requires PowerShell 5.1+ and Node.js; npm dependencies are installed automatically on first run.
