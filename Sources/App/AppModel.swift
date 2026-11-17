import Foundation
import SwiftUI
import Combine

/// 界面状态中枢
///
/// 线程模型（1.0.1 重点）：
///   - 所有联网、解密、规则解析、状态落盘都在 `WorkQueue`（后台串行队列）
///   - 主线程只做一件事：把结果刷到 `@Published` 上
///   - 校验不再在点击/启动的瞬间堵住界面，开关随时能点，转圈只是提示
final class AppModel: ObservableObject {

    @Published var license: LicenseState = ConfigStore.shared.license
    @Published var authorized: Bool = false
    @Published var announcement: LicenseClient.Announcement?
    @Published var announcementOpen: Bool = false
    @Published var cloudNotice: String?

    /// 设置页里那些「刷新」动作的结果，统一显示在主界面顶部
    @Published var actionResult: String?
    /// 结果横幅出现的时间，用于自动淡出
    @Published var actionResultAt: Date?
    /// 请求主界面收起设置页（刷新动作点了就回主界面看结果）
    @Published var closeSettingsRequest: UUID?

    /// 云端公告拉不到时的兜底：主界面必须永远有公告位，不能空白
    static let builtinNotice = LicenseClient.Announcement(
        title: "欢迎使用 \(AppConfig.appName)",
        content: "1. 首次使用请到「设置 · 卡密授权」输入卡密激活；激活后主界面会显示到期时间和规则版本。\n2. 主界面那个大圆球就是总开关，点一下开启、再点一下关闭，没有第二个按钮。\n3. 开启后只接管规则命中范围内的连接，正常上网不受影响。\n4. 卡密到期或被作废时，防护会自动关闭，界面会明确提示原因。\n5. 有问题或需要续期，请到公益频道 \(AppConfig.channelName) 反馈。",
        updatedAt: "")

    /// 主界面公告位实际展示的内容（云端优先）
    var displayNotice: LicenseClient.Announcement {
        if let a = announcement, !(a.content.isEmpty && a.title.isEmpty) { return a }
        return AppModel.builtinNotice
    }

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
    private var resultTimer: AnyCancellable?
    private var lastRenew = Date.distantPast
    private var verifyingNow = false
    private var switching = false

    /// 设置页里的刷新动作
    enum QuickAction {
        case status, rules, notice
    }

    init() {
        refreshRules()
        refreshLocal()
        loadAnnouncement()

        tunnelObserver = tunnel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        /* 界面刷新 + 统计（3 秒一次，都是读缓存，不做解析） */
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

        /* 启动即强校验：不信任本地缓存，先问服务端（全程后台） */
        verifyNow()
        bootstrapRules()
        checkUpdate()
    }

    var pin: String { ConfigStore.shared.pin }

    // MARK: - 规则

    func refreshRules() {
        let set = RuleService.shared.currentSet
        ruleCounts = (set.summary.ips, set.domains.count)
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

        RuleService.shared.load(pin: pin, code: code, force: force) { [weak self] result in
            guard let self = self else { return }
            /* RuleService 已经把回调放在主线程 */
            self.rulesLoading = false
            switch result {
            case .success(let text):
                self.refreshRules()
                if self.tunnel.isConnected {
                    self.tunnel.pushRules(text)
                }
                if force {
                    let c = self.ruleCounts
                    self.publishResult("规则已更新 · \(self.ruleSource)（IP \(c.ips) / 域名 \(c.domains)）")
                }
            case .failure(let err):
                self.rulesError = err.localizedDescription
                if force {
                    self.publishResult("规则更新失败：\(err.localizedDescription)")
                }
            }
        }
    }

    // MARK: - 授权

    func refreshLocal() {
        license = ConfigStore.shared.license
        let ok = license.isUsable()
        authorized = ok
        if ok {
            authAlert = nil
        } else if license.code.isEmpty {
            /* 还没激活过：主界面已经有「激活卡密」入口，不必再顶一条红色警告 */
            authAlert = nil
        } else {
            authAlert = license.blockReason
        }
    }

    func loadAnnouncement(completion: ((Bool) -> Void)? = nil) {
        let p = pin
        LicenseClient.shared.fetchAnnouncement(pin: p) { [weak self] ann in
            WorkQueue.main {
                guard let self = self else { return }
                if let ann = ann {
                    self.announcement = ann
                    completion?(true)
                } else {
                    completion?(false)
                }
            }
        }
    }

    /// 强校验：每次真的问服务端「这张卡现在到底还能不能用」
    /// 触发时机：App 启动 / 回到前台 / 开启 VPN 之前 / 手动刷新
    ///
    /// 网络与解包在后台，结果落盘也在后台，只有 UI 状态回主线程。
    func verifyNow(completion: ((Bool) -> Void)? = nil) {
        if verifyingNow {
            completion?(authorized)
            return
        }
        verifyingNow = true
        verifying = true
        let pin = self.pin

        LicenseClient.shared.check(pin: pin) { [weak self] result in
            guard let self = self else { return }

            WorkQueue.async {
                var ok = false
                var alert: String?
                var snapshot: LicenseState?

                switch result {
                case .success(let st):
                    var s = st
                    s.code = ConfigStore.shared.license.code
                    ConfigStore.shared.applySession(s, pin: pin, code: s.code)
                    let lic = ConfigStore.shared.license
                    ok = lic.isUsable()
                    alert = ok ? nil : lic.blockReason
                    snapshot = lic
                    if !ok { RuleService.shared.clear() }

                case .failure(let err):
                    /* 网络问题不改判定，交给窗口 + 宽限兜住 */
                    let lic = ConfigStore.shared.license
                    ok = lic.isUsable()
                    alert = ok ? nil : err.localizedDescription
                    snapshot = lic
                }

                let needRules = ok && !RuleService.shared.isLoaded

                WorkQueue.main {
                    self.verifyingNow = false
                    self.verifying = false
                    if let s = snapshot {
                        self.license = s
                        self.authorized = ok
                    } else {
                        self.refreshLocal()
                    }
                    self.authAlert = alert
                    if !ok {
                        self.refreshRules()
                        if self.tunnel.isConnected { self.tunnel.stop() }
                    } else if needRules {
                        self.loadRules(force: false)
                    }
                    completion?(ok)
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
        let pin = self.pin

        LicenseClient.shared.redeem(pin: pin, code: code) { [weak self] result in
            guard let self = self else { return }

            WorkQueue.async {
                switch result {
                case .success(let st):
                    ConfigStore.shared.applySession(st, pin: pin, code: code)
                    let lic = ConfigStore.shared.license
                    WorkQueue.main {
                        self.busy = false
                        self.license = lic
                        self.authorized = lic.isUsable()
                        self.authAlert = nil
                        self.showLicense = false
                        self.licenseInput = ""
                        self.publishResult("授权成功，有效期至 \(st.expireText)")
                        self.closeSettingsRequest = UUID()
                        self.loadRules(force: true)
                    }

                case .failure(let err):
                    WorkQueue.main {
                        self.busy = false
                        self.toast = err.localizedDescription
                    }
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
        let pin = self.pin

        LicenseClient.shared.beat(pin: pin, code: code) { [weak self] result in
            guard let self = self else { return }

            WorkQueue.async {
                switch result {
                case .success(let st):
                    ConfigStore.shared.applySession(st, pin: pin, code: code)
                    let lic = ConfigStore.shared.license
                    let ok = lic.isUsable()
                    /* 续期本身不动规则；只有内存里一份都没有时才补拉 */
                    let needRules = ok && !RuleService.shared.isLoaded
                    if !ok { RuleService.shared.clear() }

                    WorkQueue.main {
                        if !silent { self.busy = false }
                        self.license = lic
                        self.authorized = ok
                        self.refreshRules()
                        if !ok {
                            self.authAlert = lic.blockReason
                            if self.tunnel.isConnected { self.tunnel.stop() }
                            if !silent { self.publishResult("授权已失效：\(lic.blockReason)") }
                            return
                        }
                        if needRules { self.loadRules(force: true) }
                    }

                case .failure(let err):
                    var hard = false
                    var lic = ConfigStore.shared.license
                    if let le = err as? LicenseError {
                        switch le {
                        case .revoked, .expired:
                            hard = true
                            lic.verdict = (le.errorDescription == LicenseError.revoked.errorDescription)
                                ? .cardRevoked : .cardExpired
                            lic.authorized = false
                            lic.sessionUntil = Date(timeIntervalSince1970: 0)
                            ConfigStore.shared.save(license: lic)
                            RuleService.shared.clear()
                        default: break
                        }
                    }
                    WorkQueue.main {
                        if !silent { self.busy = false }
                        if hard {
                            self.license = lic
                            self.authorized = false
                            self.authAlert = lic.blockReason
                            self.refreshRules()
                            if self.tunnel.isConnected { self.tunnel.stop() }
                            if !silent { self.publishResult("授权已失效：\(lic.blockReason)") }
                        } else if !silent {
                            self.toast = err.localizedDescription
                        }
                    }
                }
            }
        }
    }

    // MARK: - 设置页的刷新动作（结果统一回主界面显示）

    /// 点设置里的刷新：先收起设置，结果落在主界面顶部
    func runQuickAction(_ action: QuickAction) {
        closeSettingsRequest = UUID()

        switch action {
        case .status:
            publishResult("正在向服务端校验授权…")
            verifyNow { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    let lic = ConfigStore.shared.license
                    self.publishResult("授权正常 · 有效期至 \(lic.expireText) · 剩余 \(lic.remainText)")
                } else {
                    self.publishResult("授权失效：\(self.authAlert ?? "状态异常，请重新激活")")
                }
            }

        case .rules:
            guard ConfigStore.shared.isAuthorized else {
                publishResult("规则刷新失败：需要先激活卡密")
                return
            }
            publishResult("正在同步云端规则…")
            loadRules(force: true)

        case .notice:
            publishResult("正在拉取公告…")
            loadAnnouncement { [weak self] ok in
                guard let self = self else { return }
                if ok {
                    self.publishResult("公告已更新 · \(MainView.prettyTime(self.displayNotice.updatedAt))")
                    self.announcementOpen = true
                } else {
                    self.publishResult("公告拉取失败，已显示内置公告")
                }
            }
        }
    }

    /// 把一条操作结果投到主界面横幅
    ///
    /// 只用这一条通道，不再额外弹 toast：两处一起出现会互相盖住，
    /// 而用户要的是「结果在主界面看得见」，不是飘一下就没。
    func publishResult(_ text: String) {
        WorkQueue.main {
            self.actionResult = text
            self.actionResultAt = Date()
        }
    }

    func dismissActionResult() {
        actionResult = nil
        actionResultAt = nil
    }

    // MARK: - 连接

    /// 唯一入口：点大圆球就是它
    func toggle(completion: @escaping () -> Void = {}) {
        guard !switching else { completion(); return }

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

        switching = true
        busy = true

        /* 开 VPN 前必须先向服务端确认一次：卡密作废 / 到期绝不允许起隧道，
           避免「界面显示已授权、VPN 却开不起来」这种前后矛盾。
           这一步在后台跑，界面不会卡住。 */
        verifyNow { [weak self] ok in
            guard let self = self else { return }
            guard ok else {
                self.switching = false
                self.busy = false
                self.showLicense = self.license.code.isEmpty
                self.publishResult(self.authAlert ?? "授权已失效，请刷新状态")
                completion()
                return
            }
            self.tunnel.start { result in
                WorkQueue.main {
                    self.switching = false
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
        VersionService.shared.check(pin: pin) { [weak self] hasUpdate, force, info in
            guard let self = self else { return }
            WorkQueue.main {
                self.updateInfo = info
                self.forceUpdate = hasUpdate && force
                if hasUpdate && !force { self.showUpdate = true }
            }
        }
    }

    // MARK: - 统计

    func pollStats() {
        tunnel.fetchStats { [weak self] obj in
            guard !obj.isEmpty else { return }
            WorkQueue.main { self?.stats = obj }
        }
    }

    var blockedText: String { "\((stats["blocked"] as? Int) ?? 0)" }
    var domainText: String { "\((stats["domains"] as? Int) ?? 0)" }
    var tcpText: String { "\((stats["tcp"] as? Int) ?? 0)" }
    var udpText: String { "\((stats["udp"] as? Int) ?? 0)" }
    var connText: String { "\((stats["conn"] as? Int) ?? 0)" }

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
