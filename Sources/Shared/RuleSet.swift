import Foundation

/// 规则库：按 ACE 3.0 的数据契约定标（IP / 域名 / 端口 三段 + 状态机解析）
///
/// 解析规则（与 ACE 的 Rules.parse 逐条对齐）：
///   1. 段头：去掉行首 `#` / `//` / `;`，trim，转大写，
///      以 `IP` 开头进 IP 段；以 `DOMAIN` / `域名` 开头进域名段；
///      以 `PORT` / `端口` 开头进端口段；其余注释行不切段
///   2. 第一个段头之前的所有行一律丢弃
///   3. IP 行：`A.B.C.D` | `A.B.C.D/N` | `A.B.C.D:端口` | `A.B.C.D:起-止`，
///      逗号后缀 `,DIRECT` / `,ALLOW` 表示放行，其余一律当拦截
///   4. 域名行：去 `,DIRECT` → 转小写 → 去 http(s):// → 第一个 `/` 截断 → 去行首的点
///   5. 端口行：只入集合，不参与判定（与原版一致）
///
/// 兼容层：老格式（hosts / dnsmasq / AdGuard）照旧认得，避免历史规则包解析成空。
///
/// 匹配上：
///   - /32 且不限端口的走 Set 精确命中
///   - 其余前缀 / 带端口规则线性扫（规则集只有几百条，够快）
///   - 域名逐级后缀命中（写 a.com 等于 *.a.com）
struct RuleSet {

    // MARK: - 报告 / 规则模型

    struct ParseReport {
        var exactIPs = 0
        var cidrs    = 0
        var domains  = 0
        var direct   = 0
        var ports    = 0
        var skipped  = 0
        var routes   = 0

        var summaryText: String {
            "\(exactIPs + cidrs) IP · \(domains) 域名 · \(ports) 端口"
        }
    }

    struct IPRule {
        let base: UInt32
        let prefix: Int
        let portFrom: Int        // -1 = 不限端口
        let portTo: Int
        let direct: Bool
    }

    private enum Section: Equatable {
        case none, ip, domain, port
    }

    // MARK: - 解析结果

    private(set) var ipRules: [IPRule] = []
    private(set) var domains: Set<String> = []
    private(set) var directDomains: Set<String> = []
    private(set) var ports: Set<Int> = []
    private(set) var portRanges: [(from: Int, to: Int)] = []
    private(set) var report = ParseReport()

    /// 派生索引
    private var exact32: Set<UInt32> = []
    private var prefixRules: [IPRule] = []
    private var directRules: [IPRule] = []

    /// 隧道路由（只收「非放行 + 不限端口」的规则，与原版 buildRoutes 一致）
    private(set) var routes: [(String, Int)] = []

    var isEmpty: Bool { ipRules.isEmpty && domains.isEmpty }

    var summary: (ips: Int, domains: Int) {
        (report.exactIPs + report.cidrs, domains.count)
    }

    // MARK: - 解析入口

    static func parse(text: String) -> RuleSet {
        var rs = RuleSet()
        let lines = text.components(separatedBy: .newlines)

        var hasHeader = false
        for line in lines where sectionHeader(line) != nil {
            hasHeader = true
            break
        }

        var section: Section = .none
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let head = sectionHeader(raw) {
                section = head
                continue
            }
            if line.hasPrefix("#") || line.hasPrefix("//")
                || line.hasPrefix(";") || line.hasPrefix("!") { continue }

            let body = stripInlineComment(line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { continue }

            /* 老规则包没有段头：按行首特征自动判类型，别整包丢掉 */
            let effective = hasHeader ? section : sniff(body)
            if effective == .none { continue }      // 第一个段头之前：丢弃

            switch effective {
            case .ip:     rs.addIpLine(body)
            case .domain: rs.addDomainLine(body)
            case .port:   rs.addPortLine(body)
            case .none:   break
            }
        }

        rs.rebuild()
        return rs
    }

    /// 段头识别：先剥 # / // / ;，再按 startsWith 判（`#IPLIST` 也算段头）
    private static func sectionHeader(_ raw: String) -> Section? {
        var t = raw.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return nil }
        if t.hasPrefix("//") {
            t.removeFirst(2)
        } else if first == "#" || first == ";" {
            t.removeFirst()
        } else {
            return nil
        }
        t = t.trimmingCharacters(in: .whitespaces)
        let u = t.uppercased()
        if u.hasPrefix("IP") { return .ip }
        if u.hasPrefix("DOMAIN") || u.hasPrefix("域名") { return .domain }
        if u.hasPrefix("PORT") || u.hasPrefix("端口") { return .port }
        return nil
    }

    /// 无段头时的类型嗅探
    private static func sniff(_ line: String) -> Section {
        let head = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? line
        if head.contains("/") && head.contains(".") && (ipToUInt(String(head.split(separator: "/")[0])) != nil) {
            return .ip
        }
        if ipToUInt(baseOf(head)) != nil { return .ip }
        if head.allSatisfy({ $0.isNumber || $0 == "-" }) { return .port }
        return .domain
    }

    /// 去掉端口 / 前缀后的地址部分
    private static func baseOf(_ token: String) -> String {
        var t = token
        if let slash = t.firstIndex(of: "/") { t = String(t[t.startIndex..<slash]) }
        if let colon = t.lastIndex(of: ":"), !t.contains("::") {
            t = String(t[t.startIndex..<colon])
        }
        return t
    }

    /// 行尾注释：`#` 前必须有空白，避免切坏 `#IP` 之外的正常内容
    private static func stripInlineComment(_ line: String) -> String {
        guard let range = line.range(of: " #") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }

    // MARK: - IP 行

    private mutating func addIpLine(_ line: String) {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

        /* hosts：`0.0.0.0 a.com` 拦截，`127.0.0.1 a.com` 放行 */
        if tokens.count > 1, let head = RuleSet.ipToUInt(tokens[0]),
           head == 0 || head == 0x7F00_0001 {
            for token in tokens.dropFirst() {
                insertDomain(token, direct: head == 0x7F00_0001)
            }
            return
        }

        guard let rule = RuleSet.parseIpRule(line) else {
            /* 段里混进来的域名 / AdGuard 写法：按兼容层再试一次 */
            if !compatAbsorb(line, allowDirect: true) { report.skipped += 1 }
            return
        }
        ipRules.append(rule)
    }

    static func parseIpRule(_ raw: String) -> IPRule? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        var direct = false
        if let comma = text.firstIndex(of: ",") {
            let suffix = String(text[text.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces).uppercased()
            text = String(text[text.startIndex..<comma])
                .trimmingCharacters(in: .whitespaces)
            if suffix == "DIRECT" || suffix == "ALLOW" { direct = true }
        }

        var portFrom = -1
        var portTo = -1
        if let colon = text.lastIndex(of: ":"), !text.contains("::") {
            let portText = String(text[text.index(after: colon)])
                .trimmingCharacters(in: .whitespaces)
            text = String(text[text.startIndex..<colon])
            if !portText.isEmpty, portText.allSatisfy({ $0.isNumber || $0 == "-" }) {
                if portText.contains("-") {
                    let parts = portText.split(separator: "-")
                    if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]),
                       a > 0, b >= a, b <= 65535 {
                        portFrom = a
                        portTo = b
                    }
                } else if let p = Int(portText), p > 0, p <= 65535 {
                    portFrom = p
                    portTo = p
                }
            }
            /* 端口写坏了（`1.2.3.4:` / `:abc`）当不限端口处理，等价于原版的「全端口」 */
        }

        var prefix = 32
        if let slash = text.firstIndex(of: "/") {
            let bits = String(text[text.index(after: slash)])
            text = String(text[text.startIndex..<slash])
            guard let b = Int(bits), b >= 0, b <= 32 else { return nil }
            prefix = b
        }

        guard let base = ipToUInt(text) else { return nil }
        return IPRule(base: base, prefix: prefix,
                      portFrom: portFrom, portTo: portTo, direct: direct)
    }

    // MARK: - 域名行

    private mutating func addDomainLine(_ line: String) {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)

        if tokens.count > 1, let head = RuleSet.ipToUInt(tokens[0]),
           head == 0 || head == 0x7F00_0001 {
            for token in tokens.dropFirst() {
                insertDomain(token, direct: head == 0x7F00_0001)
            }
            return
        }

        /* dnsmasq：address=/example.com/0.0.0.0 */
        if line.lowercased().hasPrefix("address=") {
            var touched = false
            for part in line.split(separator: "/") {
                let s = String(part)
                if s.contains("."), RuleSet.ipToUInt(s) == nil {
                    insertDomain(s, direct: false)
                    touched = true
                }
            }
            if touched { return }
        }

        guard let parsed = RuleSet.parseDomain(line) else {
            report.skipped += 1
            return
        }
        insertDomain(parsed.0, direct: parsed.1)
    }

    static func parseDomain(_ raw: String) -> (String, Bool)? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        var direct = false
        if let comma = t.firstIndex(of: ",") {
            let suffix = String(t[t.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces).uppercased()
            t = String(t[t.startIndex..<comma])
            if suffix == "DIRECT" || suffix == "ALLOW" { direct = true }
        }

        /* 老格式的放行标记：@@||x^ */
        if t.hasPrefix("@@") { direct = true; t.removeFirst(2) }
        while t.hasPrefix("|") { t.removeFirst() }
        while t.hasPrefix("*.") { t.removeFirst(2) }

        t = t.lowercased()
        if t.hasPrefix("https://") { t.removeFirst(8) }
        else if t.hasPrefix("http://") { t.removeFirst(7) }
        while t.hasPrefix(".") { t.removeFirst() }
        while t.hasSuffix("^") || t.hasSuffix("|") || t.hasSuffix("*") { t.removeLast() }

        if let slash = t.firstIndex(of: "/") { t = String(t[t.startIndex..<slash]) }
        while t.hasPrefix(".") { t.removeFirst() }
        while t.hasSuffix(".") { t.removeLast() }

        guard isValidDomain(t) else { return nil }
        return (t, direct)
    }

    // MARK: - 端口行

    private mutating func addPortLine(_ line: String) {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("-") {
            let parts = t.split(separator: "-")
            if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]),
               a > 0, b >= a, b <= 65535 {
                portRanges.append((from: a, to: b))
                if b - a <= 2000 {
                    for p in a...b { ports.insert(p) }
                }
                return
            }
        }
        if let p = Int(t), p > 0, p <= 65535 {
            ports.insert(p)
            return
        }
        report.skipped += 1
    }

    // MARK: - 兼容层（老规则包）

    @discardableResult
    private mutating func compatAbsorb(_ line: String, allowDirect: Bool) -> Bool {
        var t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@@") {
            guard allowDirect else { return false }
            t.removeFirst(2)
            while t.hasPrefix("|") { t.removeFirst() }
            guard let d = RuleSet.parseDomain(t) else { return false }
            insertDomain(d.0, direct: true)
            return true
        }
        if t.hasPrefix("||") { t.removeFirst(2) }
        while t.hasPrefix("|") { t.removeFirst() }
        guard let d = RuleSet.parseDomain(t) else { return false }
        insertDomain(d.0, direct: d.1)
        return true
    }

    // MARK: - 写入口（去重 + 放行优先）

    private mutating func insertDomain(_ raw: String, direct: Bool) {
        guard let d = RuleSet.parseDomain(raw) else {
            report.skipped += 1
            return
        }
        let name = d.0
        guard !name.isEmpty else { return }
        if direct || d.1 {
            directDomains.insert(name)
            domains.remove(name)
        } else if !directDomains.contains(name) {
            domains.insert(name)
        }
    }

    private static func isValidDomain(_ s: String) -> Bool {
        guard s.count >= 3, s.count <= 253, s.contains(".") else { return false }
        guard !s.contains(" ") else { return false }
        let ok = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyz0123456789-._").isSuperset(of: CharacterSet(charactersIn: s))
        return ok
    }

    // MARK: - 索引重建

    private mutating func rebuild() {
        exact32.removeAll()
        prefixRules.removeAll()
        directRules.removeAll()
        routes.removeAll()

        var ranges: [(UInt32, UInt32)] = []

        for rule in ipRules {
            if rule.direct {
                directRules.append(rule)
                continue
            }
            if rule.prefix == 32 && rule.portFrom < 0 {
                exact32.insert(rule.base)
            } else {
                prefixRules.append(rule)
            }
            /* 路由只收不限端口的规则：带端口的 IP 在原版里也不进路由 */
            if rule.portFrom < 0 {
                let mask = RuleSet.mask(for: rule.prefix)
                let start = rule.base & mask
                let end = start | ~mask
                ranges.append((start, end))
            }
        }

        routes = RuleSet.cidrs(from: RuleSet.mergeRanges(ranges))

        var rep = ParseReport()
        rep.exactIPs = exact32.count
        rep.cidrs = prefixRules.count
        rep.domains = domains.count
        rep.direct = directDomains.count + directRules.count
        rep.ports = ports.count
        rep.routes = routes.count
        rep.skipped = report.skipped
        report = rep
    }

    // MARK: - 合并（内置规则 + 云端规则）

    func merging(_ other: RuleSet) -> RuleSet {
        var out = RuleSet()
        out.ipRules = ipRules + other.ipRules
        out.directDomains = directDomains.union(other.directDomains)
        out.domains = domains.union(other.domains).subtracting(out.directDomains)
        out.ports = ports.union(other.ports)
        out.portRanges = portRanges + other.portRanges
        out.report.skipped = report.skipped + other.report.skipped
        out.rebuild()
        return out
    }

    // MARK: - 判定

    private static func mask(for prefix: Int) -> UInt32 {
        prefix <= 0 ? 0 : ((0xFFFF_FFFF << UInt32(32 - min(32, prefix))) & 0xFFFF_FFFF)
    }

    private static func matchIp(_ rule: IPRule, _ ip: UInt32) -> Bool {
        if rule.prefix >= 32 { return rule.base == ip }
        let m = mask(for: rule.prefix)
        return (ip & m) == (rule.base & m)
    }

    private static func matchPort(_ rule: IPRule, _ port: Int) -> Bool {
        if rule.portFrom < 0 { return true }
        return port >= rule.portFrom && port <= rule.portTo
    }

    /// 放行优先，再查拦截（与原版 isBlockedIp 同序）
    func isBlockedIp(_ ip: UInt32, port: Int) -> Bool {
        for rule in directRules where RuleSet.matchPort(rule, port) {
            if RuleSet.matchIp(rule, ip) { return false }
        }
        if exact32.contains(ip) { return true }
        for rule in prefixRules where RuleSet.matchPort(rule, port) {
            if RuleSet.matchIp(rule, ip) { return true }
        }
        return false
    }

    func isBlockedIp(_ ip: UInt32) -> Bool { isBlockedIp(ip, port: 0) }

    func isBlockedIp(_ dotted: String) -> Bool {
        guard let v = RuleSet.ipToUInt(dotted) else { return false }
        return isBlockedIp(v)
    }

    /// 隧道每个包走这里
    func shouldBlock(ip: UInt32, port: UInt16) -> Bool {
        isBlockedIp(ip, port: Int(port))
    }

    /// 端口集合只保留、不参与判定（与原版一致：1953 条一条都不生效）
    func isPortBlocked(_ port: UInt16) -> Bool {
        !ports.isEmpty && ports.contains(Int(port))
    }

    /// 域名：放行优先，再逐级后缀命中（写 a.com 等于 *.a.com，但不是裸 endsWith）
    func isBlockedDomain(_ host: String) -> Bool {
        var h = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while h.hasPrefix(".") { h.removeFirst() }
        while h.hasSuffix(".") { h.removeLast() }
        if h.isEmpty { return false }
        if matches(h, in: directDomains) { return false }
        return matches(h, in: domains)
    }

    private func matches(_ host: String, in set: Set<String>) -> Bool {
        if set.isEmpty { return false }
        if set.contains(host) { return true }
        var cursor = host
        while let dot = cursor.firstIndex(of: ".") {
            cursor = String(cursor[cursor.index(after: dot)...])
            if set.contains(cursor) { return true }
        }
        return false
    }

    // MARK: - 路由规划

    /// 隧道路由方案
    ///
    /// 1.1.0 起改成「只接管规则段」的窄口模型：
    ///   included = 规则里的 IP 段 + 假 DNS 的 /32，不做 0.0.0.0/0 全接管，
    ///   也不生成补集例外。非规则流量压根不进隧道，不存在「补集装不下就降级」。
    struct RoutePlan {
        var included: [(String, Int)] = []
        var excluded: [(String, Int)] = []
        /// 保留字段：老逻辑的全接管方案，1.1.0 不再产生
        var hijackAll = false
        /// true = 连规则段都没接管上（只有 DNS）
        var degraded = false

        var routeCount: Int { included.count + excluded.count }

        var description: String {
            if degraded { return "DNS 接管 · 无 IP 路由" }
            return "规则接管 · 路由 \(included.count) 条"
        }
    }

    /// - Parameter forceInside: 必须留在隧道里的地址（假 DNS 等），补成 /32
    /// - Parameter maxRoutes: 超过这个条数就按 /24 → /20 合并，避免设置装不下
    func routePlan(forceInside: [UInt32] = [], maxRoutes: Int = 6000,
                   coarsenTo bits: Int = 32) -> RoutePlan {
        var plan = RoutePlan()

        var included: [(String, Int)] = bits < 32 ? RuleSet.aggregate(routes, to: bits) : routes
        if included.count > maxRoutes {
            included = RuleSet.aggregate(routes, to: 24)
            if included.count > maxRoutes { included = RuleSet.aggregate(routes, to: 20) }
            if included.count > maxRoutes { included = RuleSet.aggregate(routes, to: 16) }
        }

        var seen = Set<String>()
        for item in included {
            let key = "\(item.0)/\(item.1)"
            if seen.insert(key).inserted {
                plan.included.append(item)
            }
        }
        for ip in forceInside {
            let dotted = RuleSet.uintToIP(ip)
            let key = "\(dotted)/32"
            if seen.insert(key).inserted {
                plan.included.append((dotted, 32))
            }
        }

        if plan.included.isEmpty { plan.degraded = true }
        return plan
    }

    /// 把 CIDR 列表按更大的粒度合并（规则段挨得近时合并，条数就下来了）
    private static func aggregate(_ list: [(String, Int)], to bits: Int) -> [(String, Int)] {
        var ranges: [(UInt32, UInt32)] = []
        for item in list {
            guard let base = ipToUInt(item.0) else { continue }
            let mask = mask(for: item.1)
            ranges.append((base & mask, (base & mask) | ~mask))
        }
        guard !ranges.isEmpty else { return list }
        let step = UInt64(1) << UInt64(32 - bits)
        var coarse: [(UInt32, UInt32)] = []
        for (s, e) in ranges {
            let a = UInt64(s) / step * step
            let b = min(UInt64(UInt32.max), (UInt64(e) / step + 1) * step - 1)
            coarse.append((UInt32(a), UInt32(b)))
        }
        return cidrs(from: mergeRanges(coarse))
    }

    static func mergeRanges(_ list: [(UInt32, UInt32)]) -> [(UInt32, UInt32)] {
        guard !list.isEmpty else { return [] }
        let sorted = list.sorted { $0.0 < $1.0 }
        var out: [(UInt32, UInt32)] = []
        var curStart = sorted[0].0
        var curEnd = sorted[0].1
        for (s, e) in sorted.dropFirst() {
            let adjacent = curEnd != UInt32.max && UInt64(s) <= UInt64(curEnd) + 1
            if s <= curEnd || adjacent {
                if e > curEnd { curEnd = e }
            } else {
                out.append((curStart, curEnd))
                curStart = s
                curEnd = e
            }
        }
        out.append((curStart, curEnd))
        return out
    }

    /// 区间 → CIDR（每块都是 2^n 对齐的最小集合，不会多覆盖一个地址）
    static func cidrs(from ranges: [(UInt32, UInt32)]) -> [(String, Int)] {
        var out: [(String, Int)] = []
        for (start, end) in ranges {
            var s = UInt64(start)
            let e = UInt64(end)
            while s <= e {
                var alignSize = 32
                if s != 0 {
                    alignSize = 0
                    while alignSize < 32 && (s & (UInt64(1) << UInt64(alignSize))) == 0 {
                        alignSize += 1
                    }
                }
                let span = e - s + 1
                var spanSize = 0
                while spanSize < 32 && (UInt64(1) << UInt64(spanSize + 1)) <= span {
                    spanSize += 1
                }
                let size = min(alignSize, spanSize)
                out.append((uintToIP(UInt32(s)), 32 - size))
                s += (UInt64(1) << UInt64(size))
                if size == 32 { break }
            }
        }
        return out
    }

    // MARK: - 地址工具

    static func ipToUInt(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var value: UInt32 = 0
        for part in parts {
            guard part.count <= 3, let n = UInt32(part), n <= 255 else { return nil }
            value = (value << 8) | n
        }
        return value
    }

    static func uintToIP(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }
}
