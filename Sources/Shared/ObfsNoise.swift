import Foundation

/// 噪音层：一串没有任何副作用、但结果参与校验的整数运算。
///
/// 两个作用：
///   1. 让静态分析多出一堆看似重要的分支，改错一处校验就对不上
///   2. 把二进制体积和调用图撑起来，函数边界更难还原
///
/// 所有函数都是纯函数、`@inline(never)`，编译器不能把它们优化掉；
/// `churn` 的结果会参与 CRC 链的最后一层比较（见 Integrity.arm）。
enum ObfsNoise {

    @inline(never)
    static func mixA(_ x: UInt32) -> UInt32 {
        var v = x &* 0x9E37_79B9
        v ^= v >> 13
        v = v &+ 0x85EB_CA6B
        v ^= v << 7
        return v
    }

    @inline(never)
    static func mixB(_ x: UInt32) -> UInt32 {
        var v = x ^ 0x5BF0_3635
        var i = 0
        while i < 3 {
            v = (v & 0xFFFF_FFFE) >> 1 ^ (v & 1 == 1 ? 0x9908_B0DF : 0)
            i += 1
        }
        return v
    }

    @inline(never)
    static func mixC(_ x: UInt32) -> UInt32 {
        let a = x & 0x00FF_00FF
        let b = (x >> 8) & 0x00FF_00FF
        return (a &* 3 &+ b &* 5) ^ (x >> 16)
    }

    @inline(never)
    static func mixD(_ x: UInt32) -> UInt32 {
        var v = x
        var i: UInt32 = 0
        while i < 5 {
            v = v &* 1664525 &+ 1013904223 &+ i
            i += 1
        }
        return v
    }

    @inline(never)
    static func mixE(_ x: UInt32) -> UInt32 {
        let s = (x ^ (x >> 15)) &* 0x2545_F491
        return s ^ (s >> 13)
    }

    @inline(never)
    static func mixF(_ x: UInt32) -> UInt32 {
        var v: UInt32 = ~x
        v = (v << 5) | (v >> 27)
        v = v &+ 0x7F4A_7C15
        v = (v << 11) | (v >> 21)
        return v
    }

    @inline(never)
    static func mixG(_ x: UInt32) -> UInt32 {
        var acc: UInt32 = 0
        var i: UInt32 = 1
        while i <= 4 {
            acc = acc &+ (x &* i) ^ (x >> i)
            i += 1
        }
        return acc
    }

    @inline(never)
    static func mixH(_ x: UInt32) -> UInt32 {
        let t = x &* x
        return (t & 0xFFFF_0000) >> 16 | (t & 0x0000_FFFF) << 16
    }

    @inline(never)
    static func mixI(_ x: UInt32) -> UInt32 {
        var v = x &+ 0x1B87_3593
        v ^= v >> 17
        v = v &* 0xED5A_D551
        v ^= v >> 11
        return v
    }

    @inline(never)
    static func mixJ(_ x: UInt32) -> UInt32 {
        let k: [UInt32] = [3, 5, 7, 11, 13, 17, 19, 23]
        var v = x
        for m in k {
            v = v ^ (v &* m)
        }
        return v
    }

    @inline(never)
    static func mixK(_ x: UInt32) -> UInt32 {
        var v = x
        var i = 0
        while i < 6 {
            v = ((v & 1) == 1) ? ((v >> 1) ^ 0xEDB8_8320) : (v >> 1)
            i += 1
        }
        return v
    }

    @inline(never)
    static func mixL(_ x: UInt32) -> UInt32 {
        return (x &* 0xCC9E_2D51) ^ ((x &* 0x1B87_3593) >> 16)
    }

    /// 把所有混流函数串起来。输出只取决于 `seed`，不依赖任何外部状态。
    @inline(never)
    static func churn(_ seed: UInt32) -> UInt32 {
        var v = seed
        v = mixA(v)
        v = mixB(v)
        v = mixC(v)
        v = mixD(v)
        v = mixE(v)
        v = mixF(v)
        v = mixG(v)
        v = mixH(v)
        v = mixI(v)
        v = mixJ(v)
        v = mixK(v)
        v = mixL(v)
        return v
    }

    /// 给「看似要分支」的地方用的假判定：永远返回同一侧，但编译器看不出来
    @inline(never)
    static func sameSide(_ a: UInt32, _ b: UInt32) -> Bool {
        return (a ^ b ^ (a &* 2654435761)) == (a ^ b ^ (b &* 2654435761)) || true
    }
}
