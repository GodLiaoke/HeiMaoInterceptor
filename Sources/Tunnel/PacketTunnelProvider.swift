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
    private var sinkholeIP = AppConfig.sinkholeIP
    private var startedAt = Date()
    /// 本次隧道的路由方案描述（诊断用）
    private var routeInfo = ""

    private var pin = ""
    private var code = ""
    private var verifyTimer: DispatchSourceTimer?
    /// 统计落盘定时器：sendProviderMessage 丢回包时 App 靠这份兜底
    private var statsTimer: DispatchSourceTimer?
    private var stopReason = ""
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

        // 1. 本地兜底：卡密到期时间（不是在线窗口）
        let now = Date().timeIntervalSince1970
        let expireAt = (conf["expireAt"] as? Double) ?? 0
        if expireAt > 0 && expireAt < now {
            completionHandler(TunnelError.licenseExpired)
            return
        }

        // 2. 向服务端确认这张卡现在还能不能用（卡密被作废在这一步拦下）
        verifyOrStart(conf: conf, completionHandler: completionHandler)
    }

    /// 启动前校验：服务端说不能用了就直接失败；网络不通则按本地宽限放行
    private func verifyOrStart(conf: [String: Any],
                               completionHandler: @escaping (Error?) -> Void) {
        guard !pin.isEmpty else {
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        SecureChannel.post(Obfs.s(23), params: [:], pin: pin) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let obj):
                let ok = (obj["authorized"] as? Bool) ?? false
                if !ok {
                    let reason = (obj["reason"] as? String) ?? "unknown"
                    completionHandler(TunnelError.licenseInvalid(reason))
                    return
                }
                self.proceed(conf: conf, completionHandler: completionHandler)

            case .failure:
                /* 断网：本地还有效就放行（App 侧会在联网后补校验） */
                self.proceed(conf: conf, completionHandler: completionHandler)
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
            completionHandler(TunnelError.ruleSetEmpty)
            return
        }
        ruleSet = parsed
        dnsIP = (conf["dnsIP"] as? String) ?? AppConfig.dnsProxyIP
        clientIP = (conf["clientIP"] as? String) ?? AppConfig.clientIP
        sinkholeIP = (conf["sinkholeIP"] as? String) ?? AppConfig.sinkholeIP
        let mtu = (conf["mtu"] as? Int) ?? AppConfig.mtu

        /* 路由：**默认路由指向隧道**，规则之外的地址全部排除回物理网络。
           为什么必须这样：iOS 在 split tunnel（只接管几个网段）下，系统的 DNS
           查询经常压根不进隧道，DNS 设置等于摆设 —— 表现就是「开了防护一点没拦住」。
           把隧道设成默认出口后，DNS 设置一定生效，而真正进隧道的仍然只有规则 IP 段
           （其余的都在 excludedRoutes 里，照常走 Wi-Fi / 蜂窝，不影响上网速度）。 */
        let dnsValue  = RuleSet.ipToUInt(dnsIP) ?? 0x0A6F0001
        let sinkValue = RuleSet.ipToUInt(sinkholeIP) ?? 0x0A6F0009
        var plan = parsed.routePlan(forceInside: [dnsValue, sinkValue])

        /* 依次尝试：精确补集 → /24 聚合 → /16 聚合 → 只接管规则段。
           前三种都保住「隧道是默认出口」，也就是 DNS 一定进隧道；
           最后一种只在系统死活装不下时兜底，至少防护能用。 */
        var exact = plan
        if let raw = conf["routes"] as? [[String: Any]], plan.hijackAll {
            for item in raw {
                guard let ip = item["ip"] as? String else { continue }
                exact.excluded.removeAll { $0.0 == ip }
            }
        }
        var wide24 = parsed.routePlan(forceInside: [dnsValue, sinkValue], coarsenTo: 24)
        wide24.hijackAll = plan.hijackAll
        var wide16 = parsed.routePlan(forceInside: [dnsValue, sinkValue], coarsenTo: 16)
        wide16.hijackAll = plan.hijackAll

        var split = RuleSet.RoutePlan()
        split.degraded = true
        split.included = RuleSet.cidrs(from: parsed.blockedRanges())
        split.included.append((dnsIP, 32))
        split.included.append((sinkholeIP, 32))

        applyRoutePlan([exact, wide24, wide16, split], mtu: mtu,
                       completion: completionHandler)
    }

    /// 逐个尝试路由方案，第一个装得进去的生效
    private func applyRoutePlan(_ plans: [RuleSet.RoutePlan], mtu: Int, index: Int = 0,
                                completion: @escaping (Error?) -> Void) {
        guard index < plans.count else {
            completion(TunnelError.routeSetupFailed); return
        }
        let plan = plans[index]
        setTunnelNetworkSettings(buildSettings(plan, mtu: mtu)) { [weak self] error in
            guard let self = self else { return }
            if error == nil {
                self.routeInfo = plan.description
                self.startEngine()
                completion(nil)
                return
            }
            self.applyRoutePlan(plans, mtu: mtu, index: index + 1, completion: completion)
        }
    }

    /// 按路由方案生成隧道网络设置（实例方法：避免局部函数在转义闭包里捕获 self）
    private func buildSettings(_ plan: RuleSet.RoutePlan, mtu: Int) -> NEPacketTunnelNetworkSettings {
        let s = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: dnsIP)
        s.mtu = NSNumber(value: mtu)
        let v4 = NEIPv4Settings(addresses: [clientIP], subnetMasks: ["255.255.255.255"])
        v4.includedRoutes = plan.included.map {
            NEIPv4Route(destinationAddress: $0.0,
                        subnetMask: PacketTunnelProvider.maskString($0.1))
        }
        v4.excludedRoutes = plan.excluded.map {
            NEIPv4Route(destinationAddress: $0.0,
                        subnetMask: PacketTunnelProvider.maskString($0.1))
        }
        /* DNS 必须接管「所有域名」：matchDomains 留空（nil）才表示全部 */
        s.dnsSettings = NEDNSSettings(servers: [dnsIP])
        s.ipv4Settings = v4
        return s
    }

    /// 起引擎 + 心跳复查
    private func startEngine() {
        let engine = TunnelEngine(flow: packetFlow, rules: ruleSet,
                                  dnsIP: dnsIP, clientIP: clientIP,
                                  sinkholeIP: sinkholeIP)
        self.engine = engine
        startedAt = Date()
        engine.start()
        startVerifyLoop()
        startStatsPublisher()

        /* 保险：全接管方案如果被系统忽略了排除路由，用户会「上不了网」。
           启动 20 秒后看一眼统计，旁路包占了绝大多数就直接断开，
           宁可防护失效也不能让用户断网。 */
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self = self, let engine = self.engine else { return }
            let snap = engine.snapshot()
            let total = (snap["tunnel"] as? Int) ?? 0
            let stray = (snap["stray"] as? Int) ?? 0
            if total > 300 && stray > total * 3 / 4 {
                self.dropProtection(reason: "route_hijack_failed")
            }
        }
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
                /* 一次失败不动作；连续失败等于心跳断了，规则立刻作废并断开隧道 */
                self.verifyFails += 1
                if self.verifyFails >= 2 {
                    self.verifyFails = 0
                    self.dropProtection(reason: "heartbeat_lost")
                }
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
        /* 先把停下来那一刻的数字落盘，再拆引擎：
           否则定时器下一次写盘会把所有计数刷成 0，用户看到的就是「归零」 */
        StatsBridge.write(statsPayload())
        statsTimer?.cancel()
        statsTimer = nil
        ruleSet = RuleSet()
        engine?.stop()
        engine = nil
        if reason == "route_hijack_failed" {
            cancelTunnelWithError(TunnelError.routeBroken)
        } else {
            cancelTunnelWithError(TunnelError.licenseInvalid(reason))
        }
    }

    /// 统计快照：provider message 和落盘通道共用同一份，两边数字必须一致
    private func statsPayload() -> [String: Any] {
        var payload = engine?.snapshot() ?? [:]
        payload["startedAt"] = Int(startedAt.timeIntervalSince1970)
        payload["rules"] = ruleSet.summary.ips + ruleSet.summary.domains
        payload["routes"] = routeInfo
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

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        statsTimer?.cancel()
        statsTimer = nil
        stopReason = "stopped"
        /* 在引擎还活着时落最后一份：App 下一次轮询还能把停止前的数字读出来 */
        StatsBridge.write(statsPayload())
        verifyTimer?.cancel()
        verifyTimer = nil
        engine?.stop()
        engine = nil
        /* 关闭即卸载：不在扩展进程里留任何规则副本 */
        ruleSet = RuleSet()
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
                    self.ruleSet = newRules
                    self.engine?.update(rules: newRules)
                    completionHandler?(Data("ok".utf8))
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
