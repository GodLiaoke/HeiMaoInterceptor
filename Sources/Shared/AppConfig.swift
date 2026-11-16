import Foundation

/// 全局常量：服务端、隧道参数、品牌信息
enum AppConfig {

    static let appName        = "黑猫公益拦截"
    static let apiBase        = "https://ios.ouovo.cc/api"
    static let channelURL     = "https://t.me/HeiMaoClub"
    static let channelName    = "@HeiMaoClub"

    static let appBundleID    = "com.heimao.interceptor"
    static let tunnelBundleID = "com.heimao.interceptor.tunnel"

    /// 设备码长度：服务端只接受 8 位纯数字，必须严格一致
    static let pinLength      = 8

    /// 隧道内部地址（与规则库解耦，只用于接管 DNS 与目标 IP）
    static let clientIP       = "10.111.0.2"
    static let dnsProxyIP     = "10.111.0.1"
    static let prefixLength   = 32
    static let mtu            = 1500

    /// 上游 DNS：阿里 / 腾讯 / 114，逐个回退
    static let upstreamDNS: [String] = ["223.5.5.5", "119.29.29.29", "114.114.114.114"]

    /// 云端配置包解密盐（参与密钥派生，改动会导致旧配置包失效）
    static let configSalt     = "HeiMao-Club-2026::cfg::v1"

    /// 授权宽限期：离线时本地授权最多再撑 6 小时
    static let offlineGrace: TimeInterval = 6 * 3600

    /// 心跳间隔
    static let heartbeatInterval: TimeInterval = 300

    /// 规则热更新地址（可选，失败不影响使用）
    static let remoteRulesURL = "https://raw.githubusercontent.com/GodLiaoke/HeiMaoInterceptor/main/Resources/Rules/rules.txt"
}
