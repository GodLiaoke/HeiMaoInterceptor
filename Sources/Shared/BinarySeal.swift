import Foundation
import CryptoKit

/// Mach-O 代码段指纹（1.2.4）
///
/// 为什么不用整文件哈希：巨魔 / ESign / 爱思 重签会改写 `__LINKEDIT`（签名段），
/// 整个文件的 SHA-256 每次都不同，拿它做校验只会把所有正常用户判死。
/// `__TEXT` 段是代码本体，重签不动它 —— 这才是"这个包是不是被改过"的正确判据。
///
/// 只读文件、不做任何写操作；解析失败一律返回 nil，调用方按"环境异常"处理。
enum BinarySeal {

    struct Slice {
        var offset: UInt64
        var size: UInt64
    }

    /// 取指定镜像的 __TEXT 段范围
    static func textSlice(of path: String) -> Slice? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }

        let head = fh.readData(ofLength: 32)
        guard head.count == 32 else { return nil }

        let magic = head.leUInt32(0)
        let is64: Bool
        switch magic {
        case 0xFEEDFACF: is64 = true        // MH_MAGIC_64（小端）
        case 0xCFFAEDFE: is64 = false
        default: return nil
        }
        guard is64 else { return nil }

        let ncmds = Int(head.leUInt32(16))
        let sizeofcmds = Int(head.leUInt32(20))
        guard ncmds > 0, ncmds < 4096, sizeofcmds > 0, sizeofcmds < 4 * 1024 * 1024 else { return nil }

        try? fh.seek(toOffset: 32)
        guard let body = try? fh.read(upToCount: sizeofcmds) else { return nil }

        var p = 0
        var i = 0
        while i < ncmds, p + 8 <= body.count {
            let cmd = body.leUInt32(p)
            let cmdsize = Int(body.leUInt32(p + 4))
            if cmdsize < 8 || p + cmdsize > body.count { break }

            /* LC_SEGMENT_64 = 0x19
               struct segment_command_64: cmd(4) cmdsize(4) segname(16) vmaddr(8)
                                          vmsize(8) fileoff(8) filesize(8) ... */
            if cmd == 0x19, cmdsize >= 72 {
                let nameBytes = body.subdata(in: (p + 8)..<(p + 24))
                let name = String(data: nameBytes, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""
                if name == "__TEXT" {
                    let fileoff = body.leUInt64(p + 40)
                    let filesize = body.leUInt64(p + 48)
                    if filesize > 0 { return Slice(offset: fileoff, size: filesize) }
                }
            }
            p += cmdsize
            i += 1
        }
        return nil
    }

    /// __TEXT 段的 SHA-256（小写 hex）
    static func textDigest(of path: String) -> String? {
        guard let s = textSlice(of: path), s.size <= 64 * 1024 * 1024 else { return nil }
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        try? fh.seek(toOffset: s.offset)

        var hasher = SHA256()
        var left = s.size
        while left > 0 {
            let want = Int(min(left, 256 * 1024))
            guard let chunk = try? fh.read(upToCount: want), !chunk.isEmpty else { return nil }
            hasher.update(data: chunk)
            left -= UInt64(chunk.count)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 当前主程序可执行文件路径
    static var mainExecutablePath: String? {
        if let p = Bundle.main.executablePath, !p.isEmpty { return p }
        return nil
    }
}

extension Data {
    func leUInt32(_ off: Int) -> UInt32 {
        guard off + 4 <= count else { return 0 }
        return withUnsafeBytes { raw -> UInt32 in
            let b = raw.bindMemory(to: UInt8.self)
            return UInt32(b[off]) | (UInt32(b[off + 1]) << 8)
                 | (UInt32(b[off + 2]) << 16) | (UInt32(b[off + 3]) << 24)
        }
    }

    func leUInt64(_ off: Int) -> UInt64 {
        guard off + 8 <= count else { return 0 }
        return withUnsafeBytes { raw -> UInt64 in
            let b = raw.bindMemory(to: UInt8.self)
            var v: UInt64 = 0
            var i = 7
            while i >= 0 { v = (v << 8) | UInt64(b[off + i]); i -= 1 }
            return v
        }
    }
}
