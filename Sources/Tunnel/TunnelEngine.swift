import Foundation
import NetworkExtension
import Darwin

/// 拦截内核（ACE 同构的用户态判定）
///
/// 三条链路，互不交叉：
///   1. IP 层：进隧道的 TCP/UDP 命中规则 → TCP 回 40 字节 RST，UDP 静默丢弃
///   2. DNS 层：命中域名 → 直接伪造应答（A 答 0.0.0.0 / TTL 60，其它类型答 0 记录）
///   3. 其余：一律不转发（这个实现里没有「未命中就放出去」的路径，与原版一致）
///
/// 路由只把规则里的 IP 段和假 DNS 的 /32 拉进隧道，所以「未命中」本来就不该出现；
/// 真出现了只计数，不在这里断用户的正常流量。
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
        /// 上游全部失败、给客户端回了 SERVFAIL 的次数
        var dnsFailures = 0
        /// 不该进隧道的包（路由没生效时会冒出来）
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
             "dnsFail": dnsFailures,
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

    /// 规则快照 + DNS 缓存共用一把锁。都是纳秒级操作，不排队、不切线程。
    private let stateLock = NSLock()
    private var rules: RuleSet
    private var dnsCache: [String: CacheEntry] = [:]
    private var dnsCacheKeys: [String] = []
    private let dnsCacheLimit = 1024

    /// 同一条连接只回一次 RST，避免重传包把 RST 风暴打回给内核
    private var rstSeen: [UInt64: TimeInterval] = [:]

    private let statsLock = NSLock()
    private var stats = Stats()

    /// DNS 转发用固定数量的串行 worker。
    ///
    /// 1.1.0 是 concurrent queue + semaphore(8)：每个查询要阻塞 900ms×3 个上游，
    /// 网页一开就是几十个域名同时进来，GCD 会不停加线程，线程数一爆扩展就被系统回收
    /// —— 用户看到的就是「VPN 老是断开」。固定 worker 后线程数封顶。
    private let dnsWorkers: [DispatchQueue] = (0..<6).map {
        DispatchQueue(label: "com.heimao.engine.dns.\($0)", qos: .userInitiated)
    }
    private var dnsCursor = 0
    private let dnsCursorLock = NSLock()

    /// 读包循环的状态：唤醒后要能重新拉起来，但不能同时挂两条链
    private let readLock = NSLock()
    private var reading = false
    private var lastReadAt = Date()

    private var running = false
    private let runningLock = NSLock()

    init(flow: NEPacketTunnelFlow, rules: RuleSet, dnsIP: String, clientIP: String) {
        self.flow = flow
        self.rules = rules
        self.dnsIPv4 = RuleSet.ipToUInt(dnsIP) ?? 0x0A6F_0001
        self.clientIPv4 = RuleSet.ipToUInt(clientIP) ?? 0x0A6F_0002
    }

    /// 外部（provider）读取统计
    func snapshot() -> [String: Any] {
        statsLock.lock(); defer { statsLock.unlock() }
        return stats.json
    }

    /// 规则热更新：必须连 DNS 缓存一起清掉，否则改过的域名还会拿到旧结果
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
        /* 隧道被系统重启时把刚才的数字接上（只接 30 秒内的） */
        var seed = Stats()
        let prev = StatsBridge.read()
        if let at = prev["bridgeAt"] as? Int,
           abs(Int(Date().timeIntervalSince1970) - at) <= 30 {
            seed.blockedPackets = TunnelEngine.value(prev["blocked"])
            seed.blockedDomains = TunnelEngine.value(prev["domains"])
            seed.blockedTCP     = TunnelEngine.value(prev["tcp"])
            seed.blockedUDP     = TunnelEngine.value(prev["udp"])
            seed.blockedConn    = TunnelEngine.value(prev["conn"])
            seed.passedDNS      = TunnelEngine.value(prev["passed"])
        }
        statsLock.lock(); stats = seed; statsLock.unlock()
        runningLock.lock(); running = true; runningLock.unlock()
        startReading()
    }

    private static func value(_ any: Any?) -> Int {
        if let v = any as? Int { return v }
        if let v = any as? NSNumber { return v.intValue }
        if let v = any as? String, let d = Double(v) { return Int(d) }
        return 0
    }

    func stop() {
        runningLock.lock(); running = false; runningLock.unlock()
        readLock.lock(); reading = false; readLock.unlock()
    }

    private var isRunning: Bool {
        runningLock.lock(); defer { runningLock.unlock() }
        return running
    }

    /// 唤醒后重新拉一轮读包循环
    ///
    /// 幂等：已经在读就直接返回，不会挂出两条 readPackets。
    /// 只有「超过 60 秒一个包都没读到」才认为上一轮回调死掉了、需要重建，
    /// 避免空闲时误判成停摆。
    func resumeReading() {
        readLock.lock()
        let stale = Date().timeIntervalSince(lastReadAt) > 60
        if reading && stale { reading = false }
        let need = !reading
        if need { reading = true }
        readLock.unlock()
        if need { readOnce() }
    }

    private func startReading() {
        readLock.lock()
        reading = true
        lastReadAt = Date()
        readLock.unlock()
        readOnce()
    }

    private func readOnce() {
        guard isRunning else {
            readLock.lock(); reading = false; readLock.unlock()
            return
        }
        flow.readPackets { [weak self] packets, _ in
            guard let self = self else { return }
            if !self.isRunning {
                self.readLock.lock(); self.reading = false; self.readLock.unlock()
                return
            }
            self.readLock.lock(); self.lastReadAt = Date(); self.readLock.unlock()
            for pkt in packets {
                self.handle(pkt)
            }
            self.readOnce()
        }
    }

    // MARK: - 单包处理（对应 Dh.handle）

    private func handle(_ data: Data) {
        guard let p = PacketCodec.parse(data) else { return }
        statsLock.lock(); stats.tunnelPackets += 1; statsLock.unlock()

        if p.proto == 17, let udp = p.udp {
            /* DNS：进隧道的查询只可能是发给假 DNS 的（路由只放了它的 /32），
               这里不挑目标地址 —— 换网 / 系统缓存回退时仍可能发到旧地址 */
            if udp.dstPort == 53 {
                statsLock.lock(); stats.dnsQueries += 1; statsLock.unlock()
                handleDNS(p)
                return
            }
            if isBlocked(p.dstIP, port: Int(udp.dstPort)) {
                statsLock.lock()
                stats.blockedPackets += 1
                stats.blockedUDP += 1
                statsLock.unlock()
            } else {
                statsLock.lock(); stats.stray += 1; statsLock.unlock()
            }
            return                      // UDP 一律不转发
        }

        if p.proto == 6, let tcp = p.tcp {
            if isBlocked(p.dstIP, port: Int(tcp.dstPort)) {
                dropTCP(p, key: PacketCodec.flowKey(p))
            } else {
                statsLock.lock(); stats.stray += 1; statsLock.unlock()
            }
            return                      // TCP 一律不转发
        }

        /* ICMP / 其它协议：丢（原版也是直接 return） */
    }

    /// 断一条 TCP 连接
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

    private func isBlocked(_ ip: UInt32, port: Int) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return rules.isBlockedIp(ip, port: port)
    }

    private func isDomainBlocked(_ domain: String) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return rules.isBlockedDomain(domain)
    }

    // MARK: - DNS 缓存（只缓存放行答复）

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

        var out = entry.response
        if out.count >= 2 {
            out[0] = UInt8((id >> 8) & 0xFF)
            out[1] = UInt8(id & 0xFF)
        }
        statsLock.lock(); stats.cacheHits += 1; statsLock.unlock()
        return out
    }

    private func storeCache(key: String, response: Data) {
        guard response.count >= 12 else { return }
        stateLock.lock()
        if dnsCache[key] == nil { dnsCacheKeys.append(key) }
        dnsCache[key] = CacheEntry(response: response,
                                   expireAt: Date().timeIntervalSince1970 + 90)
        if dnsCacheKeys.count > dnsCacheLimit {
            let drop = dnsCacheKeys.prefix(256)
            for k in drop { dnsCache.removeValue(forKey: k) }
            dnsCacheKeys.removeFirst(min(256, dnsCacheKeys.count))
        }
        stateLock.unlock()
    }

    // MARK: - DNS 子链路（对应 Dh.handleDns）

    private func handleDNS(_ p: PacketCodec.Parsed) {
        guard let udp = p.udp else { return }
        let payload = p.payload

        guard let query = DNSMessage.parseQuery(payload) else {
            /* 问题段解析失败：原样送去上游（原版也是 forward，不是丢弃） */
            forwardDNS(payload, query: nil, from: p, udp: udp, cacheKey: nil)
            return
        }

        let key = TunnelEngine.cacheKey(query.qname, query.qtype)

        if isDomainBlocked(query.qname) {
            let answer = DNSMessage.buildSinkhole(for: query)
            sendDNS(answer, from: p.dstIP, to: p.srcIP, port: udp.srcPort)
            statsLock.lock()
            stats.blockedPackets += 1
            stats.blockedDomains += 1
            statsLock.unlock()
            return
        }

        if let cached = cachedResponse(key: key, id: query.id) {
            sendDNS(cached, from: p.dstIP, to: p.srcIP, port: udp.srcPort)
            return
        }

        forwardDNS(payload, query: query, from: p, udp: udp, cacheKey: key)
    }

    private func forwardDNS(_ payload: Data, query: DNSMessage.Query?,
                            from p: PacketCodec.Parsed,
                            udp: PacketCodec.UDPInfo, cacheKey: String?) {
        statsLock.lock(); stats.passedDNS += 1; statsLock.unlock()
        let clientIP = p.srcIP
        let clientPort = udp.srcPort
        let serverIP = p.dstIP

        dnsCursorLock.lock()
        let worker = dnsWorkers[dnsCursor % dnsWorkers.count]
        dnsCursor &+= 1
        dnsCursorLock.unlock()

        worker.async { [weak self] in
            guard let self = self else { return }

            guard let response = DNSUpstream.query(payload) else {
                /* 三个上游全失败：回 SERVFAIL，让客户端立刻重试/换域名。
                   以前是直接不回包，客户端只能干等到自己超时，体感就是「网卡了」。 */
                self.statsLock.lock(); self.stats.dnsFailures += 1; self.statsLock.unlock()
                if let q = query {
                    self.sendDNS(DNSMessage.buildFailure(for: q),
                                 from: serverIP, to: clientIP, port: clientPort)
                }
                return
            }
            /* CNAME 链检查：规则里配的是 CNAME 目标时，只看请求的 qname 会漏。
               命中就把这条应答换成黑洞，客户端拿到 0.0.0.0。 */
            if let q = query,
               DNSMessage.firstBlockedName(in: response,
                                           checker: { self.isDomainBlocked($0) }) != nil {
                self.statsLock.lock()
                self.stats.blockedPackets += 1
                self.stats.blockedDomains += 1
                self.statsLock.unlock()
                self.sendDNS(DNSMessage.buildSinkhole(for: q),
                             from: serverIP, to: clientIP, port: clientPort)
                return
            }

            if let key = cacheKey {
                self.storeCache(key: key, response: response)
            }
            self.sendDNS(response, from: serverIP, to: clientIP, port: clientPort)
        }
    }

    /// 回包：源地址固定成假 DNS（10.111.0.1），源端口 53
    private func sendDNS(_ payload: Data, from src: UInt32, to dst: UInt32, port: UInt16) {
        let packet = PacketCodec.buildUDP(src: src, dst: dst,
                                          srcPort: 53, dstPort: port, payload: payload)
        write([packet])
    }

    private func write(_ packets: [Data]) {
        guard !packets.isEmpty else { return }
        let protos = packets.map { _ in NSNumber(value: AF_INET) }
        flow.writePackets(packets, withProtocols: protos)
    }
}

/// 上游 DNS 转发
///
///   - socket 用 connect 绑定上游，只收这一家的回包（不会被串话 / 投毒干扰）
///   - 校验事务 ID 与请求一致
///   - 单个上游 900ms 超时，失败立刻换下一个（三个都失败就不回包，客户端自己超时）
enum DNSUpstream {

    /// 三路上游并行问，谁先回用谁。
    ///
    /// 1.1.0 是串行三级回落（900ms × 3 = 最差 2.7 秒），网页一开就一堆域名排着队等，
    /// 体感是「开了防护网就变慢」，慢到最后系统把隧道判死。并行后最差 600ms。
    static func query(_ payload: Data, timeout: Int32 = 600) -> Data? {
        guard payload.count >= 2 else { return nil }
        let wantID = UInt16(payload[0]) << 8 | UInt16(payload[1])
        let servers = AppConfig.upstreamDNS
        guard !servers.isEmpty else { return nil }

        let lock = NSLock()
        var result: Data?
        let group = DispatchGroup()

        for server in servers {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                if let r = send(payload, to: server, timeout: timeout, wantID: wantID) {
                    lock.lock()
                    if result == nil { result = r }
                    lock.unlock()
                }
            }
        }

        _ = group.wait(timeout: .now() + .milliseconds(Int(timeout) + 150))
        lock.lock(); let out = result; lock.unlock()
        return out
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

        let gotID = UInt16(buf[0]) << 8 | UInt16(buf[1])
        guard gotID == wantID else { return nil }
        guard buf[2] & 0x80 != 0 else { return nil }

        return Data(buf[0..<n])
    }
}
