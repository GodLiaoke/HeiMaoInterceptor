#!/usr/bin/env python3
"""构建期字符串表加密（1.2.3）

为什么需要这一步：
    1.2.2 之前只有「顶层类型改名」一层，`strings 二进制` 就能把 /auth/check、
    卡密错误码、路由名这些全捞出来，照着改包很省事。

做法：
    把 Sources/Shared 里**不含转义、不含插值**的字符串字面量，替换成
    `StrBox.d([...])` —— 运行时按内置密钥表异或还原。二进制里不再有原文。

安全约束（宁可少加密，绝不改坏代码）：
    - 逐字符扫描真正的字面量边界，绝不让引号错位
    - 含 `\\`（转义 / 插值）的字面量整条跳过
    - 跳过 `case "...":` 模式位置（Swift 模式匹配不接受函数调用）
    - 跳过注释、多行字符串、Obfs.swift / StrBox.swift / 生成文件
    - 只处理 Sources/Shared（安全核心），UI 文案不动
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_DIRS = [os.path.join(ROOT, "Sources", "Shared")]
SKIP_FILES = {"Obfs.swift", "StrBox.swift", "IntegritySeal.swift"}

CASE_TAIL = re.compile(r"\bcase\b[^:]*$")

# 与 Sources/Shared/StrBox.swift 的 keyByte 逐位一致
SEED = [0x5D, 0x21, 0xB7, 0x4E, 0x9A, 0x33, 0xE8, 0x76,
        0x12, 0xCF, 0x88, 0x45, 0xB3, 0x6A, 0x02, 0xF1]


def key_byte(i: int) -> int:
    return SEED[(i * 5 + 3) % 16] ^ (((i * 31 + 17) & 0xFF) & 0x7F)


def encode(text: str):
    raw = text.encode("utf-8")
    return [b ^ key_byte(i) for i, b in enumerate(raw)]


def literals(line):
    """返回 [(start, end, content, escaped)]，只认真正的字面量边界"""
    out = []
    i, n = 0, len(line)
    while i < n:
        ch = line[i]
        if ch == "/" and i + 1 < n and line[i + 1] == "/":
            break                       # 行注释，后面都不是代码
        if ch == '"':
            j = i + 1
            buf = []
            escaped = False
            closed = False
            while j < n:
                c = line[j]
                if c == "\\":
                    escaped = True
                    j += 2
                    continue
                if c == '"':
                    closed = True
                    break
                buf.append(c)
                j += 1
            if not closed:
                break                   # 多行字符串或异常，整行不动
            out.append((i, j + 1, "".join(buf), escaped))
            i = j + 1
            continue
        i += 1
    return out


def transform_line(line):
    if '"""' in line:
        return line, 0
    stripped = line.lstrip()
    if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
        return line, 0

    edits = []
    for start, end, content, escaped in literals(line):
        if escaped or len(content) < 3:
            continue
        prefix = line[:start]
        if CASE_TAIL.search(prefix):
            continue
        if prefix.rstrip().endswith("StrBox.d("):
            continue
        edits.append((start, end, content))

    if not edits:
        return line, 0

    out = line
    for start, end, content in reversed(edits):
        enc = encode(content)
        call = "StrBox.d([" + ",".join(str(b) for b in enc) + "])"
        out = out[:start] + call + out[end:]
    return out, len(edits)


def main() -> int:
    files = 0
    lits = 0
    for d in TARGET_DIRS:
        for base, _, filenames in os.walk(d):
            for name in filenames:
                if not name.endswith(".swift") or name in SKIP_FILES:
                    continue
                path = os.path.join(base, name)
                with open(path, encoding="utf-8") as fh:
                    lines = fh.read().split("\n")

                total = 0
                out_lines = []
                for line in lines:
                    new, n = transform_line(line)
                    total += n
                    out_lines.append(new)

                if total:
                    text = "\n".join(out_lines)
                    # 自检：生成后每条字面量里都不该再包含 StrBox.d( 这种伪文本
                    for ln in out_lines:
                        for _, _, content, _ in literals(ln):
                            if "StrBox.d(" in content:
                                print("SELF_CHECK_FAIL: %s -> %s" % (path, ln.strip()[:80]))
                                return 1
                    with open(path, "w", encoding="utf-8") as fh:
                        fh.write(text)
                    files += 1
                    lits += total

    print("STRINGS_OK: %d 个文件 / %d 条字面量已加密" % (files, lits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
