import Foundation

/// 规则库：IP 段 / 域名 / 放行白名单
/// 文本格式与原版一致：
///   #IP      每行一个 IP 或 CIDR
///   #DOMAIN  每行一个域名（匹配本域及其全部子域）
///   #DIRECT  放行名单（优先命中）
///   #PORT    端口段（仅记录，不参与判定）
struct RuleSet {

    struct IPRange {
        let network: UInt32   // 主机序
        let mask: UInt32

        init?(_ raw: String) {
            let parts = raw.split(separator: "/")
            guard let base = RuleSet.ipToUInt(String(parts[0])) else { return nil }
            var bits = 32
            if parts.count == 2, let b = Int(parts[1]) { bits = max(0, min(32, b)) }
            let m: UInt32 = bits == 0 ? 0 : (0xFFFFFFFF << UInt32(32 - bits)) & 0xFFFFFFFF
            network = base & m
            mask = m
        }

        func contains(_ ip: UInt32) -> Bool { (ip & mask) == network }
    }

    private(set) var ipRanges: [IPRange] = []
    private(set) var domains: Set<String> = []
    private(set) var directDomains: Set<String> = []
    private(set) var portSpecs: [String] = []

    var isEmpty: Bool { ipRanges.isEmpty && domains.isEmpty }

    /// 摘要，用于 UI 显示
    var summary: (ips: Int, domains: Int) { (ipRanges.count, domains.count) }

    // MARK: - 解析

    static func parse(text: String) -> RuleSet {
        var rs = RuleSet()
        var section = ""
        text.enumerateLines { line, _ in
            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return }
            if raw.hasPrefix("#") || raw.hasPrefix("//") || raw.hasPrefix(";") {
                // 可能是段标记，也可能只是注释
                let upper = raw.uppercased()
                if upper.hasPrefix("#IP") && raw.count <= 6 { section = "ip"; return }
                if upper.hasPrefix("#DOMAIN") { section = "domain"; return }
                if upper.hasPrefix("#DIRECT") { section = "direct"; return }
                if upper.hasPrefix("#PORT") { section = "port"; return }
                return
            }
            switch section {
            case "ip":
                if let r = IPRange(raw) { rs.ipRanges.append(r) }
            case "domain":
                rs.domains.insert(normalise(raw))
            case "direct":
                rs.directDomains.insert(normalise(raw))
            case "port":
                rs.portSpecs.append(raw)
            default:
                if let r = IPRange(raw) { rs.ipRanges.append(r) }
            }
        }
        return rs
    }

    private static func normalise(_ s: String) -> String {
        var v = s.lowercased().trimmingCharacters(in: .whitespaces)
        while v.hasPrefix("*.") { v.removeFirst(2) }
        while v.hasPrefix(".") { v.removeFirst() }
        if v.hasSuffix(".") { v.removeLast() }
        return v
    }

    static func ipToUInt(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var v: UInt32 = 0
        for p in parts {
            guard let n = UInt32(p), n <= 255 else { return nil }
            v = (v << 8) | n
        }
        return v
    }

    // MARK: - 判定

    func isIPBlocked(_ ip: UInt32) -> Bool {
        for r in ipRanges where r.contains(ip) { return true }
        return false
    }

    func isIPBlocked(_ dotted: String) -> Bool {
        guard let v = RuleSet.ipToUInt(dotted) else { return false }
        return isIPBlocked(v)
    }

    /// 精确 + 子域匹配：blocked 里含 "qq.com" 则 "a.b.qq.com" 命中
    func isDomainBlocked(_ domain: String) -> Bool {
        let d = RuleSet.normalise(domain)
        if d.isEmpty { return false }
        if matches(d, in: directDomains) { return false }
        return matches(d, in: domains)
    }

    private func matches(_ d: String, in set: Set<String>) -> Bool {
        if set.isEmpty { return false }
        if set.contains(d) { return true }
        var cursor = d
        while let dot = cursor.firstIndex(of: ".") {
            cursor = String(cursor[cursor.index(after: dot)...])
            if set.contains(cursor) { return true }
        }
        return false
    }

    /// 导出隧道需要的路由列表（不含 0.0.0.0/0，避免误伤正常流量）
    func includedRoutes() -> [(String, Int)] {
        ipRanges.map { (RuleSet.uintToIP($0.network), prefixOf($0.mask)) }
    }

    private func prefixOf(_ mask: UInt32) -> Int {
        var m = mask, bits = 0
        while m != 0 { bits += 1; m <<= 1 }
        return bits
    }

    static func uintToIP(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }
}
