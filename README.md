# tools-scripts

日々の作業を自動化・効率化するための汎用スクリプト集です。  
PowerShell / Python / Shell の各言語別にツールを整理しています。

## ディレクトリ構成

```
tools-scripts/
├── powershell/   # Windows 向け PowerShell スクリプト群
├── python/       # クロスプラットフォーム Python スクリプト群
└── shell/        # macOS / Linux 向け Bash/Zsh スクリプト群
```

## カテゴリ別 README

| ディレクトリ | 説明 |
|---|---|
| [powershell/](powershell/README.md) | PowerShell ツール一覧・使用方法 |
| [python/](python/README.md) | Python ツール一覧・使用方法 |
| [shell/](shell/README.md) | Shell ツール一覧・使用方法 |

## 収録ツール一覧

### PowerShell

| ツール | 場所 | 概要 |
|---|---|---|
| MdToPdf.ps1 | [powershell/converter/](powershell/converter/) | Mermaid 対応 Markdown → PDF 一括変換 |

### Python

> 準備中

### Shell

> 準備中

## 動作環境

| カテゴリ | 要件 |
|---|---|
| PowerShell | Windows 10/11、PowerShell 5.1 以上 |
| Python | Python 3.9 以上（クロスプラットフォーム） |
| Shell | macOS / Linux、Bash 4.x 以上または Zsh |

## コントリビューション

1. ツールは言語別ディレクトリに配置してください。
2. 各ツールには個別の説明ファイル（`.md`）を同梱してください。
3. ツール追加時は対応する `README.md` のツール一覧を更新してください。

---

## Overview (English)

A collection of general-purpose automation scripts organized by language (PowerShell, Python, Shell).  
Each subdirectory contains tools aimed at improving day-to-day development workflows.  
Currently includes a PowerShell script for batch-converting Markdown files (with Mermaid diagrams) to PDF.
