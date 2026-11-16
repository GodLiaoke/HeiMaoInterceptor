import Foundation
import NetworkExtension
import Darwin

/// 拦截内核：接管 DNS + 对命中规则的 IP 断链
/// 不转发任何业务流量，命中 TCP 直接回 RST，命中 UDP 直接丢包。
final class TunnelEngine {

    struct Stats {
        var blockedPackets = 0
        var blockedDomains = 0
        var blockedTCP = 0
        var blockedUDP = 0
        var passedDNS = 0
        var startedAt = Date()

        var json: [String: Any] {
            ["blocked": blockedPackets,
             "domains": blockedDomains,
             "tcp": blockedTCP,
             "udp": blockedUDP,
             "passed": passedDNS,
             "uptime": Int(Date().timeIntervalSince(startedAt))]
        }

        var text: String {
            "已拦截 \(blockedPackets) · 域名 \(blockedDomains) · TCP \(blockedTCP) · UDP \(blockedUDP) · 放行DNS \(passedDNS)"
        }
    }

    private let flow: NEPacketTunnelFlow
    private var rules: RuleSet
    private let dnsIPv4: UInt32
    private let clientIPv4: UInt32

    private let stateQueue = DispatchQueue(label: "com.heimao.engine.state")
    private let dnsQueue = DispatchQueue(label: "com.heimao.engine.dns", attributes: .concurrent)
    private var running = false
    private(set) var stats = Stats()

    /// 外部（provider）读取统计
    func snapshot() -> [String: Any] {
        stateQueue.sync { stats.json }
    }

    init(flow: NEPacketTunnelFlow, rules: RuleSet, dnsIP: String, clientIP: String) {
        self.flow = flow
        self.rules = rules
        self.dnsIPv4 = RuleSet.ipToUInt(dnsIP) ?? 0x0A6F0001
        self.clientIPv4 = RuleSet.ipToUInt(clientIP) ?? 0x0A6F0002
    }

    func update(rules: RuleSet) {
        stateQueue.async { self.rules = rules }
    }

    // MARK: - 主循环

    func start() {
        stateQueue.async { self.stats = Stats() }
        running = true
        readLoop()
    }

    func stop() {
        running = false
    }

    private func readLoop() {
        guard running else { return }
        flow.readPackets { [weak self] packets, _ in
            guard let self = self, self.running else { return }
            for pkt in packets {
                self.handle(pkt)
            }
            self.readLoop()
        }
    }

    // MARK: - 单包处理

    private func handle(_ data: Data) {
        guard let p = PacketCodec.parse(data) else { return }

        if p.proto == 17, let udp = p.udp {
            // DNS 走代理地址
            if p.dstIP == dnsIPv4 && udp.dstPort == 53 {
                handleDNS(p)
                return
            }
            if isBlocked(p.dstIP) {
                stateQueue.async {
                    self.stats.blockedPackets += 1
                    self.stats.blockedUDP += 1
                }
                return          // UDP 直接丢
            }
            return
        }

        if p.proto == 6, p.tcp != nil {
            if isBlocked(p.dstIP) {
                if let rst = PacketCodec.buildRST(for: p) {
                    write([rst])
                }
                stateQueue.async {
                    self.stats.blockedPackets += 1
                    self.stats.blockedTCP += 1
                }
            }
            return              // 业务 TCP 永不转发
        }
    }

    private func isBlocked(_ ip: UInt32) -> Bool {
        stateQueue.sync { rules.isIPBlocked(ip) }
    }

    // MARK: - DNS

    private func handleDNS(_ p: PacketCodec.Parsed) {
        guard let udp = p.udp else { return }
        let payload = p.payload
        guard let query = DNSMessage.parseQuery(payload) else {
            forwardDNS(payload, from: p, udp: udp)
            return
        }

        let blocked = stateQueue.sync { rules.isDomainBlocked(query.qname) }
        if blocked {
            let answer = DNSMessage.buildSinkhole(for: query)
            let out = PacketCodec.buildUDP(src: dnsIPv4, dst: p.srcIP,
                                           srcPort: udp.dstPort, dstPort: udp.srcPort,
                                           payload: answer)
            write([out])
            stateQueue.async {
                self.stats.blockedPackets += 1
                self.stats.blockedDomains += 1
            }
        } else {
            forwardDNS(payload, from: p, udp: udp)
        }
    }

    private func forwardDNS(_ payload: Data, from p: PacketCodec.Parsed, udp: PacketCodec.UDPInfo) {
        stateQueue.async { self.stats.passedDNS += 1 }
        dnsQueue.async { [weak self] in
            guard let self = self else { return }
            guard let response = DNSUpstream.query(payload) else { return }
            let out = PacketCodec.buildUDP(src: self.dnsIPv4, dst: p.srcIP,
                                           srcPort: udp.dstPort, dstPort: udp.srcPort,
                                           payload: response)
            self.write([out])
        }
    }

    private func write(_ packets: [Data]) {
        guard !packets.isEmpty else { return }
        let protos = packets.map { _ in NSNumber(value: AF_INET) }
        flow.writePackets(packets, withProtocols: protos)
    }
}

/// 上游 DNS 转发（UDP + 2.5s 超时，逐个服务器回退）
enum DNSUpstream {

    static func query(_ payload: Data, timeout: Int32 = 2500) -> Data? {
        for server in AppConfig.upstreamDNS {
            if let r = send(payload, to: server, timeout: timeout) {
                return r
            }
        }
        return nil
    }

    private static func send(_ payload: Data, to host: String, timeout: Int32) -> Data? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(53).bigEndian
        var ip = in_addr()
        guard inet_pton(AF_INET, host, &ip) == 1 else { return nil }
        addr.sin_addr = ip

        let sent = withUnsafePointer(to: &addr) { ptr -> Int in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                payload.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int in
                    guard let base = buf.baseAddress else { return -1 }
                    return Int(sendto(fd, base, buf.count, 0, sa,
                                      socklen_t(MemoryLayout<sockaddr_in>.size)))
                }
            }
        }
        guard sent > 0 else { return nil }

        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, timeout) > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Int(recv(fd, base, raw.count, 0))
        }
        guard n > 0 else { return nil }
        return Data(buf[0..<n])
    }
}
