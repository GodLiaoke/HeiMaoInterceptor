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


M = 0xFFFFFFFF


def mix_a(x):
    v = (x * 0x9E3779B9) & M
    v ^= v >> 13
    v = (v + 0x85EBCA6B) & M
    v ^= (v << 7) & M
    return v & M


def mix_b(x):
    v = x ^ 0x5BF03635
    for _ in range(3):
        v = (((v & 0xFFFFFFFE) >> 1) ^ (0x9908B0DF if (v & 1) == 1 else 0)) & M
    return v


def mix_c(x):
    a = x & 0x00FF00FF
    b = (x >> 8) & 0x00FF00FF
    return ((a * 3 + b * 5) & M) ^ (x >> 16)


def mix_d(x):
    v = x
    for i in range(5):
        v = (v * 1664525 + 1013904223 + i) & M
    return v


def mix_e(x):
    s = ((x ^ (x >> 15)) * 0x2545F491) & M
    return s ^ (s >> 13)


def mix_f(x):
    v = (~x) & M
    v = (((v << 5) | (v >> 27))) & M
    v = (v + 0x7F4A7C15) & M
    v = (((v << 11) | (v >> 21))) & M
    return v


def mix_g(x):
    acc = 0
    for i in range(1, 5):
        acc = ((acc + ((x * i) & M)) & M) ^ (x >> i)
    return acc & M


def mix_h(x):
    t = (x * x) & M
    return (((t & 0xFFFF0000) >> 16) | ((t & 0x0000FFFF) << 16)) & M


def mix_i(x):
    v = (x + 0x1B873593) & M
    v ^= v >> 17
    v = (v * 0xED5AD551) & M
    v ^= v >> 11
    return v


def mix_j(x):
    v = x
    for m in (3, 5, 7, 11, 13, 17, 19, 23):
        v = (v ^ ((v * m) & M)) & M
    return v


def mix_k(x):
    v = x
    for _ in range(6):
        v = (((v >> 1) ^ 0xEDB88320) if (v & 1) == 1 else (v >> 1)) & M
    return v


def mix_l(x):
    return (((x * 0xCC9E2D51) & M) ^ (((x * 0x1B873593) & M) >> 16)) & M


def churn(seed: int) -> int:
    v = seed
    for fn in (mix_a, mix_b, mix_c, mix_d, mix_e, mix_f,
               mix_g, mix_h, mix_i, mix_j, mix_k, mix_l):
        v = fn(v)
    return v & M


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

    noise = churn(acc)

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
    static let noise: UInt32 = 0x{noise:08X}
}}
'''
    dest = os.path.join(root, "Sources", "Shared", "IntegritySeal.swift")
    with open(dest, "w") as fh:
        fh.write(out)
    print("CRC_SEAL_OK files=%d digest=0x%08X noise=0x%08X" % (len(parts), acc, noise))
    return 0


if __name__ == "__main__":
    sys.exit(main())
