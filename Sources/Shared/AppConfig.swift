import Foundation

/// 全局常量：服务端、隧道参数、品牌信息
///
/// 与「地址 / 密钥 / 派生盐」相关的项都不以明文存在二进制里，
/// 统一从 Obfs 常量表按位还原（见 Obfs.swift，由 Tools/gen_obfs.py 生成）。
enum AppConfig {

    static let appName        = "黑猫拦截 Pro"
    static let appVersion     = "1.2.4"
    static let buildNumber    = 123          // 1.2.4 build123
    static let apiBase        = Obfs.join(0, 1)
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
    static let sinkholeIP     = Obfs.s(16)
    static let prefixLength   = 32
    static let mtu            = 1500

    /// 上游 DNS：阿里 / 腾讯 / 114，逐个回退
    static var upstreamDNS: [String] { [Obfs.s(17), Obfs.s(18), Obfs.s(19)] }

    /// 云端配置包解密盐（参与密钥派生，改动会导致旧配置包失效）
    static let configSalt     = Obfs.join(4, 5)

    /// v3 加密通道主密钥（与服务端 storage/config.php 的 api_key 一致）
    /// 两段分开存放，还原时才拼接；抓包只能拿到密文
    static let secureMasterKey = Obfs.join(2, 3)

    /// 授权宽限期：在线校验窗口过期后，本地再容忍这么久（断网/抖动不误判）
    /// 注意：卡密被作废 / 到期时不走宽限，立即失效
    ///
    /// 1.2.2：10 分钟 → 30 分钟。App 进后台会被 iOS 挂起，心跳必然断档；
    /// 以前 20 分钟后一回到前台就可能被判「窗口过期」直接停隧道 —— 这是
    /// 「挂后台就断」的主因之一。防护本身已经在跑，宽限期拉长不影响安全：
    /// 卡密被作废 / 到期走的是服务端明确结论，不经过宽限。
    static let offlineGrace: TimeInterval = 30 * 60

    /// 心跳间隔：前台每 90 秒推一次在线校验窗口（服务端窗口 600 秒）
    /// 1.2.2：60 → 90 秒。窗口 600 秒，90 秒一次有 6 次余量，省一半唤醒。
    static let heartbeatInterval: TimeInterval = 90

    /// 扩展内心跳：App 在后台被挂起之后，由隧道扩展继续续在线窗口。
    /// 这是「后台常驻」的关键 —— App 进程会被系统冻结，扩展不会。
    /// 服务端窗口 600 秒；后台在线判定 300 秒，这里 150 秒打一次，
    /// 中间容一次网络失败也不会从「在线设备」里掉出去。
    static let tunnelBeatInterval: TimeInterval = 150

    /// 扩展内强校验：真正问一次「卡密还能不能用」（比心跳重，间隔拉长）
    static let tunnelVerifyInterval: TimeInterval = 15 * 60

    /// 统计落盘间隔（App 读不到消息回包时的兜底快照）
    /// 1.2.2：2 秒 → 10 秒。后台每 2 秒写一次盘，累计 I/O 会拖垮扩展。
    static let statsPublishInterval: TimeInterval = 10

    /// 规则包 #PORT 段的开关（1.2.3）
    ///
    /// 端口段以前只解析、不参与判定。新 beta 规则里这一带有 2650 个端口，
    /// 其中包含 53 / 80 / 443 —— 直接按端口全网封会当场断网（连授权通道都走 443）。
    /// 所以做成用户可开可关，且无论开关如何，下面这几个端口永远不按端口封。
    static let corePorts: Set<Int> = [22, 53, 80, 123, 443, 853, 8080, 8443]

    /// 云端规则包密钥派生参数（必须与服务端 RulesService 一致）
    static let rulesSalt = Obfs.join(6, 7)
    static let rulesInfo = Obfs.join(8, 9)

    /* v4 通道（裸密文）：密钥派生标签与签名前缀，全部走混淆表 */
    static let v4InfoReq = Obfs.s(28)
    static let v4InfoRes = Obfs.s(29)
    static let v4AadReq  = Obfs.s(30)
    static let v4AadRes  = Obfs.s(31)
    static let v4SigTag  = Obfs.s(32)

    /* ── 1.2.4 防破解心跳 ─────────────────────────────────────────
       一条独立于卡密的小请求：只要「能连上验证站」就说明设备在正常网络里。
       拿不到结果（断网 / 被劫持 / 被改包后连不上）连续到阈值就按熔断处理。
       路径与间隔都在这里集中，方便以后调整。 */
    static let pulseRoute      = Obfs.s(34)
    static let burstRoute      = Obfs.s(35)
    /// 前台心跳间隔（秒）
    static let pulseInterval: TimeInterval = 25
    /// 冷启动宽限：这段时间内允许还没连上过（正常网络启动几乎立刻成功）
    /// 给到 120 秒是照顾首次安装 + 弱网；过了这段时间还连不上就开始计数
    static let pulseGrace: TimeInterval = 120
    /// 连续失败多少次判熔断（12 × 25s ≈ 5 分钟）
    static let pulseMaxFails = 12
    /// 2 的幂次微调：给每次请求加一点随机抖动，避免整批设备同一秒打进来
    static let pulseJitter: TimeInterval = 6
}
