import Foundation
import NetworkExtension

/// VPN 隧道扩展入口
final class PacketTunnelProvider: NEPacketTunnelProvider {

    private var engine: TunnelEngine?
    private var ruleSet = RuleSet()
    private var dnsIP = AppConfig.dnsProxyIP
    private var clientIP = AppConfig.clientIP
    private var startedAt = Date()

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        guard let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration else {
            completionHandler(TunnelError.missingConfiguration)
            return
        }

        // 1. 授权时效：卡密到期 / 配置包到期 任一过期即拒绝启动
        let now = Date().timeIntervalSince1970
        let expireAt = (conf["expireAt"] as? Double) ?? 0
        let configExpire = (conf["configExpire"] as? Double) ?? 0
        if expireAt > 0 && expireAt < now {
            completionHandler(TunnelError.licenseExpired)
            return
        }
        if configExpire > 0 && configExpire < now {
            completionHandler(TunnelError.configExpired)
            return
        }

        // 2. 规则
        let rulesText = (conf["rulesText"] as? String) ?? ""
        ruleSet = RuleSet.parse(text: rulesText)
        dnsIP = (conf["dnsIP"] as? String) ?? AppConfig.dnsProxyIP
        clientIP = (conf["clientIP"] as? String) ?? AppConfig.clientIP
        let mtu = (conf["mtu"] as? Int) ?? AppConfig.mtu

        // 3. 隧道网络参数：只接管规则 IP + DNS 代理地址，其它流量不碰
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
        dns.matchDomains = [""]           // 接管全部 DNS，命中再黑洞
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
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
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
        // 上面是从低字节取的，拼回来需要反向
        return parts.reversed().joined(separator: ".")
    }

    enum TunnelError: LocalizedError {
        case missingConfiguration
        case licenseExpired
        case configExpired

        var errorDescription: String? {
            switch self {
            case .missingConfiguration: return "缺少隧道配置，请重新激活"
            case .licenseExpired:       return "卡密已到期，请续费后重试"
            case .configExpired:        return "授权配置已过期，请重新激活"
            }
        }
    }
}
