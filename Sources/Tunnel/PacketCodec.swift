import Foundation

/// IPv4 / TCP / UDP 报文解析与构造（用户态最小协议栈）
enum PacketCodec {

    struct TCPInfo {
        let srcPort: UInt16
        let dstPort: UInt16
        let seq: UInt32
        let ack: UInt32
        let flags: UInt8
        let headerLength: Int
        let totalLength: Int

        var isSYN: Bool { flags & 0x02 != 0 }
        var isFIN: Bool { flags & 0x01 != 0 }
        var payloadLength: Int { max(0, totalLength - headerLength) }
    }

    struct UDPInfo {
        let srcPort: UInt16
        let dstPort: UInt16
        let length: Int        // UDP 头 + 负载
        let payloadOffset: Int
    }

    struct Parsed {
        let srcIP: UInt32
        let dstIP: UInt32
        let proto: UInt8
        let ttl: UInt8
        let totalLength: Int
        let ipHeaderLength: Int
        let tcp: TCPInfo?
        let udp: UDPInfo?
        let payload: Data
        let raw: Data
    }

    // MARK: - 解析

    static func parse(_ data: Data) -> Parsed? {
        guard data.count >= 20 else { return nil }
        let bytes = [UInt8](data)
        let version = bytes[0] >> 4
        guard version == 4 else { return nil }
        let ihl = Int(bytes[0] & 0x0F) * 4
        guard ihl >= 20, bytes.count >= ihl else { return nil }
        let totalLength = Int(bytes[2]) << 8 | Int(bytes[3])
        guard totalLength >= ihl, bytes.count >= totalLength else { return nil }

        let srcIP = bytes[12..<16].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let dstIP = bytes[16..<20].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let proto = bytes[9]
        let ttl = bytes[8]

        var tcp: TCPInfo?
        var udp: UDPInfo?

        if proto == 6, bytes.count >= ihl + 20 {
            let sp = UInt16(bytes[ihl]) << 8 | UInt16(bytes[ihl + 1])
            let dp = UInt16(bytes[ihl + 2]) << 8 | UInt16(bytes[ihl + 3])
            let seq = be32(bytes, ihl + 4)
            let ack = be32(bytes, ihl + 8)
            let off = Int(bytes[ihl + 12] >> 4) * 4
            let flags = bytes[ihl + 13]
            tcp = TCPInfo(srcPort: sp, dstPort: dp, seq: seq, ack: ack,
                          flags: flags, headerLength: ihl + off, totalLength: totalLength)
        } else if proto == 17, bytes.count >= ihl + 8 {
            let sp = UInt16(bytes[ihl]) << 8 | UInt16(bytes[ihl + 1])
            let dp = UInt16(bytes[ihl + 2]) << 8 | UInt16(bytes[ihl + 3])
            let len = Int(bytes[ihl + 4]) << 8 | Int(bytes[ihl + 5])
            udp = UDPInfo(srcPort: sp, dstPort: dp, length: len, payloadOffset: ihl + 8)
        }

        let payloadStart = min(totalLength, max(ihl + 8, tcp?.headerLength ?? (udp?.payloadOffset ?? ihl)))
        let payload = data.subdata(in: payloadStart..<totalLength)

        return Parsed(srcIP: srcIP, dstIP: dstIP, proto: proto, ttl: ttl,
                      totalLength: totalLength, ipHeaderLength: ihl,
                      tcp: tcp, udp: udp, payload: payload, raw: data)
    }

    private static func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
        (UInt32(b[o]) << 24) | (UInt32(b[o + 1]) << 16) | (UInt32(b[o + 2]) << 8) | UInt32(b[o + 3])
    }

    // MARK: - 构造

    /// 伪造 TCP RST：让本机连接立即失败（不发也不收任何真实流量）
    ///
    /// 序列号按 RFC 793 3.4 分两种情况，之前一律用 seq=0 是错的：
    ///   - 握手包（SYN，不带 ACK）：RST 的 SEQ=0，ACK = 对端 SEQ + 1，置 ACK 位
    ///   - 已建立的连接（带 ACK）：RST 的 SEQ 必须取对端的 ACK（它期待的下一个序号），
    ///     ACK 字段清零，不置 ACK 位 —— 否则本机 TCP 栈会认为这是窗口外的乱包直接丢掉，
    ///     用户体感就变成「卡住等超时」而不是「秒失败」
    static func buildRST(for p: Parsed) -> Data? {
        guard let tcp = p.tcp else { return nil }

        var seqNum: UInt32 = 0
        var ackNum: UInt32 = 0
        var flags: UInt8 = 0x04                            // RST

        if tcp.flags & 0x10 != 0 {                         // 已建立连接
            seqNum = tcp.ack
        } else {
            var ack = tcp.seq + UInt32(tcp.payloadLength)
            if tcp.isSYN { ack &+= 1 }
            if tcp.isFIN { ack &+= 1 }
            ackNum = ack
            flags = 0x14                                   // RST | ACK
        }

        var out = Data()
        out.append(contentsOf: buildIPHeader(src: p.dstIP, dst: p.srcIP, proto: 6,
                                             payloadLength: 20, ttl: 64))
        // TCP 头
        var t = Data()
        t.append(be16(tcp.dstPort))                        // 源端口 = 原目的端口
        t.append(be16(tcp.srcPort))                        // 目的端口 = 原源端口
        t.append(be32bytes(seqNum))
        t.append(be32bytes(ackNum))
        t.append(contentsOf: [0x50, flags])                // dataOffset 5
        t.append(be16(0))                                  // window
        t.append(be16(0))                                  // checksum 占位
        t.append(be16(0))                                  // urgent
        let csum = tcpChecksum(src: p.dstIP, dst: p.srcIP, tcp: t)
        t.replaceSubrange(16..<18, with: be16(csum))
        out.append(t)
        return out
    }

    /// 连接标识：同一个五元组只回一次 RST
    static func flowKey(_ p: Parsed) -> UInt64 {
        let sp = UInt64(p.tcp?.srcPort ?? p.udp?.srcPort ?? 0)
        let dp = UInt64(p.tcp?.dstPort ?? p.udp?.dstPort ?? 0)
        return (UInt64(p.srcIP) << 32) ^ (UInt64(p.dstIP) << 16) ^ (sp << 8) ^ dp
    }

    static func buildIPHeader(src: UInt32, dst: UInt32, proto: UInt8,
                              payloadLength: Int, ttl: UInt8 = 64,
                              identification: UInt16 = UInt16.random(in: 1...60000)) -> Data {
        var h = Data()
        let total = UInt16(20 + payloadLength)
        h.append(0x45)                                     // v4, ihl 5
        h.append(0x00)                                     // tos (尽力而为)
        h.append(be16(total))
        h.append(be16(identification))
        h.append(contentsOf: [0x40, 0x00])                 // DF
        h.append(ttl)
        h.append(proto)
        h.append(be16(0))                                  // checksum 占位
        h.append(be32bytes(src))
        h.append(be32bytes(dst))
        let csum = ipChecksum(h)
        h.replaceSubrange(10..<12, with: be16(csum))
        return h
    }

    /// 构造 UDP 报文（用于回写 DNS 响应）
    static func buildUDP(src: UInt32, dst: UInt32,
                         srcPort: UInt16, dstPort: UInt16, payload: Data) -> Data {
        var udp = Data()
        udp.append(be16(srcPort))
        udp.append(be16(dstPort))
        udp.append(be16(UInt16(8 + payload.count)))
        udp.append(be16(0))
        udp.append(payload)
        let csum = udpChecksum(src: src, dst: dst, udp: udp)
        udp.replaceSubrange(6..<8, with: be16(csum == 0 ? 0xFFFF : csum))

        var out = buildIPHeader(src: src, dst: dst, proto: 17,
                                payloadLength: udp.count, ttl: 64)
        out.append(udp)
        return out
    }

    // MARK: - 校验和

    static func ipChecksum(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        let bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16(~sum & 0xFFFF)
    }

    static func tcpChecksum(src: UInt32, dst: UInt32, tcp: Data) -> UInt16 {
        var pseudo = Data()
        pseudo.append(be32bytes(src))
        pseudo.append(be32bytes(dst))
        pseudo.append(0)
        pseudo.append(6)
        pseudo.append(be16(UInt16(tcp.count)))
        pseudo.append(tcp)
        return onesComplement(pseudo)
    }

    static func udpChecksum(src: UInt32, dst: UInt32, udp: Data) -> UInt16 {
        var pseudo = Data()
        pseudo.append(be32bytes(src))
        pseudo.append(be32bytes(dst))
        pseudo.append(0)
        pseudo.append(17)
        pseudo.append(be16(UInt16(udp.count)))
        pseudo.append(udp)
        return onesComplement(pseudo)
    }

    private static func onesComplement(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        let bytes = [UInt8](data)
        var i = 0
        while i + 1 < bytes.count {
            sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
            i += 2
        }
        if i < bytes.count { sum += UInt32(bytes[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16(~sum & 0xFFFF)
    }

    // MARK: - 字节工具

    static func be16(_ v: UInt16) -> Data {
        Data([UInt8(v >> 8), UInt8(v & 0xFF)])
    }

    static func be32bytes(_ v: UInt32) -> Data {
        Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF),
              UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }

    static func ipString(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }

    static func ipValue(_ s: String) -> UInt32? {
        RuleSet.ipToUInt(s)
    }
}
