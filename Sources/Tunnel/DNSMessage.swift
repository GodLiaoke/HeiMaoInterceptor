import Foundation

/// 最小 DNS 处理：解析 QNAME、构造黑洞响应
///
/// 与 ACE 3.0 的 Dh.buildSinkhole 逐字节对齐：
///   - A 查询：答一条 `C0 0C 00 01 00 01 00 00 00 3C 00 04 00 00 00 00`
///     （名字压缩指针 → TYPE A / CLASS IN / TTL 60 / RDLENGTH 4 / 0.0.0.0）
///   - 非 A 查询（AAAA / HTTPS / SVCB …）：ANCOUNT = 0 的 NODATA，不放任何地址
///     —— 放真实 AAAA 会被客户端拿去直连，域名规则就绕过了
enum DNSMessage {

    struct Query {
        let id: UInt16
        let flags: UInt16
        let qname: String
        let qtype: UInt16
        let qclass: UInt16
        let questionEnd: Int     // question 区结束偏移（qEnd）
        let raw: Data
    }

    /// 解析查询报文（支持压缩指针，长度上限 255）
    static func parseQuery(_ data: Data) -> Query? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data)
        let id = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let flags = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let qdcount = Int(bytes[4]) << 8 | Int(bytes[5])
        guard qdcount >= 1 else { return nil }

        guard let (name, end) = readQName(bytes, 12) else { return nil }
        guard end + 4 <= bytes.count else { return nil }
        let qtype = UInt16(bytes[end]) << 8 | UInt16(bytes[end + 1])
        let qclass = UInt16(bytes[end + 2]) << 8 | UInt16(bytes[end + 3])
        let qEnd = end + 4

        return Query(id: id, flags: flags, qname: name, qtype: qtype,
                     qclass: qclass, questionEnd: qEnd, raw: data)
    }

    /// 从 DNS 载荷里读 QNAME，返回（名字，名字结束偏移）
    static func readQName(_ p: [UInt8], _ start: Int) -> (String, Int)? {
        var labels: [String] = []
        var i = start
        var end = -1
        var jumps = 0
        var total = 0

        while i < p.count {
            let len = Int(p[i])
            if len == 0 {
                i += 1
                if end < 0 { end = i }
                break
            }
            if len & 0xC0 == 0xC0 {
                guard i + 1 < p.count, jumps < 16 else { return nil }
                let ptr = ((len & 0x3F) << 8) | Int(p[i + 1])
                if end < 0 { end = i + 2 }
                guard ptr >= 0, ptr < p.count else { return nil }
                i = ptr
                jumps += 1
                continue
            }
            guard i + 1 + len <= p.count else { return nil }
            total += len + 1
            guard total <= 255 else { return nil }
            labels.append(String(decoding: p[(i + 1)..<(i + 1 + len)], as: UTF8.self))
            i += 1 + len
        }

        guard end > 0 else { return nil }
        return (labels.joined(separator: "."), end)
    }

    /// 构造黑洞响应（A → 0.0.0.0，TTL 60；非 A → NODATA）
    static func buildSinkhole(for q: Query) -> Data {
        let wantsA = (q.qtype == 1)
        var out = Data()
        out.reserveCapacity(q.questionEnd + 16)

        // ID 原样
        out.append(be16(q.id))
        // QR = 1，保留 RD（与原版同样只保 RD 一位）
        let rdBit = UInt8((q.flags >> 8) & 0x01)
        out.append(rdBit | 0x80)
        // RA = 1，其余 0
        out.append(0x80)

        out.append(be16(1))                    // QDCOUNT
        out.append(be16(wantsA ? 1 : 0))       // ANCOUNT
        out.append(be16(0))                    // NSCOUNT
        out.append(be16(0))                    // ARCOUNT

        let raw = [UInt8](q.raw)
        if q.questionEnd > 12, q.questionEnd <= raw.count {
            out.append(contentsOf: raw[12..<q.questionEnd])
        }

        if wantsA {
            out.append(contentsOf: [0xC0, 0x0C,        // 名字压缩指针 → 偏移 12
                                    0x00, 0x01,        // TYPE A
                                    0x00, 0x01,        // CLASS IN
                                    0x00, 0x00, 0x00, 0x3C,   // TTL 60
                                    0x00, 0x04,        // RDLENGTH 4
                                    0x00, 0x00, 0x00, 0x00])   // 0.0.0.0
        }
        return out
    }

    static func be16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }

    static func be32bytes(_ v: UInt32) -> Data {
        Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
              UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
}
