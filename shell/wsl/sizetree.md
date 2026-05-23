# sizetree

ディレクトリをツリー形式でサイズ付きに表示する Bash スクリプトです。  
`du` と `tree` を組み合わせたような出力で、容量を多く消費しているディレクトリを素早く特定できます。

## 動作環境

- Bash 4.x 以上
- GNU coreutils (`du`, `find`) または BSD 互換コマンド（macOS 対応）
- WSL2 推奨（Windows ユーザー）

## インストール

```bash
chmod +x sizetree.sh
```

必要に応じてパスの通ったディレクトリにコピーします。

```bash
cp sizetree.sh ~/.local/bin/sizetree
```

## 使い方

```
sizetree [OPTIONS] [PATH]
```

`PATH` を省略するとカレントディレクトリが対象になります。

## オプション

| オプション | 説明 |
|---|---|
| `-d N`, `--depth N` | 表示する最大深さ（デフォルト: 2） |
| `-r`, `--recursive` | 深さ制限なしで全展開 |
| `-s`, `--sort-size` | 各階層をサイズ降順でソート（デフォルト: 名前順） |
| `--exclude PAT` | 名前が PAT にマッチするエントリを除外（複数指定可） |
| `--min-size SZ` | SZ 未満のエントリを省略（例: `1M`, `500K`, `2G`） |
| `-h`, `--help` | ヘルプを表示 |

## 出力例

```
$ sizetree -d 2 -s ~/project
[  1.3G] /home/user/project
├── [  1.2G] node_modules/
│   ├── [900.0M] webpack/
│   └── [300.0M] react/
├── [ 50.0M] src/
└── [  2.0M] dist/
```

## 使用例

```bash
# カレントディレクトリを深さ2で表示（デフォルト）
sizetree .

# 深さ1でサイズ降順
sizetree -d 1 -s /tmp

# 再帰的に全展開（大きなディレクトリには注意）
sizetree -r ~/project

# node_modules と .git を除外してサイズ降順
sizetree -s --exclude 'node_modules' --exclude '.git' .

# 10MB 以上のエントリのみ表示
sizetree --min-size 10M /var

# 複数オプションの組み合わせ
sizetree -d 3 -s --exclude '*.log' --min-size 1M /home/user
```

## 注意事項

- 大量のファイルを含むディレクトリで `-r` を使うと時間がかかる場合があります
- Windows ファイルシステム（`/mnt/c/` など）は I/O が遅いため、WSL2 のホームディレクトリ上での使用を推奨します
- `--exclude` のパターンは glob 形式です（例: `'*.tmp'`, `'cache*'`）
