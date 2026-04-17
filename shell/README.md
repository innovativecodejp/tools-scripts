# Shell スクリプト集

macOS / Linux 向けの Bash / Zsh 自動化ツールです。

## 動作環境

- macOS 12 以上 / Ubuntu 20.04 以上（またはその他の Linux ディストリビューション）
- Bash 4.x 以上、または Zsh 5.x 以上

> Windows 上で使用する場合は WSL2（Windows Subsystem for Linux）を推奨します。

## WSL2 セットアップ（Windows ユーザー向け）

### インストール

```powershell
# PowerShell（管理者）で実行
wsl --install

# 特定のディストリビューションを指定する場合
wsl --install -d Ubuntu-24.04
```

インストール後、PC を再起動してください。

### 利用可能なディストリビューションの確認

```powershell
wsl --list --online   # インストール可能な一覧
wsl --list --verbose  # インストール済みの一覧
```

### WSL2 からスクリプトを実行する

```bash
# Windows のドライブは /mnt/ 以下にマウントされています
cd /mnt/d/dev/tools-scripts/shell

# 実行権限を付与して実行
chmod +x script_name.sh
./script_name.sh
```

### Windows ↔ WSL2 のパス変換

| Windows パス | WSL2 パス |
|---|---|
| `C:\Users\username` | `/mnt/c/Users/username` |
| `D:\dev\tools-scripts` | `/mnt/d/dev/tools-scripts` |

### 注意事項

- Windows ファイルシステム（`/mnt/c/` など）上のスクリプトは実行権限が付与できない場合があります。その際はスクリプトを WSL2 のホームディレクトリ（`~/`）にコピーして実行してください。
- 改行コードが `CRLF` のスクリプトはエラーになることがあります。`dos2unix` コマンドで変換してください。

```bash
# dos2unix のインストール
sudo apt install dos2unix

# 改行コードを LF に変換
dos2unix script_name.sh
```

## ツール一覧

> 現在準備中です。ツールが追加され次第、以下の表に記載します。

| スクリプト | カテゴリ | 概要 |
|---|---|---|
| — | — | — |

## ディレクトリ構成（予定）

```
shell/
├── git/          # Git 操作補助ツール
├── system/       # システム管理ツール
└── utility/      # 汎用ユーティリティ
```

## 共通の使い方

```bash
# 実行権限を付与
chmod +x script_name.sh

# スクリプトを実行
./script_name.sh
```

## コントリビューション

- スクリプト先頭に shebang（`#!/usr/bin/env bash` など）を記載してください。
- `set -euo pipefail` を使用してエラーハンドリングを強化することを推奨します。
- macOS の BSD コマンドと Linux の GNU コマンドの差異に注意してください。

---

## Overview (English)

Shell automation scripts (Bash / Zsh) for macOS and Linux.  
Requires Bash 4.x+ or Zsh 5.x+. Windows users should use WSL2.  
Tools will be added progressively; see the table above for the current list.
