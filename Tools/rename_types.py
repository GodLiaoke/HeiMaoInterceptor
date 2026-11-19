#!/usr/bin/env python3
"""构建期符号混淆：把自定义顶层类型改成无意义短名。

为什么要放构建期：源码要保持可读可维护，产物才需要看不清。
CI 在 xcodegen 之前跑一遍，改的是本次 checkout 的工作副本。

安全性约束（宁可漏改，绝不改错）：
  - 只改我们自己在 Sources/ 下声明的顶层 struct/class/enum/protocol/actor
  - 出现在 Info.plist 里的类型一律不动（NSExtensionPrincipalClass 靠名字找类）
  - 出现在任何字符串字面量里的名字一律不动（避免改变运行时字符串）
  - 只做整词替换，且映射固定 => 同一份源码每次构建结果一致
"""
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIRS = [os.path.join(ROOT, "Sources")]
PLIST_DIRS = [os.path.join(ROOT, "Resources")]

DECL = re.compile(
    r"^(?:@\w+\s+)?(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+|final\s+|indirect\s+)*"
    r"(?:struct|class|enum|protocol|actor)\s+([A-Za-z_]\w*)",
    re.M,
)
# 简化版：只匹配顶格声明（顶层类型），缩进的嵌套类型不动
TOP_DECL = re.compile(
    r"^(?:@\w+\s+)?(?:(?:public|internal|private|fileprivate|open|final|indirect)\s+)*"
    r"(?:struct|class|enum|protocol|actor)\s+([A-Za-z_]\w*)",
    re.M,
)
STRING_LIT = re.compile(r'"""(?:.|\n)*?"""|"(?:[^"\\\n]|\\.)*"')
# 插值 \\(...) 里是代码不是文本，判断名字是否出现在「文案」里时要剔掉
INTERP = re.compile(r"\\\((?:[^()]|\([^()]*\))*\)")


def swift_files():
    for d in SRC_DIRS:
        for base, _, files in os.walk(d):
            for f in files:
                if f.endswith(".swift"):
                    yield os.path.join(base, f)


def plist_text():
    out = []
    for d in PLIST_DIRS:
        for base, _, files in os.walk(d):
            for f in files:
                if f.endswith(".plist") or f.endswith(".entitlements"):
                    with open(os.path.join(base, f), encoding="utf-8", errors="ignore") as fh:
                        out.append(fh.read())
    return "\n".join(out)


# 构建期由 Tools/gen_crc.py 重新生成并引用的类型，不能改名：
# 生成脚本按原名写文件，改名后 Integrity.swift 里的引用会对不上。
PROTECTED_TYPES = {"IntegritySeal"}


def short_name(name: str) -> str:
    h = hashlib.sha256(("hm-obf|" + name).encode()).hexdigest()[:6]
    return "_x" + h


def main():
    files = sorted(swift_files())
    texts = {}
    for f in files:
        with open(f, encoding="utf-8") as fh:
            texts[f] = fh.read()

    candidates = set()
    for f, t in texts.items():
        for m in TOP_DECL.finditer(t):
            candidates.add(m.group(1))

    guarded = plist_text()
    literals = " ".join(m.group(0) for t in texts.values() for m in STRING_LIT.finditer(t))
    literals = INTERP.sub("", literals)

    mapping = {}
    skipped = []
    for name in sorted(candidates):
        if len(name) < 2:
            continue
        if name in PROTECTED_TYPES:
            skipped.append((name, "protected"))
            continue
        if name in guarded:
            skipped.append((name, "plist"))
            continue
        if re.search(r"\b" + re.escape(name) + r"\b", literals):
            skipped.append((name, "literal"))
            continue
        mapping[name] = short_name(name)

    # 冲突兜底：重名不可能（hash 6 位），但显式声明过的名字不能被覆盖
    for name in candidates:
        if name in mapping.values():
            mapping.pop(name, None)

    if not mapping:
        print("nothing to rename")
        return

    pattern = re.compile(r"\b(" + "|".join(sorted(map(re.escape, mapping), key=len, reverse=True)) + r")\b")

    changed = 0
    for f, t in texts.items():
        new = pattern.sub(lambda m: mapping[m.group(1)], t)
        if new != t:
            with open(f, "w", encoding="utf-8") as fh:
                fh.write(new)
            changed += 1

    print("renamed %d top-level types in %d files" % (len(mapping), changed))
    for name, why in skipped:
        print("  keep %s (%s)" % (name, why))

    out = os.environ.get("SYMBOL_MAP_PATH")
    if out:
        with open(out, "w", encoding="utf-8") as fh:
            for k, v in sorted(mapping.items()):
                fh.write("%s -> %s\n" % (k, v))
        print("map written to", out)


if __name__ == "__main__":
    sys.exit(main())
