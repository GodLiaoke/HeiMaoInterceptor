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
        var blockedConn = 0
        var passedDNS = 0
        var cacheHits = 0
        /// 进隧道的包总数：这个数是 0 就说明系统的流量压根没进隧道
        var tunnelPackets = 0
        /// 收到的 DNS 查询数（含转发和黑洞）
        var dnsQueries = 0
        /// 不该进隧道的包（路由补集没生效时会冒出来）
        var stray = 0
        var startedAt = Date()

        var json: [String: Any] {
            ["blocked": blockedPackets,
             "domains": blockedDomains,
             "tcp": blockedTCP,
             "udp": blockedUDP,
             "conn": blockedConn,
             "passed": passedDNS,
             "cache": cacheHits,
             "tunnel": tunnelPackets,
             "dns": dnsQueries,
             "stray": stray,
             "uptime": Int(Date().timeIntervalSince(startedAt))]
        }

        var text: String {
            "已拦截 \(blockedPackets) · 域名 \(blockedDomains) · TCP \(blockedTCP) · UDP \(blockedUDP) · 放行DNS \(passedDNS)"
        }
    }

    private struct CacheEntry {
        let response: Data
        let expireAt: TimeInterval
    }

    private let flow: NEPacketTunnelFlow
    private let dnsIPv4: UInt32
    private let clientIPv4: UInt32
    /// 域名黑洞地址：命中的域名都解析到这里，连接一进来就断
    private let sinkholeIPv4: UInt32

    /// 规则快照 + DNS 缓存共用一把锁。都是纳秒级操作，不排队、不切线程，
    /// 比每包一次 DispatchQueue.sync 快一个数量级。
    private let stateLock = NSLock()
    private var rules: RuleSet
    private var dnsCache: [String: CacheEntry] = [:]
    private var dnsCacheKeys: [String] = []
    private let dnsCacheLimit = 1024

    /// 同一条连接只回一次 RST，避免重传包把 RST 风暴打回给内核
    private var rstSeen: [UInt64: TimeInterval] = [:]

    private let statsLock = NSLock()
    private var stats = Stats()

    private let dnsQueue = DispatchQueue(label: "com.heimao.engine.dns", attributes: .concurrent)
    /// 同时最多 8 个上游查询，避免一轮网页加载把线程打爆
    private let dnsSlots = DispatchSemaphore(value: 8)

    private var running = false
    private let runningLock = NSLock()

    /// 外部（provider）读取统计
    func snapshot() -> [String: Any] {
        statsLock.lock(); defer { statsLock.unlock() }
        return stats.json
    }

    init(flow: NEPacketTunnelFlow, rules: RuleSet,
         dnsIP: String, clientIP: String, sinkholeIP: String) {
        self.flow = flow
        self.rules = rules
        self.dnsIPv4 = RuleSet.ipToUInt(dnsIP) ?? 0x0A6F0001
        self.clientIPv4 = RuleSet.ipToUInt(clientIP) ?? 0x0A6F0002
        self.sinkholeIPv4 = RuleSet.ipToUInt(sinkholeIP) ?? 0x0A6F0009
    }

    /// 规则热更新：必须连 DNS 缓存一起清掉。
    /// 否则某个域名从「放行」改成「拦截」后，缓存里还留着旧的真实 IP，
    /// 客户端拿到缓存直接连过去，拦截就漏了。
    func update(rules: RuleSet) {
        stateLock.lock()
        self.rules = rules
        dnsCache.removeAll(keepingCapacity: true)
        dnsCacheKeys.removeAll(keepingCapacity: true)
        rstSeen.removeAll(keepingCapacity: true)
        stateLock.unlock()
    }

    // MARK: - 主循环

    func start() {
        statsLock.lock(); stats = Stats(); statsLock.unlock()
        runningLock.lock(); running = true; runningLock.unlock()
        readLoop()
    }

    func stop() {
        runningLock.lock(); running = false; runningLock.unlock()
    }

    private var isRunning: Bool {
        runningLock.lock(); defer { runningLock.unlock() }
        return running
    }

    private func readLoop() {
        guard isRunning else { return }
        flow.readPackets { [weak self] packets, _ in
            guard let self = self, self.isRunning else { return }
            for pkt in packets {
                self.handle(pkt)
            }
            self.readLoop()
        }
    }

    // MARK: - 单包处理

    private func handle(_ data: Data) {
        guard let p = PacketCodec.parse(data) else { return }
        statsLock.lock(); stats.tunnelPackets += 1; statsLock.unlock()

        /* 域名黑洞：命中的域名解析到 sinkhole 地址，连接进来一律断掉。
           HTTPS / QUIC 都在这里断，所以不需要解密 TLS，也不需要装证书。 */
        if p.dstIP == sinkholeIPv4 {
            if p.proto == 6, p.tcp != nil {
                dropTCP(p, key: PacketCodec.flowKey(p))
            } else if p.proto == 17 {
                statsLock.lock()
                stats.blockedPackets += 1
                stats.blockedConn += 1
                stats.blockedUDP += 1
                statsLock.unlock()
            }
            return
        }

        if p.proto == 17, let udp = p.udp {
            /* 只要是 53 端口的 UDP 就当 DNS 处理，不挑目标地址。
               系统在隧道里可能仍按旧的 DNS 服务器发查询（换网 / 缓存 / DoH 回退），
               只认 dnsIPv4 会把这些查询漏掉 —— 那正是「DNS 没接管」的典型表现。 */
            if udp.dstPort == 53 {
                statsLock.lock(); stats.dnsQueries += 1; statsLock.unlock()
                handleDNS(p)
                return
            }
            if isBlocked(p.dstIP, port: udp.dstPort) {
                statsLock.lock()
                stats.blockedPackets += 1
                stats.blockedUDP += 1
                statsLock.unlock()
                return          // UDP 直接丢
            }
            statsLock.lock(); stats.stray += 1; statsLock.unlock()
            return
        }

        if p.proto == 6, let tcp = p.tcp {
            if isBlocked(p.dstIP, port: tcp.dstPort) {
                dropTCP(p, key: PacketCodec.flowKey(p))
            } else {
                /* 非规则流量正常应该在隧道外（excludedRoutes）。这里收到说明
                   路由补集没生效，记数用于判断，不在这里断用户的路。 */
                statsLock.lock(); stats.stray += 1; statsLock.unlock()
            }
            return
        }
    }

    /// 断一条 TCP 连接
    ///
    /// 只有 SYN 或者这条连接的第一个包才回 RST：客户端重传时会连发好几个包，
    /// 每个都回 RST 会把统计打爆、也给内核制造无谓压力。
    private func dropTCP(_ p: PacketCodec.Parsed, key: UInt64) {
        var send = false
        let now = Date().timeIntervalSince1970

        stateLock.lock()
        if let last = rstSeen[key], now - last < 2.0 {
            send = false
        } else {
            rstSeen[key] = now
            send = true
            if rstSeen.count > 4096 {
                rstSeen = rstSeen.filter { now - $0.value < 10 }
            }
        }
        stateLock.unlock()

        statsLock.lock()
        stats.blockedPackets += 1
        stats.blockedTCP += 1
        if send { stats.blockedConn += 1 }
        statsLock.unlock()

        guard send else { return }
        if let rst = PacketCodec.buildRST(for: p) {
            write([rst])
        }
    }

    /// IP + 端口一起判定（一次加锁，避免每个包锁两次）
    ///
    /// 端口规则的语义：
    ///   - 规则库里有 IP 时，命中 IP 就拦，端口只是附加信息，不额外限制；
    ///   - 规则库只有端口（纯端口黑名单）时，按目标端口拦。
    private func isBlocked(_ ip: UInt32, port: UInt16) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return rules.shouldBlock(ip: ip, port: port)
    }

    private func isDomainBlocked(_ domain: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return rules.isDomainBlocked(domain)
    }

    // MARK: - DNS 缓存

    private static func cacheKey(_ qname: String, _ qtype: UInt16) -> String {
        "\(qname.lowercased())|\(qtype)"
    }

    private func cachedResponse(key: String, id: UInt16) -> Data? {
        stateLock.lock()
        guard let entry = dnsCache[key], entry.expireAt > Date().timeIntervalSince1970 else {
            if dnsCache[key] != nil { dnsCache.removeValue(forKey: key) }
            stateLock.unlock()
            return nil
        }
        stateLock.unlock()

        // 缓存里存的是上一次的应答，DNS 事务 ID 必须改成本次查询的，否则客户端会丢弃
        var out = entry.response
        if out.count >= 2 {
            out[0] = UInt8((id >> 8) & 0xFF)
            out[1] = UInt8(id & 0xFF)
        }
        statsLock.lock(); stats.cacheHits += 1; statsLock.unlock()
        return out
    }

    private func storeCache(key: String, response: Data, blocked: Bool) {
        guard response.count >= 12 else { return }
        // 拦截应答短一些（域名状态可能被后台改动），放行应答长一些
        let ttl: TimeInterval = blocked ? 30 : 90
        stateLock.lock()
        if dnsCache[key] == nil {
            dnsCacheKeys.append(key)
        }
        dnsCache[key] = CacheEntry(response: response, expireAt: Date().timeIntervalSince1970 + ttl)
        if dnsCacheKeys.count > dnsCacheLimit {
            let drop = dnsCacheKeys.prefix(256)
            for k in drop { dnsCache.removeValue(forKey: k) }
            dnsCacheKeys.removeFirst(min(256, dnsCacheKeys.count))
        }
        stateLock.unlock()
    }

    // MARK: - DNS

    private func handleDNS(_ p: PacketCodec.Parsed) {
        guard let udp = p.udp else { return }
        let payload = p.payload
        guard let query = DNSMessage.parseQuery(payload) else {
            forwardDNS(payload, from: p, udp: udp, cacheKey: nil)
            return
        }

        let key = TunnelEngine.cacheKey(query.qname, query.qtype)

        if let cached = cachedResponse(key: key, id: query.id) {
            let out = PacketCodec.buildUDP(src: p.dstIP, dst: p.srcIP,
                                           srcPort: udp.dstPort, dstPort: udp.srcPort,
                                           payload: cached)
            write([out])
            return
        }

        let blocked = isDomainBlocked(query.qname)
        if blocked {
            let answer = DNSMessage.buildSinkhole(for: query, ip: sinkholeIPv4)
            storeCache(key: key, response: answer, blocked: true)
            let out = PacketCodec.buildUDP(src: p.dstIP, dst: p.srcIP,
                                           srcPort: udp.dstPort, dstPort: udp.srcPort,
                                           payload: answer)
            write([out])
            statsLock.lock()
            stats.blockedPackets += 1
            stats.blockedDomains += 1
            statsLock.unlock()
        } else {
            forwardDNS(payload, from: p, udp: udp, cacheKey: key)
        }
    }

    private func forwardDNS(_ payload: Data, from p: PacketCodec.Parsed,
                            udp: PacketCodec.UDPInfo, cacheKey: String?) {
        statsLock.lock(); stats.passedDNS += 1; statsLock.unlock()
        dnsQueue.async { [weak self] in
            guard let self = self else { return }
            self.dnsSlots.wait()
            defer { self.dnsSlots.signal() }

            guard let response = DNSUpstream.query(payload) else { return }
            if let key = cacheKey {
                self.storeCache(key: key, response: response, blocked: false)
            }
            let out = PacketCodec.buildUDP(src: p.dstIP, dst: p.srcIP,
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

/// 上游 DNS 转发
///
/// 之前的实现每个查询新建 socket、串行回退、超时 2.5s，一次网页加载几十个域名
/// 时首屏会明显变慢。现在：
///   - socket 用 connect 绑定上游，只收这一家的回包（不会被串话 / 投毒干扰）
///   - 校验事务 ID 与请求一致
///   - 单个上游 900ms 超时，失败立刻换下一个
enum DNSUpstream {

    static func query(_ payload: Data, timeout: Int32 = 900) -> Data? {
        guard payload.count >= 2 else { return nil }
        let wantID = UInt16(payload[0]) << 8 | UInt16(payload[1])
        for server in AppConfig.upstreamDNS {
            if let r = send(payload, to: server, timeout: timeout, wantID: wantID) {
                return r
            }
        }
        return nil
    }

    private static func send(_ payload: Data, to host: String,
                             timeout: Int32, wantID: UInt16) -> Data? {
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

        let connected = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        let sent = payload.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int in
            guard let base = buf.baseAddress else { return -1 }
            return Int(Darwin.send(fd, base, buf.count, 0))
        }
        guard sent > 0 else { return nil }

        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, timeout) > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Int(recv(fd, base, raw.count, 0))
        }
        guard n >= 12 else { return nil }

        // 事务 ID 必须对得上，否则是别的查询的回包（或者上游在乱塞东西）
        let gotID = UInt16(buf[0]) << 8 | UInt16(buf[1])
        guard gotID == wantID else { return nil }
        // QR 位必须为 1
        guard buf[2] & 0x80 != 0 else { return nil }

        return Data(buf[0..<n])
    }
}
