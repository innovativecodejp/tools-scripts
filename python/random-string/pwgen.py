#!/usr/bin/env python3
import hashlib
import hmac
import re
import sys
import unicodedata

BASE_CHARS = "23456789" + "ABCDEFGHJKLMNPQRSTUVWXYZ" + "abcdefghijkmnpqrstuvwxyz"
SYMBOL_CHARS = "!#$%*+-=?@_"

DIGIT_SET = set("23456789")
UPPER_SET = set("ABCDEFGHJKLMNPQRSTUVWXYZ")
LOWER_SET = set("abcdefghijkmnpqrstuvwxyz")
SYMBOL_SET = set(SYMBOL_CHARS)

CODE_RE = re.compile(r'^(\d{6})(s)?(?:-(\d{1,2}))?$')

SALT = b"pwgen-v1"
ITERATIONS = 600_000

EMOJI64 = [
    "🐱", "🐶", "🐻", "🐼", "🦊", "🐯", "🦁", "🐮",
    "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🦉", "🦅",
    "🦆", "🦇", "🐺", "🐴", "🦄", "🐝", "🐛", "🦋",
    "🐌", "🐢", "🐍", "🦎", "🐙", "🦑", "🦀", "🐠",
    "🐳", "🐬", "🦈", "🐊", "🦓", "🦒", "🐘", "🦏",
    "🐪", "🦘", "🐇", "🦔", "🦦", "🦨", "🦥", "🐿️",
    "🌵", "🌲", "🌴", "🌻", "🌸", "🍀", "🍄", "🌙",
    "⭐", "🔥", "💧", "⚡", "❄️", "🌈", "🍎", "🍋",
]

assert len(EMOJI64) == 64
assert len(set(EMOJI64)) == 64


def normalize(s: str) -> str:
    return unicodedata.normalize("NFKC", s).strip()


def parse_code(code: str):
    m = CODE_RE.match(code)
    if not m:
        raise ValueError(f"invalid CODE: {code!r}")
    digits, has_s, len_str = m.groups()
    length = int(len_str) if len_str is not None else 16
    if not (8 <= length <= 32):
        raise ValueError(f"LEN out of range (8-32): {length}")
    return digits, bool(has_s), length


def derive_key(passphrase: str) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", passphrase.encode("utf-8"), SALT, ITERATIONS, dklen=32)


def build_charset(has_s: bool) -> str:
    return BASE_CHARS + SYMBOL_CHARS if has_s else BASE_CHARS


def required_sets(has_s: bool):
    sets = [DIGIT_SET, UPPER_SET, LOWER_SET]
    if has_s:
        sets.append(SYMBOL_SET)
    return sets


def gen_password(key: bytes, code: str, length: int, charset: str) -> str:
    n = len(charset)
    threshold = 256 - (256 % n)
    sets = required_sets(len(charset) > len(BASE_CHARS))

    attempt = 0
    while True:
        chars = []
        block = 0
        while len(chars) < length:
            digest = hmac.new(key, f"pw|{code}|{attempt}|{block}".encode("utf-8"), hashlib.sha256).digest()
            for b in digest:
                if b < threshold:
                    chars.append(charset[b % n])
                    if len(chars) == length:
                        break
            block += 1

        password = "".join(chars)
        if all(any(c in s for c in password) for s in sets):
            return password
        attempt += 1


def confirmation_emoji(key: bytes) -> str:
    tag = hmac.new(key, b"check", hashlib.sha256).digest()
    b0, b1 = tag[0], tag[1]
    idx1 = b0 >> 2
    idx2 = ((b0 & 0b11) << 4) | (b1 >> 4)
    return EMOJI64[idx1] + EMOJI64[idx2]


VERSION = "1.0.0"

USAGE = """\
使い方: pwgen.py [PASSPHRASE CODE]

パスフレーズとコードから、決定的なパスワードを生成します。

引数:
  PASSPHRASE  パスワード生成の元になる秘密の文字列
  CODE        生成条件を表すコード (形式: NNNNNN[s][-LEN])
              NNNNNN  6桁の数字
              s       付けると記号を含める (省略可)
              -LEN    パスワードの長さ 8-32 (省略時は16)

引数を省略すると、対話的に入力を求めます。

チェックコード:
  出力の check: に続く絵文字2つは、パスフレーズ(のみ)から
  導出した鍵の確認用コードです。CODEには依存しません。
  同じパスフレーズなら常に同じ絵文字になるため、
  パスフレーズの入力間違いに気付く手がかりとして使えます。

オプション:
  -h, --help     このヘルプを表示して終了
  -v, --version  バージョン情報を表示して終了
"""


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:]

    if any(a in ("-h", "--help") for a in args):
        print(USAGE, end="")
        return
    if any(a in ("-v", "--version") for a in args):
        print(VERSION)
        return

    if len(args) >= 2:
        passphrase, code = args[0], args[1]
    else:
        passphrase = input("passphrase: ")
        code = input("code: ")

    passphrase = normalize(passphrase)
    code = normalize(code)

    digits, has_s, length = parse_code(code)
    key = derive_key(passphrase)
    charset = build_charset(has_s)
    password = gen_password(key, code, length, charset)
    check = confirmation_emoji(key)

    print(f"password: {password}  check: {check}")


if __name__ == "__main__":
    try:
        main()
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
