import Foundation

/// 全局常量：服务端、隧道参数、品牌信息
enum AppConfig {

    static let appName        = "黑猫拦截 Pro"
    static let appVersion     = "1.0.3"
    static let buildNumber    = 105          // 1.0.3 build105（多套规则集名称下发 / 规则详情 / UI 优化）
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
    /// 域名黑洞落地地址：命中的域名解析到这里，
    /// 连接会进隧道当场被断掉（而不是让系统去连 0.0.0.0 干等超时）
    static let sinkholeIP     = "10.111.0.9"
    static let prefixLength   = 32
    static let mtu            = 1500

    /// 上游 DNS：阿里 / 腾讯 / 114，逐个回退
    static let upstreamDNS: [String] = ["223.5.5.5", "119.29.29.29", "114.114.114.114"]

    /// 云端配置包解密盐（参与密钥派生，改动会导致旧配置包失效）
    static let configSalt     = "HeiMao-Club-2026::cfg::v1"

    /// v3 加密通道主密钥（与服务端 storage/config.php 的 api_key 一致）
    /// 只用于包内，不参与任何界面展示；抓包只能拿到密文
    static let secureMasterKey = "ef60b1af85040f5c403ad712b1f2a1816b01c1461647b0f676b0f32cb5d1c2d9"

    /// 授权宽限期：在线校验窗口过期后，本地再容忍这么久（断网/抖动不误判）
    /// 注意：卡密被作废 / 到期时不走宽限，立即失效
    static let offlineGrace: TimeInterval = 10 * 60

    /// 心跳间隔：每 60 秒推一次在线校验窗口（服务端窗口 600 秒）
    static let heartbeatInterval: TimeInterval = 60

    /// 强校验间隔：隧道运行中每 5 分钟向服务端核对一次真实授权
    static let tunnelVerifyInterval: TimeInterval = 5 * 60

    /// 云端规则包密钥派生参数（必须与服务端 RulesService 一致）
    static let rulesSalt = "heimao-salt-v1"
    static let rulesInfo = "heimao-rules-v1"
}
