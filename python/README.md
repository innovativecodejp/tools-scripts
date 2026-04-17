# Python スクリプト集

クロスプラットフォームで動作する Python 自動化ツールです。

## 動作環境

- Python 3.9 以上
- Windows / macOS / Linux

## ツール一覧

> 現在準備中です。ツールが追加され次第、以下の表に記載します。

| スクリプト | カテゴリ | 概要 |
|---|---|---|
| — | — | — |

## ディレクトリ構成（予定）

```
python/
├── converter/    # ファイル変換ツール
├── network/      # ネットワーク関連ツール
└── utility/      # 汎用ユーティリティ
```

## 共通の使い方

```bash
# 仮想環境を作成して有効化（推奨）
python -m venv .venv
source .venv/bin/activate        # macOS / Linux
.venv\Scripts\activate           # Windows

# 依存パッケージのインストール（各ツールの requirements.txt がある場合）
pip install -r requirements.txt
```

## コントリビューション

- 依存パッケージがある場合は `requirements.txt` を同梱してください。
- Python 3.9 以上との互換性を維持してください。
- 型ヒント（Type Hints）の使用を推奨します。

---

## Overview (English)

Cross-platform Python automation scripts compatible with Windows, macOS, and Linux.  
Requires Python 3.9 or later. Using a virtual environment is recommended.  
Tools will be added progressively; see the table above for the current list.
