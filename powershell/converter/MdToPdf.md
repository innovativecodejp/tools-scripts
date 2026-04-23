# MdToPdf.ps1 — 仕様・使用説明書

Mermaid ダイアグラムを含む Markdown ファイルを PDF に一括変換する PowerShell スクリプトです。

---

## 動作環境

| 要件 | 詳細 |
|------|------|
| PowerShell | 7.6 以上（推奨）/ 5.1 以上（客先環境） |
| Node.js | 任意の安定版（`node` コマンドが PATH に存在すること） |
| npm パッケージ | 初回実行時に自動インストール（下記参照） |

### 自動インストールされる npm パッケージ

初回実行時に `%LOCALAPPDATA%\md-to-pdf-ps\` へインストールされます。  
Chromium（約 170 MB）のダウンロードが発生します。

| パッケージ | 用途 |
|-----------|------|
| marked@9 | Markdown → HTML 変換 |
| marked-highlight | シンタックスハイライト連携 |
| highlight.js | コードブロックのハイライト |
| mermaid@10 | Mermaid ダイアグラム描画 |
| puppeteer@21 | Chromium による PDF 生成 |

---

## パラメーター

### 入力指定（どちらか一方を必ず指定）

#### `-Pattern <string>`（パラメーターセット: `Pattern`）

変換対象ファイルのワイルドカードパターン。

```
例: "*.md"、"docs\*.md"
```

#### `-FileList <string>`（パラメーターセット: `FileList`）

変換対象ファイルのパスを 1 行 1 ファイルで記述したテキストファイルのパス。  
ファイルが存在しない場合はエラーになります。

---

### オプションパラメーター

| パラメーター | 型 | デフォルト | 説明 |
|---|---|---|---|
| `-Recurse` | switch | off | サブディレクトリを再帰的に検索する（`-Pattern` 使用時のみ有効） |
| `-OutputDir` | string | 各 MD ファイルと同じディレクトリ | PDF の出力先ディレクトリ（存在しない場合は自動作成） |
| `-Force` | switch | off | 既存の PDF を上書きする |
| `-FontSize` | int | `12` | 本文フォントサイズ（pt） |
| `-Margin` | string | `"20mm"` | ページ余白（CSS の margin 値） |
| `-FontFamily` | string | `"Meiryo UI, Yu Gothic UI, Segoe UI, sans-serif"` | フォントファミリー |
| `-HeadingFontSize` | double | `2.0` | H1 のフォントサイズ（em）。H2 は × 0.75、H3 は × 0.60 で自動計算 |

---

## 使用例

```powershell
# カレントディレクトリの全 .md ファイルを変換
.\MdToPdf.ps1 -Pattern "*.md"

# docs\ 以下を再帰検索して .\pdf\ に出力（上書きあり）
.\MdToPdf.ps1 -Pattern "docs\*.md" -Recurse -OutputDir ".\pdf" -Force

# ファイルリストを使って変換（フォントサイズ・余白を指定）
.\MdToPdf.ps1 -FileList "files.txt" -FontSize 11 -Margin "15mm"

# フォントとヘッダーサイズをカスタマイズ
.\MdToPdf.ps1 -Pattern "*.md" -FontFamily "Yu Gothic, sans-serif" -HeadingFontSize 1.8
```

---

## 動作フロー

```
1. Node.js の存在確認
2. 変換対象 .md ファイルの収集
3. 出力ディレクトリの作成（-OutputDir 指定時）
4. 既存 PDF の確認（-Force なしの場合はスキップ）
5. npm パッケージの確認 → 未インストールなら確認後にインストール
6. Node.js 変換スクリプト（convert.js）を %LOCALAPPDATA%\md-to-pdf-ps\ に書き出し
7. 設定 JSON を %TEMP% に一時生成
8. Node.js プロセスを起動して PDF を生成
9. 一時ファイルを削除し、結果サマリーを表示
```

---

## 出力形式

- 用紙サイズ: A4
- 余白: `-Margin` パラメーターで指定した値（上下左右すべてに適用）
- 背景色: 印刷あり（`printBackground: true`）

---

## コンソール出力の見方

| プレフィックス | 意味 |
|---|---|
| `[*]` （シアン） | 処理ステップの開始 |
| `[v]` （緑） | 変換成功 |
| `[~]` （黄） | スキップ（既存 PDF、またはファイル未検出） |
| `[x]` （赤） | エラー |
| `    ` （グレー） | 補足情報 |

---

## 注意事項

- Mermaid ダイアグラムの描画には最大 15 秒待機します。タイムアウトした場合はダイアグラムなしで PDF が生成されます。
- `-Pattern` に親ディレクトリを含めない場合（例: `"*.md"`）はカレントディレクトリが検索対象になります。
- `-FileList` で指定したファイルのうち存在しないものはスキップされます（エラーにはなりません）。
- npm パッケージは `%LOCALAPPDATA%\md-to-pdf-ps\` に永続保存されるため、2 回目以降はインストール不要です。

---

## 客先環境（PS 5.1）への配布時の注意

客先環境が Windows PowerShell 5.1 の場合、以下の点に注意してください。

### スクリプトファイルのエンコーディング

PS 5.1 は BOM なし UTF-8 ファイルをシステム既定エンコーディング（日本語環境では Shift-JIS）として読み込みます。  
スクリプトを渡す際は **UTF-8 BOM あり** で保存してください。

```powershell
# PS 5.1 環境で保存する場合（UTF8 = BOM あり）
Set-Content -Path .\MdToPdf.ps1 -Value (Get-Content .\MdToPdf.ps1 -Raw -Encoding UTF8) -Encoding UTF8
```

> PS 7 で `Set-Content -Encoding UTF8` を使うと BOM なしで保存されます。  
> 客先向けファイルは PS 5.1 環境で保存するか、上記コマンドで変換してください。

### `-FileList` で渡すテキストファイル

ファイルリスト（`-FileList` に指定するテキストファイル）も **UTF-8 BOM あり** または **UTF-8 BOM なし**（ASCII のみの場合は問題なし）で作成してください。  
Shift-JIS で保存されたファイルリストはパスの読み込みに失敗する場合があります。

### 実行ポリシーの確認

PS 5.1 は実行ポリシーが `Restricted`（デフォルト）の場合、スクリプトを実行できません。  
客先での初回実行前に以下を案内してください。

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
