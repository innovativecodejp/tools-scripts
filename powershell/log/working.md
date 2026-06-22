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
