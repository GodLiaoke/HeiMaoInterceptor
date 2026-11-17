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

    private var pin = ""
    private var code = ""
    private var verifyTimer: DispatchSourceTimer?

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

        SecureChannel.post("/auth/check", params: [:], pin: pin) { [weak self] result in
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
        ruleSet = RuleSet.parse(text: rulesText)
        dnsIP = (conf["dnsIP"] as? String) ?? AppConfig.dnsProxyIP
        clientIP = (conf["clientIP"] as? String) ?? AppConfig.clientIP
        let mtu = (conf["mtu"] as? Int) ?? AppConfig.mtu

        // 隧道网络参数：只接管规则 IP + DNS 代理地址，其它流量不碰
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: dnsIP)
        settings.mtu = NSNumber(value: mtu)

        let ipv4 = NEIPv4Settings(addresses: [clientIP], subnetMasks: ["255.255.255.255"])
        var routes: [NEIPv4Route] = [NEIPv4Route(destinationAddress: dnsIP, subnetMask: "255.255.255.255")]
        if let raw = conf["routes"] as? [[String: Any]] {
            for item in raw {
                guard let ip = item["ip"] as? String else { continue }
                let prefix = (item["prefix"] as? Int) ?? 32
                let mask = PacketTunnelProvider.maskString(prefix)
                // 避免把 0.0.0.0/0 拉进隧道，误伤正常上网
                if mask == "0.0.0.0" { continue }
                routes.append(NEIPv4Route(destinationAddress: ip, subnetMask: mask))
            }
        }
        ipv4.includedRoutes = routes
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: [dnsIP])
        dns.matchDomains = [""]
        settings.dnsSettings = dns

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completionHandler(error)
                return
            }
            let engine = TunnelEngine(flow: self.packetFlow, rules: self.ruleSet,
                                      dnsIP: self.dnsIP, clientIP: self.clientIP)
            self.engine = engine
            self.startedAt = Date()
            engine.start()
            self.startVerifyLoop()
            completionHandler(nil)
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
        SecureChannel.post("/auth/check", params: [:], pin: pin) { [weak self] result in
            guard let self = self else { return }
            guard case .success(let obj) = result else { return }   // 断网不处理
            let ok = (obj["authorized"] as? Bool) ?? false
            if !ok {
                let reason = (obj["reason"] as? String) ?? "unknown"
                /* 卡密中途失效：让系统把隧道停掉，App 回到前台会看到未授权 */
                let err = TunnelError.licenseInvalid(reason)
                self.cancelTunnelWithError(err)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        verifyTimer?.cancel()
        verifyTimer = nil
        engine?.stop()
        engine = nil
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
            let newRules = RuleSet.parse(text: text)
            ruleSet = newRules
            engine?.update(rules: newRules)
            completionHandler?(Data("ok".utf8))
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
        case licenseInvalid(String)

        var errorDescription: String? {
            switch self {
            case .missingConfiguration:
                return "缺少隧道配置，请重新激活"
            case .licenseExpired:
                return "卡密已到期，请续费后重试"
            case .configExpired:
                return "授权配置已过期，请重新激活"
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
