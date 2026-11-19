import Foundation

/// 构建期生成的 CRC 链（Tools/gen_crc.py）
///
/// 每个源文件一个 CRC32，运行时 Integrity 逐层复算。
/// 这个文件每次构建都会重写，不要手工改。
enum IntegritySeal {
    static let parts: [UInt32] = [
        0x1E450802,
        0x46679F41,
        0xDD75E258,
        0x17E28840,
        0x05227969,
        0xCFF65DBC,
        0x95F5C05E,
        0x3C70AC1D,
        0xD9C17711,
        0x5C55225C,
        0xBDC3DF1D,
        0x863BEECE,
        0xFA86F47A,
        0x058D987E,
        0xE2D36DEC,
        0x1938E750,
        0xFA1C96DD,
        0x6B1C8104,
        0x5A45A63A,
        0x3FBB44CF,
        0x8A24B15B,
        0x7CA8F7F0,
        0x64B88850,
        0x34C59C31,
        0xE2CC7172,
        0x5BE16A8F,
        0x7BBCEC04,
        0x32A3B771,
        0x78DA258A
    ]
    static let digest: UInt32 = 0x6C6826B6
    static let count: Int = 29
    static let tokens: [UInt32] = [0x7B62, 0xD4F0, 0x16DA, 0x7443]
    static let noise: UInt32 = 0xD889C2A8
}
