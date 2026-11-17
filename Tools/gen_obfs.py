#!/usr/bin/env python3
"""从 stdin 读 JSON 字符串数组，生成 Sources/Shared/Obfs.swift（密文表）。

明文不落盘：调用方用管道把明文喂进来，脚本只输出密文。
解码函数必须与 Swift 侧 Obfs.keyByte 完全一致。
"""
import json
import secrets
import sys

SEED = secrets.token_bytes(16)


def key_byte(i: int, j: int) -> int:
    a = SEED[(i * 7 + j * 3) & 15]
    b = (i * 13 + j * 29) & 0xFF
    c = (j * j + i * 5) & 0xFF
    return a ^ b ^ c


def enc(i: int, text: str) -> list:
    return [b ^ key_byte(i, j) for j, b in enumerate(text.encode("utf-8"))]


def main():
    items = json.load(sys.stdin)
    rows = []
    for i, s in enumerate(items):
        body = ", ".join(str(x) for x in enc(i, s))
        rows.append("        [" + body + "],")
    seed = ", ".join(str(x) for x in SEED)

    out = f'''import Foundation

/// 内置常量表。
///
/// 二进制里不出现任何明文：每一条都按位还原，还原用的种子散在别处，
/// 直接 strings / 十六进制搜都拿不到地址和密钥。
enum Obfs {{

    private static let seed: [UInt8] = [{seed}]

    private static let table: [[UInt8]] = [
{chr(10).join(rows)}
    ]

    private static var cache: [Int: String] = [:]
    private static let lock = NSLock()

    @inline(never)
    private static func keyByte(_ i: Int, _ j: Int) -> UInt8 {{
        let a = seed[(i &* 7 &+ j &* 3) & 15]
        let b = UInt8(truncatingIfNeeded: i &* 13 &+ j &* 29)
        let c = UInt8(truncatingIfNeeded: j &* j &+ i &* 5)
        return a ^ b ^ c
    }}

    static func s(_ index: Int) -> String {{
        lock.lock()
        if let hit = cache[index] {{
            lock.unlock()
            return hit
        }}
        lock.unlock()

        guard index >= 0, index < table.count else {{ return "" }}
        var bytes = table[index]
        if !bytes.isEmpty {{
            for j in 0..<bytes.count {{ bytes[j] ^= keyByte(index, j) }}
        }}
        let out = String(bytes: bytes, encoding: .utf8) ?? ""
        lock.lock()
        cache[index] = out
        lock.unlock()
        return out
    }}

    /// 拆成两段的常量在这里拼回去
    static func join(_ a: Int, _ b: Int) -> String {{ s(a) + s(b) }}
}}
'''
    sys.stdout.write(out)


if __name__ == "__main__":
    main()
