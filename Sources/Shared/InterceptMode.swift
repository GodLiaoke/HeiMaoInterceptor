import Foundation

/// 拦截模式（1.2.3）
///
/// 以前只有一种跑法：默认路由全接管，规则外的流量靠「例外路由」交回物理网卡。
/// 例外表装不下的时候（规则 IP 一多就会）只能退回窄口，用户体感是「开了防护网就断」。
/// 现在把这件事交给用户自己选：
///
///   - `.rules`  规则模式（默认）：只把规则里的 IP 段和假 DNS 拽进隧道，
///               域名规则靠 split DNS（matchDomains）单独接管。规则外的流量
///               压根不进隧道，不存在「断网」的可能。
///   - `.global` 全局模式：默认路由全接管，规则外的流量走例外路由回物理网卡。
///               能看见所有 DNS，域名/CNAME 拦得更全，但对路由条数更敏感。
///
/// 两种模式都由扩展在启动配置里读，切换后重连一次即可生效。
enum InterceptMode: String, CaseIterable, Identifiable {
    case rules
    case global

    var id: String { rawValue }

    /// 存进 UserDefaults / providerConfiguration 的值
    var rawValueKey: String { rawValue }

    var title: String {
        switch self {
        case .rules:  return "规则模式"
        case .global: return "全局模式"
        }
    }

    var shortTitle: String {
        switch self {
        case .rules:  return "规则"
        case .global: return "全局"
        }
    }

    var icon: String {
        switch self {
        case .rules:  return "line.3.horizontal.decrease.circle"
        case .global: return "circle.grid.cross"
        }
    }

    /// 主界面选择栏里的两行说明（短）
    var brief: String {
        switch self {
        case .rules:  return "只拦命中规则的，其余直连"
        case .global: return "全部流量进隧道，拦得更全"
        }
    }

    /// 切换后的完整说明
    var detail: String {
        switch self {
        case .rules:
            return "规则模式：只有规则里的 IP 段和域名走隧道，其它流量保持原样，正常上网不受影响"
        case .global:
            return "全局模式：所有流量都交给隧道判定，域名与 CNAME 拦得更全；规则外的流量仍走原网络"
        }
    }

    var tintHexHint: String { rawValue }

    static func from(_ raw: String?) -> InterceptMode {
        guard let raw = raw, let m = InterceptMode(rawValue: raw) else { return .rules }
        return m
    }
}
