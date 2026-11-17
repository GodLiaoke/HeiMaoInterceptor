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
    @Published var ruleSource: String = "未加载"
    @Published var rulesLoading: Bool = false
    @Published var rulesError: String?

    /// 版本
    @Published var updateInfo: AppUpdateInfo?
    @Published var showUpdate: Bool = false
    @Published var forceUpdate: Bool = false

    @Published var busy: Bool = false
    @Published var toast: String?
    @Published var showLicense: Bool = false
    @Published var licenseInput: String = ""

    let tunnel = TunnelController.shared

    private var timer: AnyCancellable?
    private var renewTimer: AnyCancellable?
    private var tunnelObserver: AnyCancellable?
    private var lastRenew = Date.distantPast

    init() {
        refreshRules()
        refreshLocal()
        loadAnnouncement()

        tunnelObserver = tunnel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        /* 界面刷新 + 统计 */
        timer = Timer.publish(every: 3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.refreshLocal()
                self.pollStats()
            }

        /* 续期：每 30 秒检查一次，够 60 秒就推一次窗口 */
        renewTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                guard self.authorized else { return }
                guard Date().timeIntervalSince(self.lastRenew) >= AppConfig.heartbeatInterval else { return }
                self.refreshLicense(silent: true)
            }

        bootstrapRules()
        checkUpdate()
    }

    var pin: String { ConfigStore.shared.pin }

    // MARK: - 规则

    func refreshRules() {
        let set = ConfigStore.shared.currentRuleSet()
        ruleCounts = (set.ipRanges.count, set.domains.count)
        ruleSource = ConfigStore.shared.rulesSourceLabel
        cloudNotice = ConfigStore.shared.cloudNotice
    }

    /// 启动时：有授权就把规则拉下来
    private func bootstrapRules() {
        guard ConfigStore.shared.isAuthorized else { return }
        loadRules(force: false)
        refreshLicense(silent: true)
    }

    func loadRules(force: Bool) {
        let pin = ConfigStore.shared.pin
        let code = ConfigStore.shared.license.code
        guard !code.isEmpty else {
            rulesError = "需要先激活卡密"
            return
        }
        rulesLoading = true
        rulesError = nil

        RuleService.shared.load(pin: pin, code: code, force: force) { result in
            DispatchQueue.main.async {
                self.rulesLoading = false
                switch result {
                case .success:
                    self.refreshRules()
                    if self.tunnel.isConnected, let text = RuleService.shared.text {
                        self.tunnel.pushRules(text)
                    }
                    if !force { return }
                    self.toast = "规则已更新到 v\(RuleService.shared.version)"
                case .failure(let err):
                    self.rulesError = err.localizedDescription
                }
            }
        }
    }

    // MARK: - 授权

    func refreshLocal() {
        license = ConfigStore.shared.license
        authorized = license.isUsable()
    }

    func loadAnnouncement() {
        LicenseClient.shared.fetchAnnouncement { ann in
            DispatchQueue.main.async {
                if let ann = ann { self.announcement = ann }
            }
        }
    }

    func activate(code raw: String) {
        let code = CryptoBox.normaliseCode(raw)
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
                    ConfigStore.shared.applySession(st, pin: self.pin, code: code)
                    self.refreshLocal()
                    self.showLicense = false
                    self.licenseInput = ""
                    self.toast = "授权成功，有效期至 \(st.expireText)"
                    self.loadRules(force: true)
                case .failure(let err):
                    self.toast = err.localizedDescription
                }
            }
        }
    }

    /// 续期：失败不直接判未授权，交给窗口 + 宽限兜住
    func refreshLicense(silent: Bool = false) {
        let code = license.code
        guard !code.isEmpty else { return }
        if !silent { busy = true }
        lastRenew = Date()

        LicenseClient.shared.beat(pin: pin, code: code) { result in
            DispatchQueue.main.async {
                if !silent { self.busy = false }
                switch result {
                case .success(let st):
                    ConfigStore.shared.applySession(st, pin: self.pin, code: code)
                    self.refreshLocal()
                    let v = RuleService.shared.version
                    if self.authorized && v != ConfigStore.shared.rulesVersion {
                        self.loadRules(force: true)
                    }
                case .failure(let err):
                    if !silent { self.toast = err.localizedDescription }
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
            toast = "请先激活卡密"
            completion()
            return
        }
        guard RuleService.shared.isLoaded else {
            toast = rulesError ?? "云端规则还没加载好，稍等一下再开"
            loadRules(force: false)
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

    // MARK: - 版本

    func checkUpdate() {
        VersionService.shared.check { hasUpdate, force, info in
            self.updateInfo = info
            self.forceUpdate = hasUpdate && force
            if hasUpdate && !force {
                self.showUpdate = true
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
        "\((stats["blocked"] as? Int) ?? 0)"
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
