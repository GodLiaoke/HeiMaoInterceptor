import Foundation

/// 构建期加密字符串的解码器（1.2.3）
///
/// `Tools/obfuscate_strings.py` 会把安全核心里的字符串字面量换成
/// `StrBox.d([...])`：数组是 UTF-8 字节和下面这张密钥表异或的结果。
/// 二进制里 `strings` 不到原文，静态分析只能看到一串数字。
///
/// 密钥表本身按位还原，不连续存放在数据段里。
enum StrBox {

    private static let seed: [UInt8] = [0x5D, 0x21, 0xB7, 0x4E, 0x9A, 0x33, 0xE8, 0x76,
                                        0x12, 0xCF, 0x88, 0x45, 0xB3, 0x6A, 0x02, 0xF1]

    @inline(never)
    private static func keyByte(_ i: Int) -> UInt8 {
        let a = seed[(i &* 5 &+ 3) & 15]
        let b = UInt8(truncatingIfNeeded: i &* 31 &+ 17)
        return a ^ b & 0x7F
    }

    static func d(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        var out = bytes
        for i in 0..<out.count {
            out[i] ^= keyByte(i)
        }
        return String(bytes: out, encoding: .utf8) ?? ""
    }
}
