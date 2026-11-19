#!/usr/bin/env python3
"""构建期生成 CRC 链校验表（Sources/Shared/IntegritySeal.swift）。

每个源文件算一个 CRC32，运行时 Integrity 会沿着
arm -> checkA -> checkB -> checkC 逐层复算。
只要有一个文件被改过，digest 就对不上，链路直接断。

必须在 rename_types.py 之后运行（改名会改源文件内容）。
"""
import glob
import os
import sys
import zlib


def crc32(seed: int, value: int) -> int:
    """与 Swift 侧 Integrity.crc32 逐字节一致：4 字节小端 + 反射多项式。"""
    c = (seed ^ 0xFFFFFFFF) & 0xFFFFFFFF
    v = value & 0xFFFFFFFF
    for _ in range(4):
        c ^= v & 0xFF
        for _ in range(8):
            c = ((c >> 1) ^ 0xEDB88320) if (c & 1) else (c >> 1)
        v >>= 8
    return c ^ 0xFFFFFFFF


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    files = sorted(
        f for f in glob.glob(os.path.join(root, "Sources", "**", "*.swift"), recursive=True)
        if not f.endswith("IntegritySeal.swift")
    )
    if not files:
        print("NO_SOURCES", file=sys.stderr)
        return 1

    parts = []
    for f in files:
        with open(f, "rb") as fh:
            parts.append(zlib.crc32(fh.read()) & 0xFFFFFFFF)

    acc = 0x811C9DC5
    for i, v in enumerate(parts):
        acc = crc32((acc + (i * 2654435761)) & 0xFFFFFFFF, v)

    tokens = []
    for i in range(4):
        mix = ((parts[i % len(parts)] * 2654435761) ^ i) & 0xFFFFFFFF
        tokens.append(mix & 0xFFFF)

    body = ",\n        ".join("0x%08X" % p for p in parts)
    toks = ", ".join("0x%04X" % t for t in tokens)

    out = f'''import Foundation

/// 构建期生成的 CRC 链（Tools/gen_crc.py）
///
/// 每个源文件一个 CRC32，运行时 Integrity 逐层复算。
/// 这个文件每次构建都会重写，不要手工改。
enum IntegritySeal {{
    static let parts: [UInt32] = [
        {body}
    ]
    static let digest: UInt32 = 0x{acc:08X}
    static let count: Int = {len(parts)}
    static let tokens: [UInt32] = [{toks}]
}}
'''
    dest = os.path.join(root, "Sources", "Shared", "IntegritySeal.swift")
    with open(dest, "w") as fh:
        fh.write(out)
    print("CRC_SEAL_OK files=%d digest=0x%08X" % (len(parts), acc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
