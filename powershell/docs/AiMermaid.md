# -AiMermaid 機能仕様書

`MdToPdf.ps1` の `-AiMermaid` オプションの仕様です。  
Markdown 内の `ai-mermaid` ブロックを Claude API で Mermaid 構文に自動変換します。

---

## 概要

自然言語でフロー・構成を記述するだけで、Mermaid ダイアグラムを生成して PDF に埋め込めます。  
生成結果を `*.md.ai.md` として保存する機能（`-AiDebug`）により、Mermaid 構文の学習サンプルとしても活用できます。

---

## 事前準備

```powershell
.\Set-AiConfig.ps1
```

APIキーとモデルを設定します。詳細は [Set-AiConfig.md](Set-AiConfig.md) を参照してください。

---

## Markdown 記法

### 種別を AI に判断させる（推奨）

````markdown
```ai-mermaid
ユーザーがログインフォームに入力
→ APIサーバーが認証
→ 成功時はJWT発行、失敗時は403を返す
```
````

### 種別を明示する

````markdown
```ai-mermaid:sequence
Alice が Bob にメッセージを送り、Bob が返信する
```
````

#### 指定可能な種別

| 種別キーワード | ダイアグラム |
|---|---|
| `flowchart` / `graph` | フローチャート |
| `sequence` | シーケンス図 |
| `class` | クラス図 |
| `er` | ER図 |
| `gantt` | ガントチャート |
| `pie` | 円グラフ |
| `state` | 状態遷移図 |

---

## パラメーター

| パラメーター | 型 | 説明 |
|---|---|---|
| `-AiMermaid` | switch | AI Mermaid 生成を有効化 |
| `-AiStrict` | switch | 1ブロックでも失敗したらファイル全体をスキップ |
| `-AiDebug` | switch | AI 置換済み中間ファイル `*.md.ai.md` を保存 |
| `-Force` | switch | 既存 PDF の上書きに加え、コスト警告もスキップ |

---

## 使用例

```powershell
# 基本
.\MdToPdf.ps1 -Pattern "*.md" -AiMermaid

# 失敗したファイルはスキップ（不完全な PDF を出さない）
.\MdToPdf.ps1 -Pattern "*.md" -AiMermaid -AiStrict

# Mermaid 構文を学習用に保存
.\MdToPdf.ps1 -Pattern "*.md" -AiMermaid -AiDebug

# フル指定
.\MdToPdf.ps1 -Pattern "docs\*.md" -Recurse -AiMermaid -AiStrict -AiDebug -OutputDir ".\pdf" -Force
```

---

## 処理フロー

```
1. ai-mermaidブロックを全件抽出（BLOCK_1, BLOCK_2 ... と採番）
2. ブロック数が30件以上なら確認プロンプト（-Force でスキップ）
3. 1ファイル = 1回のAPI呼び出し（全ブロックをまとめて送信）
   - システムプロンプトはプロンプトキャッシュで効率化
   - Claude に「自己確認してから返せ」と指示
   - JSON配列 { id, status, mermaid } で受け取る
4. ブロックごとに mermaid.parse() で構文を二重検証
   - 失敗時: エラー箇所をコンソールに表示（行番号付き）
5. 成功ブロックを ```mermaid に置換
   失敗ブロックの扱いは -AiStrict の有無で決まる（下記参照）
6. -AiDebug 指定時: *.md.ai.md を保存
7. 通常の HTML 変換 → PDF 出力へ
```

---

## 失敗時の挙動

### `-AiStrict` なし（デフォルト）

失敗したブロックだけ blockquote にフォールバックし、PDF 生成は続行します。

```
[AI~] report.md: BLOCK_2（37行目付近）構文エラー: ... → blockquoteにフォールバック
[v]   report.md -> report.pdf
```

PDF 内の該当箇所:
> ⚠️ AI Mermaid生成失敗 (BLOCK_2): ユーザーが入力した元テキスト

### `-AiStrict` あり

1ブロックでも失敗した場合、ファイル全体をスキップします。

```
[AI~] report.md: BLOCK_2（37行目付近）構文エラー: ...
[x]   report.md: -AiStrict のためスキップ
```

---

## コンソール出力

| プレフィックス | 色 | 意味 |
|---|---|---|
| `[AI]` | マゼンタ | AI 処理開始 |
| `[AI✓]` | マゼンタ | AI 処理成功（トークン数表示）|
| `[AI~]` | 黄 | ブロック単位の失敗・フォールバック |

### 出力例

```
[AI]  report.md: 3ブロックを生成中...
[AI✓] report.md: 3ブロック生成完了 (入力 312 / 出力 128 tokens)
[v]   [1/3] report.md -> report.pdf

----------------------------------------
  成功:     3 件
  AI使用:   入力 892 / 出力 374 tokens (合計 1,266 tokens)
----------------------------------------
```

---

## `-AiDebug` で保存される中間ファイル

`-AiDebug` を指定すると、AI が生成した Mermaid 構文に置換済みの Markdown が `*.md.ai.md` として保存されます。

```
report.md        ← 元ファイル（変更なし）
report.md.ai.md  ← ai-mermaid → mermaid に置換済み
report.pdf       ← 生成された PDF
```

**活用方法**: `report.md.ai.md` を開いて生成された Mermaid 構文を確認し、手動コーディングのサンプルとして参照できます。

---

## 注意事項

- `ai-mermaid` ブロックが 0 件のファイルは AI 処理をスキップし、通常変換します
- API 呼び出しが失敗した場合（タイムアウト・ネットワークエラー）は `-AiStrict` と同様に扱われます
- プロンプトキャッシュにより、同一実行内での2ファイル目以降はシステムプロンプト分のコストが削減されます
