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

    /// 构造黑洞响应：域名解析到指定的黑洞地址（默认由调用方给隧道内地址），TTL 60
    ///
    /// 返回隧道内的 sinkhole 地址（而不是 0.0.0.0）有两个好处：
    ///   1. 连接会真的进隧道，被我们当场断掉，用户立刻看到失败，不用等系统超时
    ///   2. 断掉的动作能被统计到，界面上的「HTTPS 拦断」才是真实数字
    static func buildSinkhole(for q: Query, ip: UInt32) -> Data {
        /* 只有 A 查询才回一条黑洞 A 记录。
           AAAA / HTTPS(SVCB) 一律回空答案：
             - AAAA 回真实记录，客户端会直接走 IPv6 连过去，整条拦截就绕过了
             - HTTPS(65) / SVCB(64) 记录里带 ipv4hint / ipv6hint，
               Safari、Chrome 会拿 hint 直接连，同样绕过 DNS 层
           回「NOERROR + 0 条记录」既不报错、也不给任何可连的地址，
           客户端只能回退到 A 记录，也就是我们给的黑洞地址。 */
        let wantsA = (q.qtype == 1 || q.qtype == 255)
        var out = Data()
        var flags: UInt16 = 0x8000            // QR = 1
        flags |= (q.flags & 0x0100)           // 复制 RD
        flags |= 0x0400                       // AA
        flags |= 0x0080                       // RA
        // RCODE = 0（NOERROR）

        out.append(be16(q.id))
        out.append(be16(flags))
        out.append(be16(1))                   // QDCOUNT
        out.append(be16(wantsA ? 1 : 0))       // ANCOUNT
        out.append(be16(0))                   // NSCOUNT
        out.append(be16(0))                   // ARCOUNT

        // Question 原样拷贝
        if q.questionEnd <= q.raw.count {
            out.append(q.raw.subdata(in: 12..<q.questionEnd))
        }

        if wantsA {
            out.append(contentsOf: [0xC0, 0x0C])       // 指向 question 的 NAME
            out.append(be16(1))                        // TYPE A
            out.append(be16(1))                        // CLASS IN
            out.append(be32bytes(30))                  // TTL 30s：后台改规则能较快生效
            out.append(be16(4))                        // RDLENGTH
            out.append(be32bytes(ip))                  // 黑洞地址
        }
        return out
    }


    static func be16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }

    static func be32bytes(_ v: UInt32) -> Data {
        Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
              UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
}
