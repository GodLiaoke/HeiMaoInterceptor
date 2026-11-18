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

        var payloadEnd = totalLength
        if let udp = udp, udp.length >= 8 {
            payloadEnd = min(totalLength, ihl + udp.length)
        }
        let payloadStart = min(payloadEnd, max(ihl + 8, tcp?.headerLength ?? (udp?.payloadOffset ?? ihl)))
        let payload = data.subdata(in: payloadStart..<max(payloadStart, payloadEnd))

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
    /// 与 ACE 3.0 的 sendTcpRst 对齐的固定字段：
    ///   总长 40、ID 0、DF、TTL 64、window 0、urgent 0
    ///   握手包（SYN，无 ACK）：seq = 0，ack = 对端 seq + 载荷 + 1，flags = 0x14（RST|ACK）
    ///   已建立的连接（带 ACK）：seq 取对端的 ACK（它期待的下一个序号），ack = 0，flags = 0x04
    ///     —— 只有这样才落在对方的接收窗口里，本机 TCP 栈才会当成 RST 处理，
    ///        否则会被当窗口外乱包丢掉，用户体感变成「卡住等超时」
    static func buildRST(for p: Parsed) -> Data? {
        guard let tcp = p.tcp else { return nil }

        var seqNum: UInt32 = 0
        var ackNum: UInt32 = 0
        var flags: UInt8 = 0x04                            // RST

        if tcp.flags & 0x10 != 0 {                         // 已建立连接
            seqNum = tcp.ack
        } else {
            var ack = tcp.seq &+ UInt32(tcp.payloadLength)
            if tcp.isSYN { ack = ack &+ 1 }
            if tcp.isFIN { ack = ack &+ 1 }
            ackNum = ack
            flags = 0x14                                   // RST | ACK
        }

        let srcIp = p.dstIP
        let dstIp = p.srcIP
        let srcPort = tcp.dstPort
        let dstPort = tcp.srcPort

        var o = [UInt8](repeating: 0, count: 40)
        o[0] = 0x45                                        // IPv4 / IHL 5
        o[2] = 0x00; o[3] = 40                             // 总长 40
        o[6] = 0x40                                        // DF
        o[8] = 64                                          // TTL 64（固定，不继承原包）
        o[9] = 6                                           // TCP
        putU32(&o, 12, srcIp)
        putU32(&o, 16, dstIp)
        putU16(&o, 10, ipChecksum(o, 0, 20))

        putU16(&o, 20, srcPort)
        putU16(&o, 22, dstPort)
        putU32(&o, 24, seqNum)
        putU32(&o, 28, ackNum)
        o[32] = 0x50                                       // data offset 5
        o[33] = flags
        putU16(&o, 34, 0)                                  // window 0
        putU16(&o, 36, 0)                                  // checksum 占位
        putU16(&o, 38, 0)                                  // urgent 0

        let csum = l4Checksum(src: srcIp, dst: dstIp, proto: 6, seg: Array(o[20..<40]))
        putU16(&o, 36, csum == 0 ? 0xFFFF : csum)
        return Data(o)
    }

    private static func putU16(_ b: inout [UInt8], _ off: Int, _ v: UInt16) {
        b[off] = UInt8(v >> 8)
        b[off + 1] = UInt8(v & 0xFF)
    }

    private static func putU32(_ b: inout [UInt8], _ off: Int, _ v: UInt32) {
        b[off] = UInt8((v >> 24) & 0xFF)
        b[off + 1] = UInt8((v >> 16) & 0xFF)
        b[off + 2] = UInt8((v >> 8) & 0xFF)
        b[off + 3] = UInt8(v & 0xFF)
    }

    private static func ipChecksum(_ b: [UInt8], _ off: Int, _ len: Int) -> UInt16 {
        var sum: UInt32 = 0
        var i = off
        let end = off + len
        while i + 1 < end {
            sum += (UInt32(b[i]) << 8) | UInt32(b[i + 1])
            i += 2
        }
        if i < end { sum += UInt32(b[i]) << 8 }
        while (sum >> 16) != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16((~sum) & 0xFFFF)
    }

    private static func l4Checksum(src: UInt32, dst: UInt32, proto: UInt8, seg: [UInt8]) -> UInt16 {
        var buf: [UInt8] = []
        buf.append(contentsOf: [UInt8((src >> 24) & 0xFF), UInt8((src >> 16) & 0xFF),
                                UInt8((src >> 8) & 0xFF), UInt8(src & 0xFF)])
        buf.append(contentsOf: [UInt8((dst >> 24) & 0xFF), UInt8((dst >> 16) & 0xFF),
                                UInt8((dst >> 8) & 0xFF), UInt8(dst & 0xFF)])
        buf.append(0)
        buf.append(proto)
        buf.append(UInt8((seg.count >> 8) & 0xFF))
        buf.append(UInt8(seg.count & 0xFF))
        buf.append(contentsOf: seg)
        if buf.count % 2 == 1 { buf.append(0) }
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < buf.count {
            sum += (UInt32(buf[i]) << 8) | UInt32(buf[i + 1])
            i += 2
        }
        while (sum >> 16) != 0 { sum = (sum & 0xFFFF) + (sum >> 16) }
        return UInt16((~sum) & 0xFFFF)
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
