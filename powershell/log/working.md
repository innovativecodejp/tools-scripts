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
