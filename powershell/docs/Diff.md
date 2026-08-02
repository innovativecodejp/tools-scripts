# Diff.ps1 — 仕様・使用説明書

指定したファイル／フォルダの差分を TortoiseGit の GUI で開くスクリプトです。  
プロファイルへインストールすると `Diff <パス>` だけで差分ビューアを起動できます。

---

## 動作環境

| 要件 | 詳細 |
|------|------|
| PowerShell | 5.1 以上 |
| TortoiseGit | インストール済みであること（`TortoiseGitProc.exe` を使用） |
| Git | 不要（`.git` の有無はファイルシステムを辿って判定するため） |

`TortoiseGitProc.exe` は次の順で探索し、最初に実在したものを使用します。

1. `-TortoiseGitProc` パラメーターの明示指定
2. レジストリ `HKCU:\SOFTWARE\TortoiseGit` → `HKLM:\SOFTWARE\TortoiseGit` → `HKLM:\SOFTWARE\WOW6432Node\TortoiseGit`  
   （`ProcPath`、無ければ `Directory` + `bin\TortoiseGitProc.exe`。値が空のキーは読み飛ばします）
3. `PATH` 上の `TortoiseGitProc.exe`
4. `%ProgramFiles%` / `%ProgramFiles(x86)%` の `TortoiseGit\bin\TortoiseGitProc.exe`

すべて失敗した場合は導入案内を表示して停止します。

---

## 使用方法

```powershell
# 作業ツリーの内容と HEAD(BASE) を比較
Diff .\src\App.cs

# 2 ファイルを直接比較（Git 管理下でなくても可）
Diff .\a.txt .\b.txt

# リビジョンを指定して比較
Diff .\src\App.cs -s HEAD~3 -e HEAD

# unified diff 形式で開き、120 行目へスクロール
Diff .\src\App.cs -Unified -Line 120

# フォルダ指定 → 変更確認ダイアログ
Diff .\src

# 引数なし → カレントディレクトリの変更確認ダイアログ
Diff

# ウィンドウが閉じるまで待つ
Diff .\src\App.cs -Wait

# 実際には起動せず、組み立てられるコマンドラインだけ確認
Diff .\src\App.cs -WhatIf
```

インストール前にリポジトリから直接実行する場合は次のとおりです。

```powershell
.\powershell\tools\Diff.ps1 .\src\App.cs
```

---

## 発行するコマンド

指定内容に応じて `TortoiseGitProc.exe` のコマンドを切り替えます。

| `-Path` の種別 | `-Path2` | `-StartRev` / `-EndRev` | 発行コマンド | 表示されるもの |
|---|---|---|---|---|
| ファイル | なし | なし | `/command:diff` | 作業ツリー vs BASE の差分 |
| ファイル | あり | – | `/command:diff /path2:` | 2 ファイルの差分 |
| ファイル | なし | あり | `/command:diff /startrev: /endrev:` | 指定リビジョン間の差分 |
| フォルダ | なし | なし | `/command:repostatus` | 変更確認ダイアログ |
| フォルダ | なし | あり | `/command:showcompare /revision1: /revision2:` | 変更ファイル一覧 |
| フォルダ | あり | – | `/command:diff /path2:` | TortoiseGit へそのまま委譲 |

`showcompare` はリビジョン指定に `startrev`/`endrev` ではなく `revision1`/`revision2` を使う点に注意してください。  
`repostatus` は表示形式のオプションを受け付けないため、フォルダ指定時の `-Unified` / `-Line` は警告のうえ無視されます。

---

## パラメーター

| パラメーター | エイリアス | 既定値 | 説明 |
|---|---|---|---|
| `-Path` | （位置 0） | `.` | 比較対象のファイルまたはフォルダ |
| `-Path2` | （位置 1） | なし | 2 ファイル比較の相手。指定するとリビジョン指定は使えません |
| `-StartRev` | `-s` | なし | 比較元（BASE 側）のリビジョン。例: `HEAD~3` / `master` / `1a2b3c4` |
| `-EndRev` | `-e` | なし | 比較先のリビジョン |
| `-Unified` | `-u` | オフ | unified diff 形式で表示 |
| `-Line` | – | なし | 開いた直後にスクロールする行番号（1 以上） |
| `-Wait` | – | オフ | TortoiseGit のウィンドウが閉じるまで待機 |
| `-TortoiseGitProc` | – | 自動探索 | `TortoiseGitProc.exe` のパスを明示指定 |
| `-WhatIf` | – | – | 起動せずに組み立てたコマンドラインのみ表示 |

`-Path2` と `-StartRev` / `-EndRev` はパラメーターセットで排他になっており、同時指定はエラーになります。

`-s` / `-e` は単独のパラメーター名ではなく、正式名 `-StartRev` / `-EndRev` の `[Alias]` として定義しています
（単一文字名にすると、将来同じ頭文字のパラメーターが増えた時点で曖昧エラーになるため）。

---

## 戻り値

`[PSCustomObject]` を返します。`-WhatIf` 時は `ProcessId` / `ExitCode` が `$null` になります。

| プロパティ | 内容 |
|---|---|
| `Executable` | 使用した `TortoiseGitProc.exe` のフルパス |
| `Command` | 発行したコマンド（`diff` / `repostatus` / `showcompare`） |
| `Arguments` | 実際に渡したコマンドライン文字列 |
| `Path` / `Path2` | 解決後の絶対パス |
| `ProcessId` | 起動したプロセスの ID |
| `ExitCode` | `-Wait` 指定時の終了コード |

---

## 実行前チェック

| チェック | 動作 |
|---|---|
| パスの存在 | 見つからなければ「パスが見つかりません」で停止 |
| Git 管理下か | `.git` が見つからなければ「Git の管理下にありません」で停止 |
| `TortoiseGitProc.exe` | 見つからなければ導入案内を表示して停止 |

Git 管理下の判定は、対象から親ディレクトリへ向かって `.git` を探す方式です。  
submodule / worktree では `.git` がファイルになるため、ディレクトリとファイルの両方を許容します。  
`git.exe` に依存しないため、Git 本体が未インストールの環境でも誤判定しません。

`-Path2` を指定した 2 ファイル比較は BASE を必要としないため、Git 管理下チェックを行いません。

なお本スクリプトは house style に従い `$ErrorActionPreference = 'Stop'` で動作するため、
上記のエラーはいずれも終了エラー（例外）として呼び出し側へ伝わります。

---

## `Diff` という名前について（重要）

PowerShell のコマンド解決順は **Alias > Function > Cmdlet > Application** です。  
`diff` は `Compare-Object` への **ReadOnly エイリアス**として組み込まれているため、
プロファイルに `function Diff` を定義しただけでは関数は呼ばれません。

```powershell
# エイリアスを解除しない場合
PS> Diff .\README.md
Compare-Object: Cannot process command because of one or more missing mandatory parameters: DifferenceObject.
```

そのため、プロファイルには関数定義の前にエイリアスの解除行を置いています。

```powershell
# 組み込みエイリアス Diff (Compare-Object) は関数より優先されるため解除します。
if (Test-Path Alias:Diff) {
    Remove-Item -LiteralPath Alias:Diff -Force
}
```

- ReadOnly なエイリアスも `Remove-Item -Force` で解除できます（Constant は不可）。
- `Compare-Object` 本体と `compare` エイリアスは残るため、機能が失われることはありません。
- ただし `diff $a $b` を `Compare-Object` の意味で使っていた既存スクリプトには影響します。

この解除行は `InstallPsScript.ps1` が自動生成します。判定は「実行中セッションにそのエイリアスが
存在するか」で行うため、**初回インストールは解除前のセッション（新規に開いた PowerShell）で
実行してください**。すでに解除済みのセッションで再生成しても解除行は出力されません。

---

## インストール

```powershell
.\powershell\tools\InstallPsScript.ps1 tools\Diff.ps1
```

```
=== スクリプトのインストール ===
対象      : tools\Diff.ps1
関数名    : Diff
複写先    : C:\Users\<user>\...\PowerShell\tools\Diff.ps1

② 複写完了: C:\Users\<user>\...\PowerShell\tools\Diff.ps1
③ 関数 Diff をリポジトリのプロファイルに追加しました。
   同名のエイリアス Diff (Compare-Object) を解除する行も併せて追加しました。

=== プロファイル比較 ===
④ 差分は③の追加のみ。$PROFILE を上書きしました。
```

インストール後は PowerShell を再起動（またはプロファイルを再読み込み）してください。

```powershell
# 確認
Get-Command Diff                              # CommandType が Function であること
Get-Alias diff -ErrorAction SilentlyContinue  # 何も返らないこと
Compare-Object 1,2 2,3                        # Compare-Object 自体は健在
```

---

## テスト

```powershell
Invoke-Pester .\powershell\tests\unit\Diff.Tests.ps1 -Output Detailed
```

`-WhatIf` を用いてコマンドライン文字列のみを検証するため、テスト中に GUI は起動しません。  
Pester v5 以上が必要です。

---

## コンソール出力の見方

```
=== TortoiseGit Diff ===
実行ファイル: C:\Program Files\TortoiseGit\bin\TortoiseGitProc.exe
コマンド    : diff
対象        : D:\dev\tools-scripts\README.md
引数        : /command:diff /path:"D:\dev\tools-scripts\README.md" /startrev:HEAD~3 /endrev:HEAD
起動しました (PID: 12832)
```

| 行 | 意味 |
|---|---|
| 実行ファイル | 探索で解決した `TortoiseGitProc.exe` |
| コマンド | 発行した `/command:` の値 |
| 対象 / 比較相手 | 解決後の絶対パス |
| 引数（灰） | 実際に渡したコマンドライン文字列 |
| 起動しました（緑） | プロセス起動成功 |

---

## 実装メモ

引数は配列ではなく **1 本の文字列**として組み立て、`Start-Process -ArgumentList` に渡しています。

```powershell
/command:diff /path:"D:\a b\file.txt"
```

呼び出し演算子 `&` を使うと、PowerShell が空白を含む引数を `"/path:D:\a b\file.txt"` のように
**トークン全体で**引用してしまい、TortoiseGit 側のパーサ挙動に依存します。  
公式ドキュメント（`TortoiseGit_en\tgit-automation.html` / Appendix D. Automating TortoiseGit）の例と同じく
「コロンの後ろだけ」を引用した文字列を逐語的に渡すことで、PowerShell 5.1 / 7 の両方で同じ結果になります。

パスに含まれると区切り文字と衝突する `*`（TortoiseGit の複数パス区切り）は、
Windows のファイル名に使用できないため考慮不要です。
