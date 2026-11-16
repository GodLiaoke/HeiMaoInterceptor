import Foundation

/// 最小 DNS 处理：解析 QNAME、构造黑洞响应（A=0.0.0.0 / AAAA=::）
enum DNSMessage {

    struct Query {
        let id: UInt16
        let flags: UInt16
        let qname: String
        let qtype: UInt16
        let qclass: UInt16
        let questionEnd: Int     // question 区结束偏移
        let raw: Data
    }

    /// 解析查询报文
    static func parseQuery(_ data: Data) -> Query? {
        guard data.count >= 12 else { return nil }
        let bytes = [UInt8](data)
        let id = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        let flags = UInt16(bytes[2]) << 8 | UInt16(bytes[3])
        let qdcount = Int(bytes[4]) << 8 | Int(bytes[5])
        guard qdcount >= 1 else { return nil }

        var offset = 12
        var labels: [String] = []
        while offset < bytes.count {
            let len = Int(bytes[offset])
            if len == 0 { offset += 1; break }
            if len & 0xC0 == 0xC0 {
                // 压缩指针，客户端查询里极少出现，放弃解析
                return nil
            }
            guard offset + 1 + len <= bytes.count else { return nil }
            let label = String(decoding: bytes[(offset + 1)..<(offset + 1 + len)], as: UTF8.self)
            labels.append(label)
            offset += 1 + len
            if labels.count > 32 { return nil }
        }
        guard offset + 4 <= bytes.count else { return nil }
        let qtype = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
        let qclass = UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3])
        offset += 4

        let name = labels.joined(separator: ".")
        return Query(id: id, flags: flags, qname: name, qtype: qtype,
                     qclass: qclass, questionEnd: offset, raw: data)
    }

    /// 构造黑洞响应：域名解析到 0.0.0.0 / :: ，TTL 60
    static func buildSinkhole(for q: Query) -> Data {
        var out = Data()
        var flags: UInt16 = 0x8000            // QR = 1
        flags |= (q.flags & 0x0100)           // 复制 RD
        flags |= 0x0400                       // AA
        flags |= 0x0080                       // RA
        // RCODE = 0（NOERROR），返回一个 0.0.0.0 的 A 记录让客户端立刻失败

        out.append(be16(q.id))
        out.append(be16(flags))
        out.append(be16(1))                   // QDCOUNT
        out.append(be16(isIPv6(q.qtype) ? 0 : 1))  // ANCOUNT
        out.append(be16(0))                   // NSCOUNT
        out.append(be16(0))                   // ARCOUNT

        // Question 原样拷贝
        if q.questionEnd <= q.raw.count {
            out.append(q.raw.subdata(in: 12..<q.questionEnd))
        }

        if !isIPv6(q.qtype) {
            out.append(contentsOf: [0xC0, 0x0C])       // 指向 question 的 NAME
            out.append(be16(1))                        // TYPE A
            out.append(be16(1))                        // CLASS IN
            out.append(be32bytes(60))                  // TTL
            out.append(be16(4))                        // RDLENGTH
            out.append(contentsOf: [0, 0, 0, 0])       // 0.0.0.0
        }
        return out
    }

    /// AAAA 查询返回空答案（NOERROR + 0 记录），避免客户端回退到真实 IPv6
    static func isIPv6(_ qtype: UInt16) -> Bool { qtype == 28 }

    static func be16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }

    static func be32bytes(_ v: UInt32) -> Data {
        Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
              UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
}
