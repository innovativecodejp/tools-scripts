<#
    Diff.ps1 のユニットテスト（Pester v5）
    実行: Invoke-Pester .\tests\unit\Diff.Tests.ps1 -Output Detailed

    注意: -WhatIf を付けて実行するため、TortoiseGit の GUI は一切起動しません。
          検証対象は「組み立てられたコマンドライン文字列」です。
#>

BeforeAll {
    # tests\unit → tests → powershell
    $script:PowerShellRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:DiffScript     = Join-Path $script:PowerShellRoot 'tools\Diff.ps1'
    $script:RepoRoot       = Split-Path -Parent $script:PowerShellRoot

    # リポジトリ内（= Git 管理下）の既存ファイル / フォルダ
    $script:RepoFile = Join-Path $script:RepoRoot 'README.md'
    $script:RepoDir  = $script:PowerShellRoot

    # 空白を含むパス・Git 管理外パスの検証用（一時領域に作成する）
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('DiffTests {0}' -f [Guid]::NewGuid())
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    $script:TempFileA = Join-Path $script:TempDir 'one.txt'
    $script:TempFileB = Join-Path $script:TempDir 'two.txt'
    Set-Content -LiteralPath $script:TempFileA -Value 'a'
    Set-Content -LiteralPath $script:TempFileB -Value 'b'

    # Write-Host の出力（情報ストリーム）を捨てて戻り値だけを取り出すヘルパー。
    function Invoke-Diff {
        param([hashtable]$Parameters)
        return (& $script:DiffScript @Parameters -WhatIf 6> $null)
    }
}

AfterAll {
    if (Test-Path -LiteralPath $script:TempDir) {
        Remove-Item -LiteralPath $script:TempDir -Recurse -Force
    }
}

Describe 'コマンドの選択' {

    It 'ファイル指定は diff コマンドになり、path が絶対パスで引用される' {
        $result = Invoke-Diff @{ Path = $script:RepoFile }

        $result.Command   | Should -Be 'diff'
        $result.Arguments | Should -BeLike '/command:diff /path:"*README.md"'
        $result.Path      | Should -Be (Resolve-Path -LiteralPath $script:RepoFile).Path
    }

    It 'フォルダ指定は repostatus（変更確認ダイアログ）になる' {
        $result = Invoke-Diff @{ Path = $script:RepoDir }

        $result.Command   | Should -Be 'repostatus'
        $result.Arguments | Should -BeLike '/command:repostatus /path:"*"'
    }

    It 'フォルダ + リビジョン指定は showcompare になり revision1/revision2 を使う' {
        $result = Invoke-Diff @{ Path = $script:RepoDir; StartRev = 'HEAD~1'; EndRev = 'HEAD' }

        $result.Command   | Should -Be 'showcompare'
        $result.Arguments | Should -BeLike '*/revision1:HEAD~1*'
        $result.Arguments | Should -BeLike '*/revision2:HEAD*'
        $result.Arguments | Should -Not -BeLike '*/startrev:*'
    }
}

Describe 'オプションの組み立て' {

    It '-Path2 を指定すると path2 が付き、リビジョン指定は付かない' {
        $result = Invoke-Diff @{ Path = $script:TempFileA; Path2 = $script:TempFileB }

        $result.Command   | Should -Be 'diff'
        $result.Arguments | Should -BeLike '*/path2:"*two.txt"*'
        $result.Arguments | Should -Not -BeLike '*/startrev:*'
        $result.Path2     | Should -Be (Resolve-Path -LiteralPath $script:TempFileB).Path
    }

    It '-StartRev / -EndRev が startrev / endrev に変換される' {
        $result = Invoke-Diff @{ Path = $script:RepoFile; StartRev = 'HEAD~3'; EndRev = 'HEAD' }

        $result.Arguments | Should -BeLike '*/startrev:HEAD~3*'
        $result.Arguments | Should -BeLike '*/endrev:HEAD*'
    }

    It '-s / -e はそれぞれ -StartRev / -EndRev のエイリアスとして働く' {
        $result = & $script:DiffScript $script:RepoFile -s 'HEAD~2' -e 'HEAD' -WhatIf 6> $null

        $result.Arguments | Should -BeLike '*/startrev:HEAD~2*'
        $result.Arguments | Should -BeLike '*/endrev:HEAD*'
    }

    It '-Unified / -Line が unified / line に変換される' {
        $result = Invoke-Diff @{ Path = $script:RepoFile; Unified = $true; Line = 120 }

        $result.Arguments | Should -BeLike '*/unified*'
        $result.Arguments | Should -BeLike '*/line:120*'
    }

    It '空白を含むパスはコロンの後ろだけが引用される' {
        $result = Invoke-Diff @{ Path = $script:TempFileA; Path2 = $script:TempFileB }

        # /path:"C:\...\DiffTests <guid>\one.txt" の形（トークン全体の引用ではない）
        $result.Arguments | Should -BeLike '/command:diff /path:"*"*'
        $result.Arguments | Should -Not -BeLike '"/path:*'
    }

    It 'フォルダ指定時の -Unified / -Line は警告して無視される' {
        $warnings = @()
        $result = & $script:DiffScript $script:RepoDir -Unified -Line 10 -WhatIf `
            -WarningVariable warnings -WarningAction SilentlyContinue 6> $null

        $result.Arguments | Should -Not -BeLike '*/unified*'
        $result.Arguments | Should -Not -BeLike '*/line:*'
        $warnings.Count   | Should -BeGreaterThan 0
    }
}

Describe '実行前チェック' {

    It '-WhatIf では TortoiseGit を起動せず ProcessId が null になる' {
        $result = Invoke-Diff @{ Path = $script:RepoFile }

        $result.ProcessId | Should -BeNullOrEmpty
        $result.ExitCode  | Should -BeNullOrEmpty
    }

    # 本スクリプトは house style に従い $ErrorActionPreference = 'Stop' で動作するため、
    # Write-Error は終了エラーになる（= 呼び出し側には例外として伝わる）。
    It 'Git 管理外のパスは終了エラーになる' {
        {
            & $script:DiffScript $script:TempFileA -WhatIf 6> $null
        } | Should -Throw '*Git の管理下にありません*'
    }

    It '-Path2 指定時は Git 管理外でもエラーにならない（BASE を必要としないため）' {
        $result = Invoke-Diff @{ Path = $script:TempFileA; Path2 = $script:TempFileB }

        $result.Command | Should -Be 'diff'
    }

    It '存在しないパスは終了エラーになる' {
        {
            & $script:DiffScript (Join-Path $script:RepoRoot 'NOT_EXIST.md') -WhatIf 6> $null
        } | Should -Throw '*パスが見つかりません*'
    }

    It '-TortoiseGitProc に存在しないパスを指定すると停止する' {
        {
            & $script:DiffScript $script:RepoFile -TortoiseGitProc 'C:\not-exist\TortoiseGitProc.exe' -WhatIf 6> $null
        } | Should -Throw '*TortoiseGitProc.exe が見つかりません*'
    }
}

Describe 'TortoiseGitProc.exe の解決' {

    It '解決された実行ファイルが実在する' {
        $result = Invoke-Diff @{ Path = $script:RepoFile }

        $result.Executable                            | Should -Not -BeNullOrEmpty
        (Test-Path -LiteralPath $result.Executable)   | Should -BeTrue
        (Split-Path -Leaf $result.Executable)         | Should -Be 'TortoiseGitProc.exe'
    }
}
