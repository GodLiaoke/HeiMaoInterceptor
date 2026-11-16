import Foundation
import SwiftUI
import Combine

/// 界面状态中枢
final class AppModel: ObservableObject {

    @Published var license: LicenseState = ConfigStore.shared.license
    @Published var authorized: Bool = false
    @Published var announcement: LicenseClient.Announcement?
    @Published var cloudNotice: String?
    @Published var stats: [String: Any] = [:]
    @Published var ruleCounts: (ips: Int, domains: Int) = (0, 0)
    @Published var ruleSource: String = "内置规则库"
    @Published var busy: Bool = false
    @Published var toast: String?
    @Published var showLicense: Bool = false
    @Published var licenseInput: String = ""

    let tunnel = TunnelController.shared
    private var timer: AnyCancellable?
    private var tunnelObserver: AnyCancellable?

    init() {
        refreshRules()
        refreshLocal()
        loadAnnouncement()
        tunnelObserver = tunnel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollStats()
            }
    }

    var pin: String { ConfigStore.shared.pin }

    func refreshRules() {
        let set = ConfigStore.shared.currentRuleSet()
        ruleCounts = (set.ipRanges.count, set.domains.count)
        ruleSource = ConfigStore.shared.rulesSourceLabel
        cloudNotice = ConfigStore.shared.cloudNotice
    }

    func refreshLocal() {
        license = ConfigStore.shared.license
        authorized = ConfigStore.shared.isAuthorized
    }

    // MARK: - 公告

    func loadAnnouncement() {
        LicenseClient.shared.fetchAnnouncement { ann in
            DispatchQueue.main.async {
                if let ann = ann { self.announcement = ann }
            }
        }
    }

    // MARK: - 授权

    func activate(code raw: String) {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 6 else {
            toast = "请输入完整卡密"
            return
        }
        busy = true
        LicenseClient.shared.redeem(pin: pin, code: code) { result in
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let st):
                    ConfigStore.shared.save(license: st)
                    self.refreshLocal()
                    self.refreshRules()
                    self.showLicense = false
                    self.licenseInput = ""
                    self.toast = "授权成功，有效期至 \(st.expireText)"
                case .failure(let err):
                    self.toast = err.localizedDescription
                }
            }
        }
    }

    func refreshLicense(silent: Bool = false) {
        guard !license.code.isEmpty else { return }
        if !silent { busy = true }
        LicenseClient.shared.beat(pin: pin, code: license.code) { result in
            DispatchQueue.main.async {
                self.busy = false
                if case .success(let st) = result {
                    var merged = st
                    merged.authorized = st.authorized || self.license.authorized
                    merged.code = st.code.isEmpty ? self.license.code : st.code
                    ConfigStore.shared.save(license: merged)
                    self.refreshLocal()
                    self.refreshRules()
                }
            }
        }
    }

    // MARK: - 连接

    func toggle(completion: @escaping () -> Void = {}) {
        if tunnel.isConnected {
            tunnel.stop()
            completion()
            return
        }
        guard ConfigStore.shared.isAuthorized else {
            showLicense = true
            completion()
            return
        }
        busy = true
        tunnel.start { result in
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success:
                    if let notice = ConfigStore.shared.cloudNotice, !notice.isEmpty {
                        self.toast = notice
                    }
                case .failure(let err):
                    self.toast = "启动失败：\(err.localizedDescription)"
                }
                completion()
            }
        }
    }

    // MARK: - 统计

    func pollStats() {
        tunnel.fetchStats { obj in
            guard !obj.isEmpty else { return }
            DispatchQueue.main.async { self.stats = obj }
        }
    }

    var blockedText: String {
        let v = (stats["blocked"] as? Int) ?? 0
        return "\(v)"
    }

    var domainText: String {
        "\((stats["domains"] as? Int) ?? 0)"
    }

    var tcpText: String { "\((stats["tcp"] as? Int) ?? 0)" }
    var udpText: String { "\((stats["udp"] as? Int) ?? 0)" }

    var uptimeText: String {
        let s = (stats["uptime"] as? Int) ?? 0
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)时\(m)分" }
        if m > 0 { return "\(m)分\(sec)秒" }
        return "\(sec)秒"
    }

    func dismissToast() {
        toast = nil
    }
}
