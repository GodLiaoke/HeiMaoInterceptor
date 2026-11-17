import Foundation

/// 规则库：IP / 域名 / 端口 / 放行白名单
///
/// 解析上尽量宽松，别人给的规则文件拿来就能用：
///
///   `#IP` / `#DOMAIN` / `#DIRECT` / `#PORT` 分段标记（原生格式）
///   纯 IP、CIDR：`1.2.3.4`、`1.2.3.0/24`
///   hosts：`0.0.0.0 example.com`（127.0.0.1 归到放行）
///   dnsmasq：`address=/example.com/0.0.0.0`
///   AdGuard／通用订阅：`||example.com^`、`@@||example.com^`、`|https://example.com`
///   带端口：`1.2.3.4:8080`、`example.com:443`（拆成目标和端口）
///   一行多项（空格 / 逗号分隔）、行尾注释、`!` 注释、通配符 `*.` `*` `^` `|`
///
/// 匹配上做了两件事，规则涨到几万条也不会拖慢转发：
///   - IP 段在解析时就合并成互不相交的有序区间，查命中走二分
///   - 精确 IP 走 Set，域名走逐级后缀查 Set
struct RuleSet {

    // MARK: - 解析结果

    struct ParseReport {
        var exactIPs = 0
        var cidrs    = 0
        var domains  = 0
        var direct   = 0
        var ports    = 0
        var skipped  = 0

        var summaryText: String {
            "\(exactIPs + cidrs) IP · \(domains) 域名 · \(ports) 端口"
        }
    }

    /// 合并后的地址区间（闭区间，按 start 升序且互不相交）
    private struct Segment {
        let start: UInt32
        let end: UInt32
    }

    private(set) var exactIPs: Set<UInt32> = []
    private var segments: [Segment] = []
    private(set) var domains: Set<String> = []
    private(set) var directDomains: Set<String> = []
    private(set) var ports: Set<Int> = []
    private(set) var portSpecs: [String] = []
    private(set) var report = ParseReport()

    var isEmpty: Bool {
        exactIPs.isEmpty && segments.isEmpty && domains.isEmpty
    }

    /// 摘要，用于 UI 显示
    var summary: (ips: Int, domains: Int) {
        (report.exactIPs + report.cidrs, domains.count)
    }

    // MARK: - 解析

    static func parse(text: String) -> RuleSet {
        var rs = RuleSet()
        var section = ""
        var cidrList: [(UInt32, UInt32)] = []

        text.enumerateLines { line, _ in
            let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.isEmpty { return }

            // 分段标记（只有短行才当标记，避免把长注释误判成段头）
            if raw.hasPrefix("#") {
                let head = raw.uppercased()
                if head.hasPrefix("#IP"), raw.count <= 8 { section = "ip"; return }
                if head.hasPrefix("#DOMAIN"), raw.count <= 14 { section = "domain"; return }
                if head.hasPrefix("#DIRECT"), raw.count <= 14 { section = "direct"; return }
                if head.hasPrefix("#PORT"), raw.count <= 10 { section = "port"; return }
                return
            }
            if raw.hasPrefix("!") || raw.hasPrefix(";") || raw.hasPrefix("//") { return }

            let body = stripInlineComment(raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { return }

            let tokens = splitTokens(body)

            /* hosts 格式：0.0.0.0 x.com 是拦截，127.0.0.1 x.com 是放行 */
            if tokens.count > 1, let head = RuleSet.ipToUInt(tokens[0]),
               head == 0 || head == 0x7F000001 {
                let isDirectHost = (head == 0x7F000001)
                for token in tokens.dropFirst() {
                    rs.insertDomain(token, direct: isDirectHost)
                }
                return
            }

            for token in tokens {
                rs.absorb(token, section: section, cidrList: &cidrList)
            }
        }

        rs.segments = merge(cidrList)
        rs.report.cidrs = cidrList.count
        return rs
    }

    /// 去掉行尾注释（`#` 前必须有空白，避免切坏 `#IP` 之外的正常内容）
    private static func stripInlineComment(_ line: String) -> String {
        guard let range = line.range(of: " #") else { return line }
        return String(line[line.startIndex..<range.lowerBound])
    }

    /// 一行多项：空格 / Tab / 逗号
    private static func splitTokens(_ line: String) -> [String] {
        line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private mutating func absorb(_ token: String,
                                 section: String,
                                 cidrList: inout [(UInt32, UInt32)]) {
        let t0 = token.trimmingCharacters(in: CharacterSet(charactersIn: " "))

        // 通配 / 注解符号先剥掉
        var t = t0
        var isDirect = false
        if t.hasPrefix("@@") { isDirect = true; t.removeFirst(2) }
        if t.hasPrefix("||") { t.removeFirst(2) }
        while t.hasPrefix("|") || t.hasPrefix("*") || t.hasPrefix(".") {
            t.removeFirst()
        }
        while t.hasSuffix("^") || t.hasSuffix("|") || t.hasSuffix("*") || t.hasSuffix(".") {
            t.removeLast()
        }

        // 正则类规则直接跳过
        if t.hasPrefix("/") || t.hasPrefix("[") { report.skipped += 1; return }

        // 单独出现的 0.0.0.0 / 127.0.0.1 只是 hosts 的前导地址，不是规则
        if let ip = RuleSet.ipToUInt(t0), ip == 0 || ip == 0x7F000001 {
            return
        }

        // dnsmasq: address=/example.com/0.0.0.0
        if t.lowercased().hasPrefix("address=") {
            let parts = t.split(separator: "/")
            for part in parts {
                let s = String(part)
                if s.contains("."), RuleSet.ipToUInt(s) == nil {
                    insertDomain(s, direct: false)
                }
            }
            return
        }

        // 带端口
        var hostPart = t
        var port: Int?
        if let colon = t.lastIndex(of: ":"),
           !t.contains("::"),                       // 排除 IPv6
           let p = Int(t[t.index(after: colon)...]), p > 0, p <= 65535 {
            hostPart = String(t[t.startIndex..<colon])
            port = p
        }
        if let p = port, !hostPart.isEmpty, hostPart.contains(".") {
            ports.insert(p)
            portSpecs.append("\(hostPart):\(p)")
            report.ports += 1
        }

        // 端口段
        if section == "port" || (port == nil && isPortOnly(t)) {
            if let p = Int(t), p > 0, p <= 65535 {
                ports.insert(p)
                portSpecs.append(t)
                report.ports += 1
                return
            }
            // 端口范围 1000-2000
            let parts = t.split(separator: "-")
            if parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]), a <= b, b <= 65535 {
                var v = a
                while v <= b && ports.count < 4096 {
                    ports.insert(v); v += 1
                }
                portSpecs.append(t)
                report.ports += 1
                return
            }
        }

        // IP / CIDR
        if section != "domain" {
            if let cidr = RuleSet.parseCIDR(hostPart) {
                cidrList.append(cidr)
                return
            }
            if let ip = RuleSet.ipToUInt(hostPart) {
                exactIPs.insert(ip)
                report.exactIPs += 1
                return
            }
        }

        // 域名
        if hostPart.contains(".") || section == "domain" || section == "direct" {
            let d = RuleSet.normalise(hostPart)
            guard RuleSet.isValidDomain(d) else { report.skipped += 1; return }
            insertDomain(d, direct: isDirect || section == "direct")
            return
        }

        report.skipped += 1
    }

    private mutating func insertDomain(_ raw: String, direct: Bool) {
        let d = RuleSet.normalise(raw)
        guard RuleSet.isValidDomain(d) else { report.skipped += 1; return }
        if direct {
            directDomains.insert(d); report.direct += 1
        } else {
            domains.insert(d); report.domains += 1
        }
    }

    private func isPortOnly(_ s: String) -> Bool {
        guard !s.isEmpty, s.allSatisfy({ $0.isNumber || $0 == "-" }) else { return false }
        return Int(s) != nil || s.contains("-")
    }

    private static func isValidDomain(_ s: String) -> Bool {
        guard s.count >= 3, s.count <= 253, s.contains(".") else { return false }
        guard !s.contains(" ") else { return false }
        // 允许字母数字、连字符、下划线、点；中文等交给系统转 IDN 后再说
        let ok = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyz0123456789-._").isSuperset(of: CharacterSet(charactersIn: s))
        return ok
    }

    private static func parseCIDR(_ s: String) -> (UInt32, UInt32)? {
        guard s.contains("/") else { return nil }
        let parts = s.split(separator: "/")
        guard parts.count == 2,
              let base = ipToUInt(String(parts[0])),
              let bits = Int(parts[1]), bits >= 0, bits <= 32 else { return nil }
        let mask: UInt32 = bits == 0 ? 0 : (0xFFFFFFFF << UInt32(32 - bits)) & 0xFFFFFFFF
        let network = base & mask
        let broadcast = network | ~mask
        return (network, broadcast)
    }

    /// 区间合并：重叠 / 相邻的段并成一个，之后二分才成立
    private static func merge(_ list: [(UInt32, UInt32)]) -> [Segment] {
        guard !list.isEmpty else { return [] }
        let sorted = list.sorted { $0.0 < $1.0 }
        var out: [Segment] = []
        var curStart = sorted[0].0
        var curEnd = sorted[0].1
        for (s, e) in sorted.dropFirst() {
            let adjacent = curEnd != UInt32.max ? (s == curEnd + 1) : false
            if s <= curEnd || adjacent {
                if e > curEnd { curEnd = e }
            } else {
                out.append(Segment(start: curStart, end: curEnd))
                curStart = s; curEnd = e
            }
        }
        out.append(Segment(start: curStart, end: curEnd))
        return out
    }

    private static func normalise(_ s: String) -> String {
        var v = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // 订阅里常见的注解符号：@@||x^ / |x| / *.x
        while v.hasPrefix("@@") || v.hasPrefix("||") || v.hasPrefix("|")
                || v.hasPrefix("*.") || v.hasPrefix(".") {
            if v.hasPrefix("@@") || v.hasPrefix("||") { v.removeFirst(2) }
            else { v.removeFirst() }
        }
        while v.hasSuffix("^") || v.hasSuffix("|") || v.hasSuffix("*") { v.removeLast() }
        if v.hasSuffix(".") { v.removeLast() }
        // 常见前缀噪声
        for junk in ["https://", "http://", "www."] where v.hasPrefix(junk) {
            v.removeFirst(junk.count)
        }
        if let slash = v.firstIndex(of: "/") { v = String(v[v.startIndex..<slash]) }
        if let colon = v.firstIndex(of: ":") { v = String(v[v.startIndex..<colon]) }
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
        if exactIPs.contains(ip) { return true }
        guard !segments.isEmpty else { return false }
        // 二分：找最后一个 start <= ip 的区间
        var lo = 0, hi = segments.count - 1, hit = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if segments[mid].start <= ip {
                hit = mid; lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        guard hit >= 0 else { return false }
        return ip <= segments[hit].end
    }

    func isIPBlocked(_ dotted: String) -> Bool {
        guard let v = RuleSet.ipToUInt(dotted) else { return false }
        return isIPBlocked(v)
    }

    /// 端口命中（规则里显式给了端口才参与判定）
    func isPortBlocked(_ port: UInt16) -> Bool {
        !ports.isEmpty && ports.contains(Int(port))
    }

    /// 隧道每个包走这里：IP 优先，纯端口规则库再按端口判
    func shouldBlock(ip: UInt32, port: UInt16) -> Bool {
        if isIPBlocked(ip) { return true }
        guard !ports.isEmpty else { return false }
        // 有 IP 规则时，端口不单独放行/拦截，避免误伤同 IP 的其它服务
        if !exactIPs.isEmpty || !segments.isEmpty { return false }
        return ports.contains(Int(port))
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

    // MARK: - 路由规划

    /// 隧道路由方案
    ///
    /// iOS 的关键行为：**只有 split tunnel 时，系统经常不把 DNS 查询交给隧道**，
    /// 表现就是「开了防护，域名规则一条都碰不到」。所以这里改成
    /// 「默认路由指向隧道 + 把规则之外的地址排除出去」：
    /// 系统认为隧道是默认出口 → DNS 设置一定生效；真正走隧道的只有规则 IP 段。
    struct RoutePlan {
        /// true = included 里放 0.0.0.0/0，靠 excluded 把非规则流量放回物理网络
        var hijackAll = false
        var included: [(String, Int)] = []
        var excluded: [(String, Int)] = []
        /// 补集太碎时退回「只接管规则段」
        var degraded = false

        var routeCount: Int { included.count + excluded.count }

        var description: String {
            if degraded { return "按规则段接管 \(included.count) 条" }
            return "全接管 · 例外 \(excluded.count) 条"
        }
    }

    /// 规则命中的地址区间（合并后，闭区间、升序、互不相交）
    ///
    /// `coarsenTo`：把每个区间扩张到 2^(32-bits) 对齐边界，用于路由条数过多时
    /// 降低补集碎片（代价是同一块里没列进规则的地址也会进隧道）。
    func blockedRanges(coarsenTo bits: Int = 32) -> [(UInt32, UInt32)] {
        var list: [(UInt32, UInt32)] = segments.map { ($0.start, $0.end) }
        if !exactIPs.isEmpty {
            list.append(contentsOf: exactIPs.map { ($0, $0) })
        }
        guard !list.isEmpty else { return [] }
        list.sort { $0.0 < $1.0 }

        var out: [(UInt32, UInt32)] = []
        var curStart = list[0].0
        var curEnd = list[0].1
        for (s, e) in list.dropFirst() {
            let adjacent = curEnd != UInt32.max && UInt64(s) <= UInt64(curEnd) + 1
            if adjacent {
                if e > curEnd { curEnd = e }
            } else {
                out.append((curStart, curEnd))
                curStart = s; curEnd = e
            }
        }
        out.append((curStart, curEnd))
        return bits < 32 ? RuleSet.coarsen(out, to: bits) : out
    }

    /// 把区间对齐放大到 2^(32-bits) 的整块，再合并
    private static func coarsen(_ ranges: [(UInt32, UInt32)],
                                to bits: Int) -> [(UInt32, UInt32)] {
        guard bits < 32, !ranges.isEmpty else { return ranges }
        let step = UInt64(1) << UInt64(32 - bits)
        var list: [(UInt32, UInt32)] = []
        for (s, e) in ranges {
            let a = UInt64(s) / step * step
            let b = min(UInt64(UInt32.max), (UInt64(e) / step + 1) * step - 1)
            list.append((UInt32(a), UInt32(b)))
        }
        list.sort { $0.0 < $1.0 }
        var out: [(UInt32, UInt32)] = []
        var cs = list[0].0, ce = list[0].1
        for (s, e) in list.dropFirst() {
            if UInt64(s) <= UInt64(ce) + 1 {
                if e > ce { ce = e }
            } else {
                out.append((cs, ce)); cs = s; ce = e
            }
        }
        out.append((cs, ce))
        return out
    }

    /// 生成路由方案。
    ///
    /// - `forceInside`：必须留在隧道里的地址（DNS 代理、黑洞地址）。
    ///   它们在补集里被挖掉，否则系统会把 DNS 查询送回物理网络，整条链就断了。
    /// - `maxRoutes`：补集 CIDR 太多时退回保守方案，避免网络设置装不下起不来。
    func routePlan(forceInside: [UInt32] = [], maxRoutes: Int = 2600,
                   coarsenTo bits: Int = 32) -> RoutePlan {
        let blocked = blockedRanges(coarsenTo: bits)

        guard !blocked.isEmpty else {
            // 没有 IP 规则：只接管 DNS，别的都别碰
            var plan = RoutePlan()
            plan.included = forceInside.map { (RuleSet.uintToIP($0), 32) }
            return plan
        }

        var outside = RuleSet.complement(of: blocked)
        outside = RuleSet.removePoints(forceInside, from: outside)
        let excluded = RuleSet.cidrs(from: outside)

        if excluded.count > maxRoutes {
            // 补集碎到系统可能装不下：退回「只把规则段拉进隧道」，
            // 宁可 DNS 可能不生效，也不能让隧道起不来 / 用户断网。
            var plan = RoutePlan()
            plan.degraded = true
            plan.included = RuleSet.cidrs(from: blocked)
            plan.included.append(contentsOf: forceInside.map { (RuleSet.uintToIP($0), 32) })
            return plan
        }

        var plan = RoutePlan()
        plan.hijackAll = true
        plan.included = [("0.0.0.0", 0)]
        plan.excluded = excluded
        return plan
    }

    /// 0.0.0.0/0 减去这些区间
    private static func complement(of ranges: [(UInt32, UInt32)]) -> [(UInt32, UInt32)] {
        var out: [(UInt32, UInt32)] = []
        var cursor: UInt64 = 0
        for (s, e) in ranges {
            if UInt64(s) > cursor {
                out.append((UInt32(cursor), s - 1))
            }
            let next = UInt64(e) + 1
            cursor = max(cursor, next)
            if cursor > UInt64(UInt32.max) { break }
        }
        if cursor <= UInt64(UInt32.max) {
            out.append((UInt32(cursor), UInt32.max))
        }
        return out
    }

    /// 把若干单点从区间里挖掉（用于强制把 DNS / 黑洞地址留在隧道内）
    private static func removePoints(_ points: [UInt32],
                                     from ranges: [(UInt32, UInt32)]) -> [(UInt32, UInt32)] {
        guard !points.isEmpty else { return ranges }
        var out: [(UInt32, UInt32)] = []
        for (s, e) in ranges {
            var pieces: [(UInt32, UInt32)] = [(s, e)]
            for p in points {
                var next: [(UInt32, UInt32)] = []
                for (a, b) in pieces {
                    if p < a || p > b { next.append((a, b)); continue }
                    if a < p { next.append((a, p - 1)) }
                    if p < b { next.append((p + 1, b)) }
                }
                pieces = next
            }
            out.append(contentsOf: pieces)
        }
        return out
    }

    /// 区间 → CIDR（每块都是 2^n 对齐的最小集合，不会多覆盖一个地址）
    static func cidrs(from ranges: [(UInt32, UInt32)]) -> [(String, Int)] {
        var out: [(String, Int)] = []
        for (start, end) in ranges {
            var s = UInt64(start)
            let e = UInt64(end)
            while s <= e {
                // s 这一位能覆盖多大（按对齐）
                var alignSize = 32
                if s != 0 {
                    alignSize = 0
                    while alignSize < 32 && (s & (UInt64(1) << UInt64(alignSize))) == 0 {
                        alignSize += 1
                    }
                }
                // 剩余跨度能覆盖多大
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

    static func uintToIP(_ v: UInt32) -> String {
        "\((v >> 24) & 0xFF).\((v >> 16) & 0xFF).\((v >> 8) & 0xFF).\(v & 0xFF)"
    }
}
