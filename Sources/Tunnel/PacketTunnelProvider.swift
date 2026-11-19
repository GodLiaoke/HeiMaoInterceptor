import Foundation
import NetworkExtension

/// VPN 隧道扩展入口
///
/// 授权相关的三道防线：
///   1. App 在点开启前先强校验（最前面拦住，用户立刻看到原因）
///   2. 扩展启动时自己再向服务端校验一次（防止旧配置被复用）
///   3. 运行时每 5 分钟复查一次，卡密中途被作废/到期就主动断开
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var engine: TunnelEngine?
    private var ruleSet = RuleSet()
    private var dnsIP = AppConfig.dnsProxyIP
    private var clientIP = AppConfig.clientIP
    private var startedAt = Date()
    /// 本次隧道的路由方案描述（诊断用）
    private var routeInfo = ""
    /// true = 全接管（0.0.0.0/0 + 例外）；false = 窄口
    private var routeHijackAll = false
    /// 规则热更新要按新规则重算路由，这里留一份启动时的配置和 MTU
    private var lastConf: [String: Any] = [:]
    private var lastMTU = AppConfig.mtu

    private var pin = ""
    private var code = ""
    private var verifyTimer: DispatchSourceTimer?
    /// 统计落盘定时器：sendProviderMessage 丢回包时 App 靠这份兜底
    private var statsTimer: DispatchSourceTimer?
    /// 本机直连的统计服务：不走沙箱共享目录、不走消息回调，环境挡不住
    private var statsServer: StatsServer?
    /// 快照会被四条通道同时拼装（定时器 / 消息回包 / 落盘 / 直连服务），
    /// 规则热更新又会在主线程换 ruleSet —— 加把锁，免得读到半个规则集
    private let payloadLock = NSLock()
    private var stopReason = ""
    /// 当前阶段：starting / running / stopped:原因 / failed:原因
    /// App 那边靠它判断隧道卡在哪一步，不用再靠猜
    private var phase = "idle"
    /// 周期校验连续失败次数：连着三次连不上服务端，就当链路断了，自己断开
    private var verifyFails = 0

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration else {
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        pin  = (conf["pin"] as? String) ?? ""
        code = (conf["code"] as? String) ?? ""

        /* 主程序把自己的 Documents 路径传过来了，统计就按这个路径写。
           这是跨进程最稳的一条通道：不依赖 App Group 容器有没有被系统建出来。 */
        StatsBridge.setExtraDir(conf["statsDir"] as? String)

        /* 本机直连统计服务：从一开始就起。
           这是「扩展回传统计」最硬的一条路 —— 不走消息回调、不写共享目录，
           伪签名环境和隧道重连都影响不到它。 */
        startStatsServer()

        guard !pin.isEmpty else {
            phase = "failed:no_pin"
            StatsBridge.write(statsPayload())
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        /* 心跳从第一毫秒就开始写：App 侧靠它判断「扩展到底起没起、卡在哪一步」。
           以前只有隧道设置成功之后才写统计，隧道起不来时 App 什么都读不到，
           面板全 0，分不清「没流量」和「根本没启动」。 */
        phase = "starting"
        startStatsPublisher()

        // 1. 本地兜底：卡密到期时间（不是在线窗口）
        let now = Date().timeIntervalSince1970
        let expireAt = (conf["expireAt"] as? Double) ?? 0
        if expireAt > 0 && expireAt < now {
            phase = "failed:license_expired"
            StatsBridge.write(statsPayload())
            completionHandler(TunnelError.licenseExpired)
            return
        }

        /* 2. 启动路径上不等网络。
           以前这里先 POST 一次授权校验才开始建隧道，通道请求超时 12 秒、
           资源超时 25 秒；网络差的时候会把 iOS 给隧道扩展的启动窗口耗光，
           系统直接判 provider 超时并杀掉扩展 —— 表现就是「开了跟没开一样」。
           现在先把隧道和应用设置起来（毫秒级完成），授权校验挪到隧道起来之后异步做，
           不通过就断开（dropProtection）。 */
        proceed(conf: conf, completionHandler: completionHandler)
    }

    /// 隧道起来之后再核一次授权（不阻塞启动）。
    /// 服务端说不能用就断开；网络不通就按本地宽限放行，等下一次心跳。
    private func verifyAfterStart() {
        guard !pin.isEmpty else { return }
        SecureChannel.post(Obfs.s(23), params: [:], pin: pin) { [weak self] result in
            guard let self = self else { return }
            guard case .success(let obj) = result else { return }
            let ok = (obj["authorized"] as? Bool) ?? false
            if !ok {
                let reason = (obj["reason"] as? String) ?? "unknown"
                self.dropProtection(reason: reason)
            }
        }
    }

    private func proceed(conf: [String: Any],
                         completionHandler: @escaping (Error?) -> Void) {
        // 3. 规则：App 传进来的是已经解密好的内存文本
        let rulesText = (conf["rulesText"] as? String) ?? ""
        if !rulesText.isEmpty {
            begin(rulesText: rulesText, conf: conf, completionHandler: completionHandler)
            return
        }

        // 兜底：扩展自己向云端取（同样需要有效卡密）
        RuleService.shared.load(pin: pin, code: code, force: false) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let text):
                self.begin(rulesText: text, conf: conf, completionHandler: completionHandler)
            case .failure(let err):
                completionHandler(err)
            }
        }
    }

    private func begin(rulesText: String,
                       conf: [String: Any],
                       completionHandler: @escaping (Error?) -> Void) {
        /* 几万条规则的解析放到后台队列，别堵着扩展的启动线程 */
        WorkQueue.async { [weak self] in
            let parsed = RuleSet.parse(text: rulesText)
            WorkQueue.main {
                guard let self = self else { return }
                self.applyRules(parsed, conf: conf, completionHandler: completionHandler)
            }
        }
    }

    private func applyRules(_ parsed: RuleSet,
                            conf: [String: Any],
                            completionHandler: @escaping (Error?) -> Void) {
        /* 规则一条都没解析出来就别开隧道：开了也拦不住任何东西，
           反而让用户以为防护生效了。 */
        guard !parsed.isEmpty else {
            phase = "failed:rules_empty"
            StatsBridge.write(statsPayload())
            completionHandler(TunnelError.ruleSetEmpty)
            return
        }
        payloadLock.lock(); ruleSet = parsed; payloadLock.unlock()
        dnsIP = (conf["dnsIP"] as? String) ?? AppConfig.dnsProxyIP
        clientIP = (conf["clientIP"] as? String) ?? AppConfig.clientIP
        let mtu = (conf["mtu"] as? Int) ?? AppConfig.mtu

        lastConf = conf
        lastMTU = mtu
        applyRoutePlan(makeRoutePlans(parsed, conf: conf), mtu: mtu,
                       completion: completionHandler)
    }

    /// 生成路由候选方案（从最精确到最能装）
    ///
    /// 前提：**默认路由必须指向隧道**。iOS 在 split tunnel（只接管几个网段）下，
    /// 系统的 DNS 查询经常压根不进隧道，NEDNSSettings 等于摆设 —— 表现就是
    /// 「规则下发了、域名一条都没拦」。所以下面每一档都必须是「全接管 + 补集例外」，
    /// 只有全都装不下时才退到「只接管规则段」（那一档域名规则基本废，仅保证 IP 规则能用）。
    ///
    /// 精确补集的条数随规则里 IP 数量增长：规则从 108 条 IP 涨到 196 条，
    /// 补集就从 1553 条涨到 2708 条 —— 以前上限写死 2600，一涨就整档被放弃，
    /// 于是降级成 split，域名规则静默失效。现在：
    ///   1. 上限放宽到能装下常见规模的精确补集
    ///   2. 精确档装不下时逐级放大聚合粒度，而不是直接跳到 split
    private func makeRoutePlans(_ parsed: RuleSet, conf: [String: Any]) -> [RuleSet.RoutePlan] {
        let dnsValue = RuleSet.ipToUInt(dnsIP) ?? 0x0A6F_0001
        let clientValue = RuleSet.ipToUInt(clientIP) ?? 0x0A6F_0002
        let keepInside = [dnsValue, clientValue]

        /* 1.1.1：全接管 + 精确补集优先。
           窄口模型（1.1.0）只把规则 IP 拽进隧道，iOS 在 split 隧道下经常不把
           系统 DNS 交给隧道，域名规则等于没生效 —— 这是「拦不完整」的根因。
           全接管让所有 DNS/TCP 都经过这里，非规则流量由 excludedRoutes 放回物理网卡。
           阶梯：精确 → /24 → /20 → /16，哪一档装得下用哪一档。
           精确档能保留「同网段邻居不受影响」，粗化档会多接管一点邻居地址。 */
        var plans: [RuleSet.RoutePlan] = []
        for bits in [32, 24, 20] {
            if let full = parsed.fullRoutePlan(forceInside: keepInside, coarsenTo: bits) {
                plans.append(full)
            }
        }

        /* 兜底一：窄口（规则 IP 段 + 假 DNS）。
           全接管补集装不下时用，保证至少 IP 规则能拦、也不会断网。 */
        plans.append(parsed.routePlan(forceInside: keepInside))

        /* 兜底二：规则段太碎（好几千条 /32）时逐级合并粒度再试 */
        for bits in [24, 20, 16] {
            plans.append(parsed.routePlan(forceInside: keepInside, coarsenTo: bits))
        }

        /* 兜底三：只留假 DNS，不做 IP 接管（退到最后也不能让用户断网） */
        var dnsOnly = RuleSet.RoutePlan()
        dnsOnly.degraded = true
        dnsOnly.included = [(dnsIP, 32)]
        plans.append(dnsOnly)
        return plans
    }

    /// 逐个尝试路由方案，第一个装得进去的生效
    private func applyRoutePlan(_ plans: [RuleSet.RoutePlan], mtu: Int, index: Int = 0,
                                completion: @escaping (Error?) -> Void) {
        guard index < plans.count else {
            phase = "failed:route_setup"
            StatsBridge.write(statsPayload())
            completion(TunnelError.routeSetupFailed); return
        }
        let plan = plans[index]
        setTunnelNetworkSettings(buildSettings(plan, mtu: mtu)) { [weak self] error in
            guard let self = self else { return }
            if error == nil {
                self.routeInfo = plan.description
                self.routeHijackAll = plan.hijackAll
                self.startEngine()
                completion(nil)
                return
            }
            self.applyRoutePlan(plans, mtu: mtu, index: index + 1, completion: completion)
        }
    }

    /// 规则热更新后按新规则重算路由
    ///
    /// 只换 ruleSet 不换路由的后果：新增的规则 IP 段仍然躺在 excludedRoutes 里，
    /// 那些流量照旧走物理网卡、压根不进隧道 —— 表现就是「规则更新了，新规则一条没生效」。
    /// 这里重设一次网络设置（会短暂 reassert），把补集按新规则重算。
    private func rebuildRoutes() {
        guard phase == "running" else { return }
        payloadLock.lock(); let snapshot = ruleSet; payloadLock.unlock()
        guard !snapshot.isEmpty else { return }
        applyRoutesOnly(makeRoutePlans(snapshot, conf: lastConf), mtu: lastMTU)
    }

    private func applyRoutesOnly(_ plans: [RuleSet.RoutePlan], mtu: Int, index: Int = 0) {
        guard index < plans.count else { return }
        let plan = plans[index]
        setTunnelNetworkSettings(buildSettings(plan, mtu: mtu)) { [weak self] error in
            guard let self = self else { return }
            if error == nil {
                self.routeInfo = plan.description
                self.routeHijackAll = plan.hijackAll
                StatsBridge.write(self.statsPayload())
                return
            }
            self.applyRoutesOnly(plans, mtu: mtu, index: index + 1)
        }
    }

    /// 按路由方案生成隧道网络设置（实例方法：避免局部函数在转义闭包里捕获 self）
    private func buildSettings(_ plan: RuleSet.RoutePlan, mtu: Int) -> NEPacketTunnelNetworkSettings {
        let s = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: dnsIP)
        s.mtu = NSNumber(value: mtu)
        let v4 = NEIPv4Settings(addresses: [clientIP], subnetMasks: ["255.255.255.255"])
        v4.includedRoutes = plan.included.map {
            /* /0 用系统自带的默认路由对象，别手搓 0.0.0.0/0.0.0.0 */
            $0.1 == 0 ? NEIPv4Route.default()
                      : NEIPv4Route(destinationAddress: $0.0,
                                    subnetMask: PacketTunnelProvider.maskString($0.1))
        }
        v4.excludedRoutes = plan.excluded.map {
            NEIPv4Route(destinationAddress: $0.0,
                        subnetMask: PacketTunnelProvider.maskString($0.1))
        }
        /* DNS 接管「所有域名」：matchDomains 放一个空串就是全部（ACE 的等价写法）。
           窄路由此刻仍然成立 —— 假 DNS 的 /32 已在 includedRoutes 里。 */
        let dns = NEDNSSettings(servers: [dnsIP])
        dns.matchDomains = [""]
        s.dnsSettings = dns
        s.ipv4Settings = v4
        return s
    }

    /// 起引擎 + 心跳复查
    private func startEngine() {
        let engine = TunnelEngine(flow: packetFlow, rules: ruleSet,
                                  dnsIP: dnsIP, clientIP: clientIP)
        self.engine = engine
        startedAt = Date()
        phase = "running"
        engine.start()
        startVerifyLoop()
        startStatsPublisher()

        /* 保险：授权校验放到隧道跑起来之后，别挡着启动 */
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.verifyAfterStart()
        }

        /* 1.1.1 删掉了「启动 20 秒后旁路包占比高就主动断开」这段。
           那个判据是给全接管方案兜底的，但窄口/全接管下 DNS 转发、规则 IP 的
           非目标端口流量都会被算成 stray —— 正常使用也会被误判成「路由被系统忽略」，
           用户看到的就是 VPN 莫名其妙掉线。路由有没有生效改由诊断行判断，不再自动断网。 */
    }

    /// 运行中复查：卡密中途被作废 / 到期，隧道主动断开
    private func startVerifyLoop() {
        verifyTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "hm.verify"))
        t.schedule(deadline: .now() + AppConfig.tunnelVerifyInterval,
                   repeating: AppConfig.tunnelVerifyInterval)
        t.setEventHandler { [weak self] in
            self?.verifyOnce()
        }
        t.resume()
        verifyTimer = t
    }

    private func verifyOnce() {
        guard !pin.isEmpty else { return }
        SecureChannel.post(Obfs.s(23), params: [:], pin: pin) { [weak self] result in
            guard let self = self else { return }

            guard case .success(let obj) = result else {
                /* 1.1.1：网络失败不再断隧道。
                   以前连续两次（10 分钟）连不上服务端就 cancelTunnelWithError，
                   手机锁屏、切网、地铁里信号差都会触发 —— 用户体感就是「VPN 老是断开」。
                   防护是否继续由本地授权状态决定，服务端连不上只是复核延后。 */
                self.verifyFails += 1
                return
            }
            self.verifyFails = 0

            let ok = (obj["authorized"] as? Bool) ?? false
            if !ok {
                let reason = (obj["reason"] as? String) ?? "unknown"
                self.dropProtection(reason: reason)
            }
        }
    }

    /// 卸载规则 + 停隧道：内存里的规则先清掉再断，断完这一份就不存在了
    private func dropProtection(reason: String) {
        stopReason = reason
        phase = "stopped:\(reason)"
        /* 先把停下来那一刻的数字落盘，再拆引擎：
           否则定时器下一次写盘会把所有计数刷成 0，用户看到的就是「归零」 */
        StatsBridge.write(statsPayload())
        statsTimer?.cancel()
        statsTimer = nil
        stopStatsServer()
        payloadLock.lock(); ruleSet = RuleSet(); payloadLock.unlock()
        engine?.stop()
        engine = nil
        if reason == "route_hijack_failed" {
            cancelTunnelWithError(TunnelError.routeBroken)
        } else {
            cancelTunnelWithError(TunnelError.licenseInvalid(reason))
        }
    }

    /// 统计快照：provider message / 落盘 / 本机直连服务共用同一份，三边数字必须一致
    private func statsPayload() -> [String: Any] {
        payloadLock.lock()
        defer { payloadLock.unlock() }

        var payload = engine?.snapshot() ?? [:]
        payload["startedAt"] = Int(startedAt.timeIntervalSince1970)
        payload["rules"] = ruleSet.summary.ips + ruleSet.summary.domains
        payload["routes"] = routeInfo
        payload["mode"] = "ace"
        payload["routeMode"] = routeHijackAll ? "full" : "narrow"
        payload["routeCount"] = ruleSet.report.routes
        payload["phase"] = phase
        /* 注意：这里必须是 dnsServer，不能写 dns。
           写成 dns 会把引擎回上来的 DNS 查询计数覆盖成地址字符串，
           App 侧 as? Int 读到 nil，DNS 那一格永远是 0。 */
        payload["dnsServer"] = dnsIP
        payload["engine"] = engine != nil
        payload["stopReason"] = stopReason
        payload["ruleReport"] = [
            "ips": ruleSet.report.exactIPs + ruleSet.report.cidrs,
            "domains": ruleSet.report.domains,
            "direct": ruleSet.report.direct,
            "ports": ruleSet.report.ports,
            "skipped": ruleSet.report.skipped,
        ]
        payload["bridgeAt"] = Int(Date().timeIntervalSince1970)
        return payload
    }

    /// 每 2 秒把统计落一份盘，App 侧 sendProviderMessage 丢回包时读这份
    private func startStatsPublisher() {
        statsTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "hm.stats"))
        t.schedule(deadline: .now() + 1, repeating: 2)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            StatsBridge.write(self.statsPayload())
        }
        t.resume()
        statsTimer = t
    }

    /// 起本机直连统计服务（只有回环能连）：
    /// App 每 3 秒连一次问数字，服务器一停端口就消失，不存在残留状态。
    private func startStatsServer() {
        guard statsServer == nil else { return }
        let server = StatsServer { [weak self] in
            self?.statsPayload() ?? [:]
        }
        server.start()
        statsServer = server
    }

    private func stopStatsServer() {
        statsServer?.stop()
        statsServer = nil
    }

    /// 设备休眠 / 唤醒
    ///
    /// 系统休眠时会把扩展挂起，readPackets 的回调有可能不再回来。
    /// 唤醒后不重新拉一轮，表现就是「VPN 显示已连接，但一个包都不读了」——
    /// 用户以为隧道断了，其实是引擎停摆，拦截全失效。
    override func sleep(completionHandler: @escaping () -> Void) {
        StatsBridge.write(statsPayload())
        completionHandler()
    }

    override func wake() {
        StatsBridge.write(statsPayload())
        guard phase == "running", let engine = engine else { return }
        engine.resumeReading()
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        statsTimer?.cancel()
        statsTimer = nil
        stopReason = "stopped"
        phase = "stopped"
        /* 在引擎还活着时落最后一份：App 下一次轮询还能把停止前的数字读出来 */
        StatsBridge.write(statsPayload())
        stopStatsServer()
        verifyTimer?.cancel()
        verifyTimer = nil
        engine?.stop()
        engine = nil
        /* 关闭即卸载：不在扩展进程里留任何规则副本 */
        payloadLock.lock(); ruleSet = RuleSet(); payloadLock.unlock()
        verifyFails = 0
        completionHandler()
    }

    /// App 侧通过 sendProviderMessage 取统计 / 热更新规则
    override func handleAppMessage(_ messageData: Data,
                                  completionHandler: ((Data?) -> Void)? = nil) {
        guard let cmd = String(data: messageData, encoding: .utf8) else {
            completionHandler?(nil); return
        }

        if cmd == "stats" {
            let payload = statsPayload()
            StatsBridge.write(payload)
            let data = try? JSONSerialization.data(withJSONObject: payload)
            completionHandler?(data)
            return
        }

        if cmd == "verify" {
            verifyOnce()
            completionHandler?(Data("ok".utf8))
            return
        }

        if cmd.hasPrefix("rules:") {
            let text = String(cmd.dropFirst(6))
            WorkQueue.async { [weak self] in
                guard let self = self else { return }
                let newRules = RuleSet.parse(text: text)
                WorkQueue.main {
                    /* 热更新失败时保留旧规则，不要因为一次坏包把防护清空 */
                    guard !newRules.isEmpty else {
                        completionHandler?(Data("reject".utf8))
                        return
                    }
                    self.payloadLock.lock(); self.ruleSet = newRules; self.payloadLock.unlock()
                    self.engine?.update(rules: newRules)
                    /* 规则变了，路由必须跟着重算：不然新增的规则 IP 段还在
                       排除列表里，作业面上「规则更新了但新规则不拦」。 */
                    self.rebuildRoutes()
                    let info = "ok:\(self.routeInfo)"
                    completionHandler?(Data(info.utf8))
                }
            }
            return
        }

        completionHandler?(Data("unknown".utf8))
    }

    // MARK: - 工具

    static func maskString(_ prefix: Int) -> String {
        let p = max(0, min(32, prefix))
        var value: UInt32 = p == 0 ? 0 : (0xFFFFFFFF << UInt32(32 - p)) & 0xFFFFFFFF
        var parts: [String] = []
        for _ in 0..<4 {
            parts.append(String(value & 0xFF))
            value >>= 8
        }
        return parts.reversed().joined(separator: ".")
    }

    enum TunnelError: LocalizedError {
        case missingConfiguration
        case licenseExpired
        case configExpired
        case ruleSetEmpty
        case routeSetupFailed
        case routeBroken
        case licenseInvalid(String)

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "缺少隧道配置，请重新激活"
            case .licenseExpired:
                return "卡密已到期，请续费后重试"
            case .configExpired:
                return "授权配置已过期，请重新激活"
            case .ruleSetEmpty:
                return "云端规则为空，请稍后重试"
            case .routeSetupFailed:
                return "隧道网络设置失败，请重启应用后重试"
            case .routeBroken:
                return "这台设备的系统没接受拦截路由（为避免断网已自动关闭），请把这条提示发给管理员"
            case .licenseInvalid(let reason):
                switch reason {
                case "card_revoked":   return "卡密已被作废，防护无法开启"
                case "card_expired":   return "卡密已过期，防护无法开启"
                case "card_not_found": return "卡密不存在，请重新激活"
                case "no_card":        return "当前设备未绑定卡密"
                case "window_expired": return "授权校验已过期，请先在 App 里刷新状态"
                default:               return "授权无效，防护无法开启"
                }
            }
        }
    }
}
