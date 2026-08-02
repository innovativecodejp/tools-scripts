# PowerShell スクリプト集

Windows 環境向けの PowerShell 自動化ツールです。

## 動作環境

| 環境 | PowerShell | 備考 |
|---|---|---|
| 必須 | **7.0 以上** | 各スクリプトが `#Requires -Version 7.0` を宣言 |
| 推奨 | 7.6 以上 | 開発・動作確認環境。UTF-8 がデフォルト、BOM 不要 |

> PS 7 は `winget install Microsoft.PowerShell` で導入できます。

### Windows PowerShell 5.1 では動作しません

本リポジトリのスクリプトは **UTF-8 BOM なし + LF** で管理しています。  
PowerShell 5.1 は BOM なしファイルをシステム既定エンコーディング（日本語環境では CP932 / Shift-JIS）として読むため、日本語を含むスクリプトはパースエラーになります。

```
# Windows PowerShell 5.1 でのパース結果
Unexpected token '}' in expression or statement.
```

BOM を付ければ 5.1 でも動作しますが、PS 7 の既定（BOM なし）から外れて形式が揺れるため、リポジトリは PS 7 専用に統一する方針です。  
5.1 環境へ配布する必要がある場合は、**配布時に BOM 付きへ変換**してください（手順は [MdToPdf.md](converter/MdToPdf.md#客先環境ps-51への配布時の注意) を参照）。

形式が揃っているかは `CheckPsTools` のエンコーディングチェックで確認できます。

```powershell
CheckPsTools
# === エンコーディングチェック (BOM なし + LF) ===
# OK (11 件すべて BOM なし + LF)
```

`.gitattributes` で `*.ps1` などの改行を LF に固定しているため、clone / チェックアウト時にも形式は保たれます。

## ツール一覧

### converter — ファイル変換ツール

| スクリプト | 概要 | 詳細 |
|---|---|---|
| [MdToPdf.ps1](converter/MdToPdf.ps1) | Mermaid ダイアグラムを含む Markdown を PDF に一括変換。`-AiMermaid` で自然言語→Mermaid自動生成に対応 | [仕様書](converter/MdToPdf.md) / [AI機能仕様](docs/AiMermaid.md) |
| [Set-AiConfig.ps1](converter/Set-AiConfig.ps1) | Claude API のキーとモデルをユーザー環境変数に保存（`-AiMermaid` 使用前に一度だけ実行） | [仕様書](docs/Set-AiConfig.md) |

### tools — ユーティリティ

| スクリプト | 概要 | 詳細 |
|---|---|---|
| [Diff.ps1](tools/Diff.ps1) | 指定したファイル／フォルダの差分を TortoiseGit の GUI で開く。2ファイル比較・リビジョン指定にも対応 | [仕様書](docs/Diff.md) |
| [KillLine.ps1](tools/KillLine.ps1) | LINE.exe を終了（使用中はスキップ）。`-s` でタスクスケジューラによる定期実行を登録、`-e` で解除 | – |
| [InstallPsScript.ps1](tools/InstallPsScript.ps1) | スクリプトを `$PROFILE` 配下へ複写し、拡張子なしで起動できるラッパー関数をプロファイルへ追加。`-c` で複写のみ | – |
| [CheckPsTools.ps1](tools/CheckPsTools.ps1) | 各スクリプトが `$PROFILE` 配下へインストール済みか、`.ps1` が BOM なし + LF に揃っているかをチェック（読み取り専用） | – |

## プロファイル

| ファイル | 概要 | 用途 |
|---|---|---|
| [Microsoft.PowerShell_profile.ps1](Microsoft.PowerShell_profile.ps1) | PowerShell 7 用のプロファイルファイル。現在は `KillLine` / `InstallPsScript` / `Diff` 関数と `MdToPdf` の読み込みを定義しています。 | リポジトリで管理し、使用時は PowerShell 7 の `$PROFILE` が指す実際のパスへ配置して利用します。 |

PowerShell 7 では、現在のプロファイル配置先を次のコマンドで確認できます。

```powershell
$PROFILE
```

このリポジトリ上の `Microsoft.PowerShell_profile.ps1` は、PowerShell 7 のプロファイル本体として使う前提の管理用ファイルです。必要な設定をここに追記し、実運用時は `$PROFILE` の実パスに配置してください。

運用時は、`Microsoft.PowerShell_profile.ps1` と同じディレクトリ配下に `converter/` `tools/` `mail/` `file/` などのフォルダをこのリポジトリと同様の構成で配置して使用します。

プロファイルに定義された関数は、いずれも `tools\` 配下の実体スクリプトを呼び出します。引数はそのままスクリプトへ渡されます。関数定義は `InstallPsScript.ps1` が自動生成します。

```powershell
# LINE.exe を直ちに終了（使用中とみなせる場合はスキップ）
KillLine

# 30 分間隔の定期実行をタスクスケジューラに登録（登録直後に 1 回実行）
KillLine -s

# 定期実行を停止（タスクを削除）
KillLine -e

# 登録状況・次回実行時刻を表示
KillLine -Status
```

`-s` が登録するタスクは「ログオン中のみ・現在のユーザー権限（昇格不要）」で非表示実行されます。タスクが参照するのは `$PROFILE` 配下の配置先（`<$PROFILE のフォルダ>\tools\KillLine.ps1`）のため、dev リポジトリから `-s` を実行する場合も、事前に `InstallPsScript.ps1 tools\KillLine.ps1` で配置しておいてください。

## 共通の使い方

PowerShell を開き、スクリプトのあるディレクトリへ移動してから実行してください。

```powershell
# 実行ポリシーの確認（初回のみ）
Get-ExecutionPolicy

# 必要に応じて実行ポリシーを緩和
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## ツール詳細

### InstallPsScript.ps1

スクリプトを `$PROFILE` 配下へ複写し、拡張子なしで起動できるラッパー関数をプロファイルへ追加します。

```powershell
# 複写 + 関数登録 + $PROFILE 同期
.\powershell\tools\InstallPsScript.ps1 tools\Diff.ps1

# 複写のみ（既にインストール済みのスクリプトを修正して置き直す場合）
.\powershell\tools\InstallPsScript.ps1 tools\Diff.ps1 -c
```

> **`-CopyOnly` (`-c`) を使う場面**  
> 既に登録済みのスクリプトを修正しただけなら、関数登録（③）は不要です。`-c` を付けると複写だけを行います。

> **関数ライブラリ形式は自動でスキップされます**  
> `MdToPdf.ps1` や `AiMermaid.ps1` のように**ファイル全体が関数定義だけ**で構成されたスクリプトは、実行しても関数を定義するだけで何も起きません（`&` で呼ぶと子スコープで定義が消えます）。  
> この形式にラッパー関数を作ると、プロファイル前半でドットソース登録された本体を**後から上書き**してしまい、エラーも出ずに無反応になります。  
> そのため AST を解析して自動検出し、③④ をスキップしてドットソースの記述例を案内します。プロファイルには手動で `. ($Global:ConverterDir + 'MdToPdf.ps1')` のように記述してください。

### Diff.ps1

指定したファイル／フォルダの差分を TortoiseGit の GUI（既定では TortoiseGitMerge）で開きます。  
`TortoiseGitProc.exe` はレジストリ・`PATH`・既定のインストール先の順に自動探索します。

```powershell
# 作業ツリーの内容と HEAD(BASE) を比較
Diff .\src\App.cs

# 2 ファイルを直接比較（Git 管理下でなくても可）
Diff .\a.txt .\b.txt

# リビジョンを指定して比較
Diff .\src\App.cs -s HEAD~3 -e HEAD

# unified diff 形式で開き、120 行目へスクロール
Diff .\src\App.cs -Unified -Line 120

# フォルダ指定 → 変更確認ダイアログ（引数なしならカレント）
Diff .\src

# 実際には起動せず、組み立てられるコマンドラインだけ確認
Diff .\src\App.cs -WhatIf
```

> **注意**: `diff` は `Compare-Object` への組み込みエイリアスで、PowerShell の解決順（Alias > Function）により
> 関数より優先されます。そのためプロファイルでは `Diff` 関数の定義前にこのエイリアスを解除しています。
> `Compare-Object` 本体と `compare` エイリアスは引き続き利用できます。

詳細なパラメーター説明・発行コマンドの切り替え表は [Diff.md](docs/Diff.md) を参照してください。

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
Requires PowerShell 7.0+ (7.6+ recommended) and Node.js; npm dependencies are installed automatically on first run.  
Windows PowerShell 5.1 is **not** supported: scripts are stored as UTF-8 without BOM, which 5.1 reads as the system ANSI code page and fails to parse.
