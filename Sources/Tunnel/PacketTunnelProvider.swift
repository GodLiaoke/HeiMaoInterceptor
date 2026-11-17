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

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: dnsIP)
        settings.mtu = NSNumber(value: mtu)

        /* 路由：**默认路由指向隧道**，规则之外的地址全部排除回物理网络。
           为什么必须这样：iOS 在 split tunnel（只接管几个网段）下，系统的 DNS
           查询经常压根不进隧道，DNS 设置等于摆设 —— 表现就是「开了防护一点没拦住」。
           把隧道设成默认出口后，DNS 设置一定生效，而真正进隧道的仍然只有规则 IP 段
           （其余的都在 excludedRoutes 里，照常走 Wi-Fi / 蜂窝，不影响上网速度）。 */
        let dnsValue  = RuleSet.ipToUInt(dnsIP) ?? 0x0A6F0001
        let sinkValue = RuleSet.ipToUInt(sinkholeIP) ?? 0x0A6F0009
        var plan = parsed.routePlan(forceInside: [dnsValue, sinkValue])

        /* 兼容：App 侧若在配置里额外给了路由，并进接管列表 */
        if let raw = conf["routes"] as? [[String: Any]] {
            for item in raw {
                guard let ip = item["ip"] as? String else { continue }
                let prefix = (item["prefix"] as? Int) ?? 32
                plan.included.append((ip, prefix))
            }
        }
        routeInfo = plan.description

        func buildSettings(_ plan: RuleSet.RoutePlan) -> NEPacketTunnelNetworkSettings {
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
            let dns = NEDNSSettings(servers: [dnsIP])
            s.dnsSettings = dns
            s.ipv4Settings = v4
            return s
        }

        /* DNS 必须接管「所有域名」：matchDomains 留空（nil）才表示全部，
           之前写成 [""]（一个空字符串）等价于不匹配任何域名，
           系统 DNS 查询压根不进隧道 —— 域名规则因此一条都用不上。 */
        let dns = NEDNSSettings(servers: [dnsIP])
        settings.dnsSettings = dns

        func startEngine() {
            let engine = TunnelEngine(flow: self.packetFlow, rules: self.ruleSet,
                                      dnsIP: self.dnsIP, clientIP: self.clientIP,
                                      sinkholeIP: self.sinkholeIP)
            self.engine = engine
            self.startedAt = Date()
            engine.start()
            self.startVerifyLoop()
        }

        setTunnelNetworkSettings(buildSettings(plan)) { [weak self] error in
            guard let self = self else { return }
            if error == nil {
                startEngine()
                completionHandler(nil)
                return
            }

            /* 全接管方案没装进去（路由条数太多 / 系统拒绝）：退回只接管规则段，
               宁可 DNS 可能不生效，也不能让用户开不了防护或者断网。 */
            var fallback = RuleSet.RoutePlan()
            fallback.degraded = true
            fallback.included = RuleSet.cidrs(from: parsed.blockedRanges())
            fallback.included.append((dnsIP, 32))
            fallback.included.append((sinkholeIP, 32))
            self.routeInfo = "降级 · 按规则段接管 \(fallback.included.count) 条"

            self.setTunnelNetworkSettings(buildSettings(fallback)) { [weak self] err2 in
                guard let self = self else { return }
                if let err2 = err2 {
                    completionHandler(err2)
                    return
                }
                startEngine()
                completionHandler(nil)
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
        ruleSet = RuleSet()
        engine?.stop()
        engine = nil
        cancelTunnelWithError(TunnelError.licenseInvalid(reason))
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
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
            var payload = engine?.snapshot() ?? [:]
            payload["startedAt"] = Int(startedAt.timeIntervalSince1970)
            payload["rules"] = ruleSet.summary.ips + ruleSet.summary.domains
            payload["routes"] = routeInfo
            payload["dns"] = dnsIP
            payload["ruleReport"] = [
                "ips": ruleSet.report.exactIPs + ruleSet.report.cidrs,
                "domains": ruleSet.report.domains,
                "direct": ruleSet.report.direct,
                "ports": ruleSet.report.ports,
                "skipped": ruleSet.report.skipped,
            ]
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
