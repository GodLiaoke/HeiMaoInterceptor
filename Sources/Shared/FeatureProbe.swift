import Foundation

/// 功能库校验
///
/// 一个功能一组 5 条 CRC，值全部取自「真实实现的输出」，不是写死的常量：
/// 算法被替换、常量被改、解析规则被放宽，CRC 必然对不上。
/// 客户端每次强校验把整组上报，服务端按「功能 + build」登记一条哈希逐条比对。
enum FeatureProbe {

    struct Item {
        let key: String
        let crcs: [UInt32]
    }

    private static let lock = NSLock()
    private static var cached: [Item] = []

    /// 全部功能（结果缓存：同一进程只算一次）
    static func all() -> [Item] {
        lock.lock()
        if !cached.isEmpty {
            let hit = cached
            lock.unlock()
            return hit
        }
        lock.unlock()

        let fresh: [Item] = [
            hashFunction(),
            hmacFunction(),
            ruleParse(),
            ruleMatch(),
            codeNormalise(),
            verdictTable(),
            builtinTables()
        ]

        lock.lock()
        cached = fresh
        lock.unlock()
        return fresh
    }

    /// 上报串：key:c1,c2,c3,c4,c5|key:...
    static var report: String {
        all().map { item in
            item.key + ":" + item.crcs.map { String($0) }.joined(separator: ",")
        }
        .joined(separator: "|")
    }

    /// 不联网时也能自查：本机算出来的组数
    static var featureCount: Int { all().count }

    // MARK: - CRC32

    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }

    private static func crc(_ s: String) -> UInt32 { crc32(Array(s.utf8)) }

    // MARK: - 功能探针

    /// 摘要算法：不同长度、中文、符号、长串
    private static func hashFunction() -> Item {
        let inputs = ["", "heimao", "黑猫拦截 Pro", "a-b_c|d/e", String(repeating: "x", count: 97)]
        return Item(key: "crypto.sha256", crcs: inputs.map { crc(CryptoBox.fingerprint($0)) })
    }

    /// 签名算法：空串、路径签名、中文、定长键
    private static func hmacFunction() -> Item {
        let pairs = [("", "k1"),
                     ("v3|auth/check|12345678", "hm"),
                     ("rule-pack", "heimao"),
                     ("黑猫", "K9"),
                     (String(repeating: "9", count: 64), "salt-中文")]
        return Item(key: "crypto.hmac", crcs: pairs.map { crc(CryptoBox.hmac($0.0, key: $0.1)) })
    }

    /// 规则解析：IP / CIDR / 域名 / 放行 / 端口段 / 坏行
    private static func ruleParse() -> Item {
        let sample = """
        #IP
        1.2.3.4
        10.0.0.0/8
        192.168.1.0/24
        #DOMAIN
        ads.example.com
        *.track.example.net
        @@||pass.example.org
        #PORT
        8080
        443-445
        not_a_rule
        """
        let set = RuleSet.parse(text: sample)
        return Item(key: "ruleset.parse", crcs: [
            crc("\(set.report.exactIPs)/\(set.report.cidrs)"),
            crc("\(set.report.domains)"),
            crc(set.domains.sorted().joined(separator: ",")),
            crc(set.ports.sorted().map { "\($0)" }.joined(separator: ",")),
            crc("\(set.report.direct)/\(set.report.skipped)")
        ])
    }

    /// 匹配：后缀命中、通配、放行优先、端口命中
    private static func ruleMatch() -> Item {
        let set = RuleSet.parse(text: """
        #DOMAIN
        ads.example.com
        *.track.example.net
        @@||pass.example.org
        #PORT
        8080
        """)
        let probes = [
            set.domains.contains("ads.example.com"),
            set.domains.count >= 3,
            set.ports.contains(8080),
            set.directDomains.contains("pass.example.org"),
            !set.domains.contains("nothing.example.com")
        ]
        return Item(key: "ruleset.match", crcs: probes.map { crc($0 ? "1" : "0") })
    }

    /// 卡密规范化：带符号、小写、带空格、长度不足、全符号
    private static func codeNormalise() -> Item {
        let inputs = ["ABCD-EF01-2345-6789",
                      "abcdef0123456789",
                      "  abcd ef01 2345 6789  ",
                      "1234",
                      "----////"]
        return Item(key: "license.code", crcs: inputs.map { crc(CryptoBox.normaliseCode($0)) })
    }

    /// 授权判定表：状态到「是否彻底失效」的映射
    private static func verdictTable() -> Item {
        let raw = ["ok", "no_card", "card_revoked", "card_expired", "window_expired"]
        return Item(key: "license.verdict", crcs: raw.map { name in
            guard let v = LicenseVerdict(rawValue: name) else { return crc("nil:" + name) }
            return crc("\(v.isHardFailure ? 1 : 0)\(v.isBlocking ? 1 : 0)")
        })
    }

    /// 内置常量表：地址、派生盐、黑洞地址被改会在这一组体现
    private static func builtinTables() -> Item {
        let parts = [Obfs.join(0, 1),
                     AppConfig.configSalt,
                     AppConfig.rulesSalt + AppConfig.rulesInfo,
                     AppConfig.sinkholeIP,
                     AppConfig.upstreamDNS.joined(separator: ",")]
        return Item(key: "core.const", crcs: parts.map { crc($0) })
    }
}
