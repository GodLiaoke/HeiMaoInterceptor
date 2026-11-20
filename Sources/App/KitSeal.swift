import Foundation

/// 看门狗框架的结构校验（1.2.4）
///
/// 主程序这一侧对 HMKit 做的是「结构与身份」校验，而不是代码段哈希：
/// 两边都用代码段哈希会互相锁死（patch 一边就会破坏另一边的期望值），
/// 所以分工是 —— 看门狗那边用代码段哈希盯主程序，主程序这边盯框架的结构。
///
/// 校验项：
///   1. 框架二进制在不在（删掉 → 直接熔断，不等 dyld 报错）
///   2. `__TEXT` 段大小是否等于构建期写入的值（换一个别的框架进来立刻发现）
///   3. 二进制里是否有我们自己的标记串（防止拿同尺寸的空壳顶上）
///
/// 大小与标记都是打包脚本写进来的，源码里只是占位符。
enum KitSeal {

    /// 打包脚本会把 8 个 0 换成真实的 __TEXT 段字节数
    private static let sizeMark = "HMKITSZ:"
    private static let sizeRaw = "HMKITSZ:00000000"

    /// 框架里必须出现的一串标记（编译进 HMKit 的签名字符串）
    private static let markBytes = Array("hm-wd-2".utf8)

    static var expectedSize: UInt64? {
        let s = String(sizeRaw.dropFirst(sizeMark.count))
        guard s.count == 8, let v = UInt64(s), v > 0 else { return nil }
        return v
    }

    static var frameworkPath: String? {
        let p = Bundle.main.bundleURL
            .appendingPathComponent("Frameworks")
            .appendingPathComponent("HMKit.framework")
            .appendingPathComponent("HMKit")
            .path
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }

    static var present: Bool { frameworkPath != nil }

    /// 结构是否可信。
    ///
    /// 发布包里 sizeRaw 已被打包脚本写成真实值，三项全过才算通过；
    /// 本地调试构建还没写值时只做「在不在 + 标记」两项，免得开发机一跑就崩。
    static func intact() -> Bool {
        guard let path = frameworkPath else { return false }
        guard containsMark(path: path) else { return false }
        guard let want = expectedSize else { return true }
        guard let slice = BinarySeal.textSlice(of: path) else { return false }
        return slice.size == want
    }

    /// 在文件里找标记串（分块扫，避免把整个二进制读进内存）
    private static func containsMark(path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        let chunkSize = 128 * 1024
        let overlap = markBytes.count - 1
        var carry = [UInt8]()
        while true {
            guard let chunk = try? fh.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            var buf = carry
            buf.append(contentsOf: chunk)
            if find(buf) { return true }
            carry = Array(buf.suffix(max(0, overlap)))
        }
        return false
    }

    private static func find(_ hay: [UInt8]) -> Bool {
        guard hay.count >= markBytes.count else { return false }
        let first = markBytes[0]
        var i = 0
        let limit = hay.count - markBytes.count
        while i <= limit {
            if hay[i] == first {
                var j = 1
                while j < markBytes.count, hay[i + j] == markBytes[j] { j += 1 }
                if j == markBytes.count { return true }
            }
            i += 1
        }
        return false
    }
}
