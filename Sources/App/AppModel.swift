import Foundation
import SwiftUI
import Combine

/// 界面状态中枢
final class AppModel: ObservableObject {

    @Published var license: LicenseState = ConfigStore.shared.license
    @Published var authorized: Bool = false
    @Published var announcement: LicenseClient.Announcement?
    @Published var announcementOpen: Bool = false
    @Published var cloudNotice: String?
    @Published var stats: [String: Any] = [:]
    @Published var ruleCounts: (ips: Int, domains: Int) = (0, 0)
    @Published var ruleSource: String = "未加载"
    @Published var rulesLoading: Bool = false
    @Published var rulesError: String?

    /// 授权异常横幅（卡密作废 / 到期 / 未激活时给用户看的原因）
    @Published var authAlert: String?
    /// 正在向服务端确认授权
    @Published var verifying: Bool = false

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
    private var verifyingNow = false

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

        /* 启动即强校验：不信任本地缓存，先问服务端 */
        verifyNow()
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

    /// 有授权就把规则拉下来
    private func bootstrapRules() {
        guard ConfigStore.shared.isAuthorized else { return }
        loadRules(force: false)
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
        if authorized {
            authAlert = nil
        } else if license.code.isEmpty {
            /* 还没激活过：主界面已经有「激活卡密」入口，不必再顶一条红色警告 */
            authAlert = nil
        } else {
            authAlert = license.blockReason
        }
    }

    func loadAnnouncement() {
        LicenseClient.shared.fetchAnnouncement(pin: pin) { ann in
            DispatchQueue.main.async {
                if let ann = ann { self.announcement = ann }
            }
        }
    }

    /// 强校验：每次真的问服务端「这张卡现在到底还能不能用」
    /// 触发时机：App 启动 / 回到前台 / 开启 VPN 之前 / 手动刷新
    func verifyNow(completion: ((Bool) -> Void)? = nil) {
        guard !verifyingNow else {
            completion?(authorized)
            return
        }
        verifyingNow = true
        verifying = true

        LicenseClient.shared.check(pin: pin) { result in
            DispatchQueue.main.async {
                self.verifyingNow = false
                self.verifying = false
                switch result {
                case .success(let st):
                    var s = st
                    s.code = ConfigStore.shared.license.code
                    ConfigStore.shared.applySession(s, pin: self.pin, code: s.code)
                    self.refreshLocal()

                    if !self.authorized {
                        /* 服务端说不能用了：立刻停隧道、清规则、
                           界面同步成未授权，不再出现「显示已授权但 VPN 起不来」 */
                        self.authAlert = s.blockReason
                        RuleService.shared.clear()
                        self.refreshRules()
                        if self.tunnel.isConnected { self.tunnel.stop() }
                    } else if !RuleService.shared.isLoaded {
                        self.loadRules(force: false)
                    }
                    completion?(self.authorized)

                case .failure(let err):
                    /* 网络问题不改判定，交给窗口 + 宽限兜住 */
                    self.refreshLocal()
                    if !self.authorized {
                        self.authAlert = err.localizedDescription
                    }
                    completion?(self.authorized)
                }
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
                    self.authAlert = nil
                    self.toast = "授权成功，有效期至 \(st.expireText)"
                    self.loadRules(force: true)
                case .failure(let err):
                    self.toast = err.localizedDescription
                }
            }
        }
    }

    /// 续期：失败不直接判未授权（交给窗口 + 宽限）；
    /// 但服务端明确说卡密作废 / 到期，就必须当场失效。
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
                    if !self.authorized {
                        self.authAlert = st.blockReason
                        RuleService.shared.clear()
                        self.refreshRules()
                        if self.tunnel.isConnected { self.tunnel.stop() }
                        return
                    }
                    let v = RuleService.shared.version
                    if self.authorized && v != ConfigStore.shared.rulesVersion {
                        self.loadRules(force: true)
                    }
                case .failure(let err):
                    /* 卡密作废 / 到期：服务端会明确报错，这时立刻降级 */
                    if let le = err as? LicenseError {
                        switch le {
                        case .revoked, .expired:
                            var s = ConfigStore.shared.license
                            s.verdict = (le.errorDescription == LicenseError.revoked.errorDescription)
                                ? .cardRevoked : .cardExpired
                            s.authorized = false
                            s.sessionUntil = Date(timeIntervalSince1970: 0)
                            ConfigStore.shared.save(license: s)
                            self.refreshLocal()
                            self.authAlert = s.blockReason
                            RuleService.shared.clear()
                            self.refreshRules()
                            if self.tunnel.isConnected { self.tunnel.stop() }
                            if !silent { self.toast = le.localizedDescription }
                            return
                        default: break
                        }
                    }
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
        guard !ConfigStore.shared.license.code.isEmpty else {
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

        /* 开 VPN 前必须先向服务端确认一次：卡密作废 / 到期绝不允许起隧道，
           避免「界面显示已授权、VPN 却开不起来」这种前后矛盾 */
        busy = true
        verifyNow { ok in
            guard ok else {
                self.busy = false
                self.showLicense = self.license.code.isEmpty
                self.toast = self.authAlert ?? "授权已失效，请刷新状态"
                completion()
                return
            }
            self.busy = true
            self.tunnel.start { result in
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
    }

    // MARK: - 版本

    func checkUpdate() {
        VersionService.shared.check(pin: pin) { hasUpdate, force, info in
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
