# 作業ログ

## 2026-06-22

### KillLine.ps1 を「使用中はスキップ」する近似方式に更新

- 対象: [tools/KillLine.ps1](../tools/KillLine.ps1)
- 変更内容:
  - 従来は無条件で `Stop-Process` していたが、「LINE 使用中とみなせる場合は終了をスキップ」する判定を追加。
  - 判定は Win32 API による近似:
    - `GetForegroundWindow` … LINE ウィンドウが最前面(アクティブ)か
    - `GetLastInputInfo` … 最終入力からの経過時間(OS 全体)
  - 「最前面」かつ「最終入力からの経過 < しきい値(既定 3000ms)」のとき入力中とみなしスキップ。それ以外は従来どおり強制終了。
  - パラメータ追加:
    - `-IdleThresholdMs <int>`(既定 3000)… 入力中とみなす猶予時間(ミリ秒)
    - `-Quiet`(switch)… スキップ時のメッセージを抑制
- 既知の制約:
  - `GetLastInputInfo` は OS 全体の入力のため、LINE が最前面なら他アプリのキー操作も「入力中」と判定し得る。
  - メッセージ入力欄の中身や IME 変換中までは判定不可。
  - 構文チェック(Parser)のみ実施。実行確認は LINE が終了し得るため未実施。

## 2026-06-23

### KillLine を 30 分ごとに自動実行する仕組みを追加

- 追加: [tools/Register-KillLineTask.ps1](../tools/Register-KillLineTask.ps1)
  - KillLine.ps1 を 30 分間隔で繰り返し実行するタスクをタスクスケジューラに登録/解除する。
  - 「ログオン中のみ・現在ユーザー権限(昇格不要)」で非表示実行。
  - 登録は `schtasks.exe` を使用(`Register-ScheduledTask` 等の CIM コマンドレットは本環境では「アクセス拒否」で失敗するため)。
  - タスクが参照する KillLine.ps1 は `$PROFILE` 配下の配置先(`<$PROFILE のフォルダ>\tools\KillLine.ps1`)。dev リポジトリは開発環境とし、配置先へコピーして運用する方針。`-ScriptPath` で変更可。
  - `schtasks /TR` には 261 文字制限があり配置先の長いパスで超過するため、タスク定義を XML 化して `schtasks /Create /XML` で取り込む方式にした(Arguments に文字数制限なし)。
- 追加: [tools/KillLineLoop.ps1](../tools/KillLineLoop.ps1)
  - コンソールを開いている間だけ動く常駐ループ版(既定 30 分間隔)。タスクスケジューラ方式の代替/簡易確認用。
- 補足: 一時的に KillLine.ps1 へファイルログ出力機能(`-LogPath`)を追加していたが、本日廃止(下記)。

### KillLine.log へのログ出力を廃止

- 対象: [tools/KillLine.ps1](../tools/KillLine.ps1) / [tools/Register-KillLineTask.ps1](../tools/Register-KillLineTask.ps1)
- 変更内容:
  - KillLine.ps1 から `-LogPath`・`Write-KillLineLog`・終了確認用の待機/再チェックを削除し、元のシンプルな実装に戻した。
  - Register-KillLineTask.ps1 の登録引数から `-LogPath` を除去。
  - 既存ログフォルダ(`tools\logs`)を dev/配置先の両方で削除。
- 確認: タスク再登録後に手動実行 → Last Result = 0、`logs` フォルダが再生成されないことを確認。

### インストール状況チェックスクリプトを追加

- 追加: [tools/CheckPsTools.ps1](../tools/CheckPsTools.ps1)
  - `converter/` `excel/` `file/` `tools/` 配下のスクリプトが `$PROFILE` ディレクトリ配下にインストール済みかをチェックする。
  - 未インストールのスクリプト名をカテゴリごとに一覧表示する。
  - `$PROFILE` 本体とリポジトリの `Microsoft.PowerShell_profile.ps1` を SHA256 で比較し、一致/不一致を判定する。
  - 読み取り専用。インストール先へのコピーは一切行わない(`Copy-Item`/`Move-Item` 等を含めない)。
  - チェック結果は `[PSCustomObject]`(`MissingCount`/`Missing`/`ProfileEqual` 等)としても返す。
- 関連変更:
  - 実フォルダ `excle`(綴り誤り)を `excel` にリネームし、`$Global:ExcelDir`(`\excel\`)と一致させた。
  - スクリプト名を当初の `Test-Installation.ps1` から `CheckPsTools.ps1` に変更。

### スクリプトインストールスクリプトを追加

- 追加: [tools/InstallPsScript.ps1](../tools/InstallPsScript.ps1)
  - 使い方: `InstallPsScript.ps1 <script-file.ps1>`
  - ② 指定スクリプトを `$PROFILE` ディレクトリ配下へ、同じ相対パス(カテゴリフォルダ込み)で複写する。
  - ③ リポジトリの `Microsoft.PowerShell_profile.ps1` に、拡張子なしで起動できるラッパー関数(`KillLine` と同じスタイル)を追加する。カテゴリに応じて `$Global:ToolsDir` 等の既存変数を使用。
  - ④ `$PROFILE` がリポジトリの「③追加前の内容」と一致する(＝差分が③のみ)場合のみ `$PROFILE` を上書きする。それ以外はバージョン差異とみなし、赤字で「更新していません」と表示する。
- 配慮した点:
  - 元プロファイルの改行コード(LF)・BOM 無しを検出して保持。
  - 同名関数が既に定義済みの場合は二重追加しない。
  - 比較は改行コード・末尾空白を正規化して判定。
- 確認: 正常系 / 既定義スキップ / バージョン差異(赤字)の 3 パターンを実機検証(検証で生じたプロファイル変更は元に戻し済み)。

## 2026-08-03

### KillLine の起動経路を KillLine.ps1 に一本化(`-s` / `-e` を追加)

- 対象: [tools/KillLine.ps1](../tools/KillLine.ps1) / [Microsoft.PowerShell_profile.ps1](../Microsoft.PowerShell_profile.ps1)
- 仕様:
  - `KillLine` … 従来どおり LINE.exe を直ちに終了(使用中とみなせる場合はスキップ)。
  - `KillLine -s` … 30 分間隔の定期実行タスクを登録。登録直後に 1 回実行される。
  - `KillLine -e` … 定期実行タスクを削除して停止。
  - `KillLine -Status` … 登録状況・次回実行時刻を表示(追加)。
- 変更内容:
  - パラメータセット(`Run` / `Schedule` / `End` / `Status`)で排他化。`-s` `-e` を
    単独のパラメータ名にせず、正式名 `-Schedule` `-End` の `[Alias]` として定義した
    (単一文字名は将来同じ頭文字のパラメータが増えた時点で曖昧エラーになるため)。
  - 削除: `tools/Register-KillLineTask.ps1`(XML 生成ロジックは KillLine.ps1 へ移設)
  - 削除: `tools/KillLineLoop.ps1`(タスクスケジューラ方式に一本化したため不要)
  - `Microsoft.PowerShell_profile.ps1` の `KillLine` 関数が `& $scriptPath` で引数を
    捨てていたため `@args` を追加。これが無いと `KillLine -s` が引数なしの即時 kill に
    なってしまう(他の関数は InstallPsScript.ps1 が生成する `@args` 付きの形)。
  - schtasks.exe の呼び出しを `Invoke-Schtasks` に集約。native コマンドの stderr は
    `$ErrorActionPreference = 'Stop'` の下で NativeCommandError となり得るため、
    実行中だけ `Continue` に戻して終了コードで判定する。
- 据え置いた点:
  - 実行間隔は 30 分のまま(`-IntervalMinutes` で変更可)。タスク名も `KillLine` 据え置きの
    ため、既存タスクは `/F` で上書きされ二重登録にはならない。
  - タスクが参照するのは `$PROFILE` 配下の配置先。dev リポジトリから `-s` しても配置先を
    指す(リポジトリ移動でタスクが壊れないようにするため)。
- 確認:
  - Parser による構文チェック / パラメータセットの解決を確認。
  - `-Status`(読み取り専用)、`-s` の配置先不在エラー、`-e` の未登録時警告、
    `-s -e` 同時指定の拒否を実機で確認。いずれもタスクへの変更なし。
  - 既定(引数なし)の実行は LINE 起動中のため未実施。
  - 補足: 現在 `KillLine` タスクは Status = Disabled / Next Run Time = N/A。
    有効化するには `KillLine -s` で再登録する。

## 2026-08-03

### TortoiseGit の差分を開く Diff.ps1 を追加

- 対象: [tools/Diff.ps1](../tools/Diff.ps1) / [tools/InstallPsScript.ps1](../tools/InstallPsScript.ps1) /
  [Microsoft.PowerShell_profile.ps1](../Microsoft.PowerShell_profile.ps1) /
  [tests/unit/Diff.Tests.ps1](../tests/unit/Diff.Tests.ps1) / [docs/Diff.md](../docs/Diff.md)
- 仕様:
  - `Diff <パス>` … 作業ツリーの内容と HEAD(BASE) を TortoiseGit の差分ビューアで比較。
  - `Diff <A> <B>` … 2 ファイルを直接比較(`-Path2`)。BASE 不要のため Git 管理外でも可。
  - `Diff <パス> -s <rev> -e <rev>` … リビジョン指定。`-s`/`-e` は `-StartRev`/`-EndRev` のエイリアス。
  - `-Unified` / `-Line <n>` / `-Wait` / `-TortoiseGitProc <path>` / `-WhatIf` に対応。
  - パスがフォルダなら `repostatus`(変更確認ダイアログ)、フォルダ + リビジョンなら `showcompare` を
    発行する。引数なしはカレントディレクトリ扱い。
- 変更内容:
  - **`Diff` は組み込みエイリアス `diff`(= `Compare-Object`)と衝突する**。PowerShell のコマンド解決順は
    Alias > Function > Cmdlet > Application のため、プロファイルに `function Diff` を定義しても関数は
    呼ばれない(実測: `Cannot process command because of one or more missing mandatory parameters:
    DifferenceObject.`)。そこでプロファイルの関数定義の前にエイリアス解除行を置く方式にした。
    ReadOnly なエイリアスも `Remove-Item -LiteralPath Alias:<名前> -Force` で解除できる(Constant は不可)。
    `Compare-Object` 本体と `compare` エイリアスは残るため機能欠落はない。
  - `InstallPsScript.ps1` の ③ を拡張し、**関数名と同名のエイリアスが存在する場合は解除行も自動生成**する
    ようにした。これで `InstallPsScript tools\Diff.ps1` の 1 コマンドでインストールが完結する。
    判定は「実行中セッションに `Get-Alias <名前>` が存在するか」のため、初回インストールは解除前の
    新規セッションで実行する必要がある(この点は docs/Diff.md に明記)。
  - 引数は配列ではなく **1 本の文字列**として組み立て、`Start-Process -ArgumentList` に渡す。
    呼び出し演算子 `&` では空白を含む引数が `"/path:D:\a b\x.txt"` のようにトークン全体で引用され、
    TortoiseGit 側のパーサ挙動に依存するため。公式ドキュメント
    (`TortoiseGit_en\tgit-automation.html` / Appendix D)の例と同じく「コロンの後ろだけ」を引用する。
  - `TortoiseGitProc.exe` の探索は ①明示指定 → ②レジストリ(HKCU/HKLM/WOW6432Node) → ③PATH →
    ④`%ProgramFiles%`。**HKCU は実機で `ProcPath`/`Directory` が空文字だった**ため、
    `[string]::IsNullOrWhiteSpace` による空判定を必ず通す。
  - Git 管理下の判定は親方向へ `.git` を探す方式。submodule / worktree では `.git` がファイルになるため
    ディレクトリ・ファイルの両方を許容する。`git.exe` に依存しないので Git 未導入環境でも誤判定しない。
    `-Path2` 指定時は BASE 不要のためこのチェックを行わない。
- 据え置いた点:
  - house style に合わせ `$ErrorActionPreference = 'Stop'` としたため、`Write-Error` は終了エラーになる。
    `-ErrorAction SilentlyContinue` を渡しても抑制されない(スクリプト側の代入が勝つ)。テストもこれに
    合わせて `Should -Throw` で書いている。
  - `-Log` / `-Blame` など diff 以外の TortoiseGit GUI は含めていない(`Diff` という名前の責務を超えるため)。
- 確認:
  - Parser による構文チェック(Diff.ps1 / InstallPsScript.ps1 / Diff.Tests.ps1)… OK。
  - `Invoke-Pester tests\unit\Diff.Tests.ps1` … 15 件すべて成功(`-WhatIf` のため GUI は起動しない)。
    ※ 本環境には Pester 3.4.0 しか無かったため、Pester 6.0.1 を CurrentUser スコープへ追加導入した。
  - 実機確認: `Diff .\README.md -s HEAD~3 -e HEAD` で TortoiseGitMerge が起動
    (ウィンドウタイトル `README.md: 80e651e2 - TortoiseGitMerge`)。空白を含むパスでの
    2 ファイル比較も起動を確認。
  - インストール後の新規セッションで `Get-Command Diff` = Function、`Get-Alias diff` = なし、
    `Compare-Object 1,2 2,3` は正常動作を確認。
  - `CheckPsTools.ps1` は Diff.ps1 を自動的に検出対象に含む(登録作業は不要)。
    なお `tools/CheckPsTools.ps1` 自体は未インストールのままで、今回は触れていない。

### PowerShell 7 専用に統一し、CheckPsTools を登録・拡張

- 対象: 全 `.ps1` / [.gitattributes](../../.gitattributes) / [tools/CheckPsTools.ps1](../tools/CheckPsTools.ps1) /
  [tools/InstallPsScript.ps1](../tools/InstallPsScript.ps1) /
  [Microsoft.PowerShell_profile.ps1](../Microsoft.PowerShell_profile.ps1) / README・docs 一式
- きっかけ:
  - Pester の導入影響を調べる過程で、**Windows PowerShell 5.1 では本リポジトリの `.ps1` が
    ほぼ全滅する**ことが判明した。5.1 は BOM なしファイルをシステム既定エンコーディング
    (日本語環境では CP932)として読むため、日本語を含むスクリプトがパースエラーになる。
    KillLine(11) / MdToPdf(108) / Set-AiConfig(9) / InstallPsScript(5) / CheckPsTools(3) / Diff(9) が NG。
    同じファイルを BOM 付きに変換すると 5.1 でも Parse OK になることを実測で確認し、原因を確定した。
  - つまり README の「客先環境 5.1 以上 / スクリプトはどちらでも動作」と `#Requires -Version 5.1` は
    実態と食い違っていた。BOM 付きへ統一する案もあったが、PS 7 の既定(BOM なし)から外れるため、
    **PS 7 専用に割り切る**方針を採用した。
- 変更内容:
  - `#Requires -Version 5.1` → `-Version 7.0`(Diff / InstallPsScript / CheckPsTools)。
    宣言の無かった KillLine / MdToPdf / Set-AiConfig にも `#Requires -Version 7.0` を追加。
    AiMermaid.ps1 はドットソース専用のライブラリのため宣言しない(呼び出し元の MdToPdf.ps1 が宣言済み)。
  - エンコーディングを **BOM なし + LF** に統一。BOM + 単独 CRLF が混在していた
    AiMermaid.ps1 / AiMermaid.Tests.ps1 / Set-AiConfig.Tests.ps1 を正規化した。
  - `.gitattributes` を新規追加し、`*.ps1` `*.md` 等の改行を `eol=lf` に固定
    (`*.bat` `*.cmd` は CRLF でないと動かないため除外)。clone / チェックアウト時の揺れを防ぐ。
  - `CheckPsTools.ps1` に **④ エンコーディングチェック**を追加。SourceRoot 配下の `.ps1` を再帰的に
    走査し、BOM または CRLF を含むファイルを赤字で列挙する。戻り値にも
    `EncodingIssueCount` / `EncodingIssues` を追加した。
  - `CheckPsTools` をプロファイルへ登録(これまで未登録だった)。
  - README(ルート / powershell) と docs(Diff / Set-AiConfig / MdToPdf) の動作環境記述を実態に合わせた。
    MdToPdf.md の「客先環境(PS 5.1)への配布」節は削除せず、**配布時に BOM 付きへ変換する手順**として
    位置づけを整理し、PS 7 では `Set-Content -Encoding UTF8` が BOM なしになる点を踏まえて
    `UTF8Encoding($true)` を使う例に差し替えた。
- 作業中の失敗と修正:
  - 変更した `.ps1` を再配置する際、converter 配下にも `InstallPsScript.ps1` を実行してしまい、
    **不要なラッパー関数 `MdToPdf` / `Set-AiConfig` / `AiMermaid` がプロファイルに追加された**。
    特に `MdToPdf` は MdToPdf.ps1 内で定義される本体をラッパーが上書きしてしまい、
    `& $scriptPath @args` では関数を定義するだけで何も起きない状態になっていた。
    3 つとも削除し、converter 配下は `Copy-Item` による複写のみに切り替えた。
    → 単に再配置したいだけの場合に `InstallPsScript.ps1` を使うと関数登録まで走る点に注意。
  - 前回追加したエイリアス解除行の生成で、解除行が無いケースに空行が 2 行入る不具合があった
    (`$blockLines = @('')` の後に `@('', '<#' ...)` を足していたため)。解除行側の末尾に `''` を
    移動して修正し、エイリアスあり/なしの両方を疑似リポジトリで生成して行送りを確認した。
- 確認:
  - 全 11 本の `.ps1` が PS 7 で Parse OK。`CheckPsTools` のエンコーディングチェックも
    「OK (11 件すべて BOM なし + LF)」。
  - `Invoke-Pester tests\unit` … 36 件すべて成功。
  - 新規セッションで `Diff` / `KillLine` / `InstallPsScript` / `CheckPsTools` / `MdToPdf` が
    すべて Function として解決すること、`MdToPdf` がラッパーではなく本体(`-Pattern` を持つ)で
    あること、`AiMermaid` / `Set-AiConfig` 関数が存在しないことを確認。
  - `CheckPsTools` … スクリプト 7 件すべてインストール済み / プロファイル一致。

### InstallPsScript に -CopyOnly と関数ライブラリ検出を追加

- 対象: [tools/InstallPsScript.ps1](../tools/InstallPsScript.ps1) / [README.md](../README.md)
- きっかけ:
  - 上記の作業中に、再配置目的で converter へ `InstallPsScript.ps1` を実行してしまい、
    不要なラッパー関数を作って `MdToPdf` を壊しかけた。同じ事故を仕組みで防ぐ。
- 変更内容:
  - `-CopyOnly`(エイリアス `-c`) を追加。② の複写のみを行い、③ 関数定義の追加と
    ④ `$PROFILE` の同期をスキップする。既にインストール済みのスクリプトを修正して
    置き直すだけの用途を想定。
  - `Test-FunctionLibrary` を追加。AST を解析し、**トップレベルに param ブロックが無く、
    実行文がすべて関数定義**であるスクリプトを「関数ライブラリ形式」と判定する。
    該当する場合は ③④ を自動スキップし、ドットソースの記述例を案内する。
    (この形式は `&` で実行しても関数が子スコープで消えるだけで何も起きず、
     ラッパー関数を作るとドットソース済みの本体を後から上書きしてしまうため)
  - 見出しの「関数名」欄は、登録しない場合 `(登録しません)` と表示する。
- 判定の実測(リポジトリ内 11 本):
  - True : `converter/MdToPdf.ps1`、`converter/AiMermaid.ps1` … 実際に壊れた 2 本のみ
  - False: 通常スクリプト(Diff / KillLine / InstallPsScript / CheckPsTools)、
    トップレベル実行文を持つ `Set-AiConfig.ps1`、テスト、プロファイル
- 確認:
  - 疑似リポジトリで 4 パターンを実行。① 通常スクリプト → 従来どおり ③④ が動作、
    ② `-CopyOnly` → ② のみ、③ `-c` エイリアス → 同上、
    ④ 関数ライブラリ形式 → 自動スキップし `. ($Global:ConverterDir + 'ZzzLib.ps1')` を案内。
    テスト用に配置先へ複写されたファイルはすべて削除済み。
  - 実リポジトリで `InstallPsScript.ps1 tools\InstallPsScript.ps1 -c` を実行し、複写のみで
    プロファイルが変化しないことを確認。
  - `Invoke-Pester tests\unit` … 36 件すべて成功。`CheckPsTools` も全項目 OK。
