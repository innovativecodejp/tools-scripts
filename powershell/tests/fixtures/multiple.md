# 複数ブロックテスト

ai-mermaid ブロックが複数あるサンプルです。

## システム構成

```ai-mermaid
Webブラウザ → Nginxリバースプロキシ → Appサーバー → PostgreSQL
```

## デプロイフロー

```ai-mermaid:sequence
開発者がgit pushし、CIがテストを実行し、合格したらサーバーにデプロイされる
```

## 状態遷移

```ai-mermaid:state
注文は「受付」から始まり、「処理中」「発送済み」「完了」と遷移する。キャンセルはどの状態からも可能
```
