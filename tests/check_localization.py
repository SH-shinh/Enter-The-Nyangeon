"""校验本地化源的 UTF-8 BOM、CRLF、CSV 列宽及 key 唯一性。"""
import csv
import io
from pathlib import Path
import sys


def bare_quote(text):
    # csv.reader(strict=True) 仍允许未加引号字段中的裸双引号，Godot 会吞掉它们。
    state = "start"
    for char in text:
        if state == "quoted":
            if char == '"': state = "after"
        elif state == "after":
            if char == '"': state = "quoted"
            elif char in ",\r\n": state = "start"
            else: return True
        elif char == '"':
            if state != "start": return True
            state = "quoted"
        elif char in ",\r\n":
            state = "start"
        else:
            state = "plain"
    return state == "quoted"


def check(path):
    errors = []
    data = path.read_bytes()
    if not data.startswith(b"\xef\xbb\xbf"):
        errors.append("缺少 UTF-8 BOM")
    remaining = data.replace(b"\r\n", b"")
    if b"\n" in remaining or b"\r" in remaining:
        errors.append("存在非 CRLF 行尾")
    try:
        text = data.decode("utf-8-sig", errors="strict")
        if bare_quote(text):
            errors.append("字段内双引号未按 CSV 规则转义")
        rows = list(csv.reader(io.StringIO(text, newline=""), strict=True))
    except (UnicodeDecodeError, csv.Error) as error:
        return errors + [str(error)]
    if not rows or rows[0] != ["", "zh_CN", "en", "pt", "vi_VN", "ja", "ko", "ru"]:
        errors.append("本地化表头不符合约定")
    seen = set()
    for index, row in enumerate(rows[1:], 2):
        if len(row) != 8:
            errors.append(f"记录 {index} 的列数不是 8")
        elif not row[0] or row[0] in seen:
            errors.append(f"记录 {index} 的 key 为空或重复：{row[0]}")
        else:
            seen.add(row[0])
    return errors


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    failed = False
    for path in sorted(Path(__file__).resolve().parents[1].glob("ETN_*localization.csv")):
        errors = check(path)
        failed |= bool(errors)
        print(path.name + ": " + ("；".join(errors) if errors else "PASS"))
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
