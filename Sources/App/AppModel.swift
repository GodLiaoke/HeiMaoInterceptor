import Foundation
import SwiftUI
import Combine
import UIKit

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
    /// 公告默认展开：用户第一眼要能看完公告全文，不能一进来就被折成两行
    @Published var announcementOpen: Bool = true
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
        content: "1. 首次使用请到「设置 · 卡密授权」输入卡密激活；激活后主界面会显示到期时间和规则版本。\n2. 主界面那个大圆球就是总开关，点一下开启、再点一下关闭，没有第二个按钮。\n3. 开启后只接管规则命中范围内的连接，正常上网不受影响。\n4. 卡密到期或被作废时，防护会自动关闭，界面会明确提示原因。\n5. 有问题或需要续期，请到官方频道 \(AppConfig.channelName) 反馈。",
        updatedAt: "")

    /// 主界面公告位实际展示的内容（云端优先）
    var displayNotice: LicenseClient.Announcement {
        if let a = announcement, !(a.content.isEmpty && a.title.isEmpty) { return a }
        return AppModel.builtinNotice
    }

    @Published var stats: [String: Any] = [:]
    /// 这次数字是从「隧道回包」还是「扩展落盘」来的，排查时能直接看出通道状态
    @Published var statsSource: String = "—"
    @Published var ruleCounts: (ips: Int, domains: Int) = (0, 0)
    @Published var rulePorts: Int = 0
    @Published var ruleSource: String = "未加载"
    /// 后台勾选下发的那几套规则（名称来自 manifest）
    @Published var ruleSets: [String] = []
    @Published var ruleSetCount: Int = 0
    @Published var ruleSetDetails: [[String: Any]] = []
    @Published var ruleVersionText: String = "未加载"
    @Published var ruleUpdatedAt: Date?
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
    /// 拦截模式：规则 / 全局（1.2.3）
    @Published var interceptMode: InterceptMode = ConfigStore.shared.mode
    /// 规则包 #PORT 段是否参与拦截（1.2.3，默认关）
    @Published var portBlocking: Bool = ConfigStore.shared.portBlocking
    /// 维护模式原因（nil = 正常）。服务端开启维护后，整个界面会被维护页盖住
    @Published var maintenanceReason: String?

    let tunnel = TunnelController.shared

    private var timer: AnyCancellable?
    private var opsTimer: AnyCancellable?
    private var renewTimer: AnyCancellable?
    private var tunnelObserver: AnyCancellable?
    private var resultTimer: AnyCancellable?
    private var lastRenew = Date.distantPast
    private var verifyingNow = false
    private var switching = false
    /// 心跳连续失败次数：到阈值就按「链路断了」处理，卸载规则并断开
    private var renewFailures = 0
    /// 是否在前台。App 进后台后 iOS 会把进程挂起，主线程 Timer 全部停摆，
    /// 这时候再发心跳没有意义，只会让「心跳失败次数」虚涨。
    private var foreground = true
    /// 进后台时申请的短暂额度：用来把手上这一次心跳 / 状态落盘做完
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// 续期守护：曾经开过防护、现在断了，就自己拉回来
    private var lastAutoStart = Date.distantPast
    private var autoStartCount = 0

    /// 用户上一次的意图：开 or 关。自动重连只在这个为 true 时做，
    /// 用户自己点了关闭就不会被系统「热心」地重新拉起来。
    private var wantsProtection: Bool {
        get { UserDefaults.standard.bool(forKey: "hm.wants.protection") }
        set { UserDefaults.standard.set(newValue, forKey: "hm.wants.protection") }
    }

    /// 设置页里的刷新动作
    enum QuickAction {
        case status, rules, notice
    }

    init() {
        /* 先做一次运行环境自检：注入 / 调试 / 改包都会留痕，
           结论随授权请求一起上报，本地也据此决定授权要不要写盘 */
        Integrity.shared.evaluate()
        /* 1.2.3：先按本地熔断钉子判一次（上次联网时钉下的结论，断网也照样生效） */
        OpsService.enforcePinned()
        /* 看门狗：主程序与内嵌 dylib 互相校验，任一侧被拔掉都直接退场 */
        GuardLink.start { OpsService.die() }
        /* 功能校验的 CRC 组提前在后台算好，别卡在授权请求那一下 */
        WorkQueue.async { _ = FeatureProbe.all() }

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
                self.protectionGuard()
            }

        /* 续期：每 30 秒检查一次，够 90 秒就推一次窗口 */
        renewTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                /* 后台不发心跳：进程随时会被冻住，发的这次也可能排在队列里
                   等唤醒后才执行，反而把 lastRenew 推后、让下一次心跳更晚。
                   后台续期交给隧道扩展（它不会被挂起）。 */
                guard self.foreground else { return }
                /* 1.2.2：这里以前是 guard self.authorized。
                   窗口一过期 authorized 就变 false，于是心跳彻底停了 ——
                   再怎么等也恢复不了，只能手动去点「刷新状态」。
                   现在只要不是硬失效就继续续，网络回来自然能续上。 */
                guard !ConfigStore.shared.license.isHardInvalid else { return }
                guard self.tunnel.isConnected else { return }
                guard Date().timeIntervalSince(self.lastRenew) >= AppConfig.heartbeatInterval else { return }
                self.refreshLicense(silent: true)
            }

        /* 运维状态定期刷新：云端开维护 / 开熔断之后，正在用的设备也要在几分钟内响应 */
        opsTimer = Timer.publish(every: 240, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.foreground else { return }
                self.checkUpdate()
            }

        /* 启动即强校验：不信任本地缓存，先问服务端（全程后台） */
        verifyNow()
        /* 规则不在启动时拉：只在开启防护的那一刻下发 */
        checkUpdate()
    }

    // MARK: - 前后台

    /// 进后台：只把最后一笔状态落盘，然后停止一切定时任务（反正会被冻结）
    func applicationDidEnterBackground() {
        foreground = false
        /* 申请一小段后台时间，把「刚收发的统计」「当前授权」落稳，
           顺便把下一次心跳提前发掉 —— 这样后台闲置很长时间后回来，
           服务端窗口也还没过期，不用等一次完整校验才恢复。 */
        beginBackgroundWindow()
        if authorized && tunnel.isConnected {
            refreshLicense(silent: true)
        }
    }

    /// 回前台：立刻补一次校验，并把自动重连的节流窗口复位
    func applicationWillEnterForeground() {
        foreground = true
        endBackgroundWindow()
        lastAutoStart = .distantPast
        autoStartCount = 0
        /* 顺手核对按需连接还在不在：被系统吞掉的话，隧道掉一次就再也拉不回来 */
        if wantsProtection { tunnel.healOnDemand() }
        pollStats()
        protectionGuard(force: true)
    }

    private func beginBackgroundWindow() {
        endBackgroundWindow()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "hm.beat") { [weak self] in
            self?.endBackgroundWindow()
        }
        /* 最多 25 秒，别占着系统额度 */
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.endBackgroundWindow()
        }
    }

    private func endBackgroundWindow() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - 防护守护

    /// 心跳自己会断，隧道不该跟着断。
    ///
    /// 这个守护只做一件事：用户明确开过防护、授权还有效、但隧道掉了
    /// （切网、锁屏、系统回收扩展之后没被 onDemand 拉回来），就自己拉回来。
    /// 每次最少间隔 45 秒、连续 8 次失败就停手，避免在没救的情况下反复连断。
    private func protectionGuard(force: Bool = false) {
        guard wantsProtection else { return }
        /* 只按硬失效拦：窗口过期（后台久了 / 刚切网）不该阻止把隧道拉回来 */
        guard !ConfigStore.shared.license.isHardInvalid else { return }
        guard tunnel.status == .disconnected || tunnel.status == .invalid else { return }
        guard !switching else { return }
        guard autoStartCount < 8 else { return }
        guard force || Date().timeIntervalSince(lastAutoStart) >= 45 else { return }

        lastAutoStart = Date()
        autoStartCount += 1

        if RuleService.shared.isLoaded {
            launchTunnel(auto: true)
            return
        }
        /* 规则不在内存里（App 被系统重开过、刚装完）：先拉一次再起隧道。
           直接 start() 会被「规则还没加载好」挡回来，表现就是守护一直试一直失败。 */
        loadRules(force: false, requireTunnel: false) { [weak self] ok in
            guard let self = self, ok else { return }
            self.launchTunnel(auto: true)
        }
    }

    private func launchTunnel(auto: Bool = false) {
        tunnel.start { [weak self] result in
            guard let self = self else { return }
            if case .success = result {
                let first = (self.autoStartCount <= 1)
                self.autoStartCount = 0
                /* 只在第一次自动恢复时提示，避免反复连断时刷屏 */
                if auto && first {
                    self.publishResult("VPN 被系统中断，已自动恢复防护")
                }
            }
        }
    }

    var pin: String { ConfigStore.shared.pin }

    // MARK: - 规则

    func refreshRules() {
        let rs = RuleService.shared
        let set = rs.currentSet
        ruleCounts = (set.summary.ips, set.domains.count)
        rulePorts = set.report.ports
        ruleSource = ConfigStore.shared.rulesSourceLabel
        ruleSets = rs.setNames
        ruleSetCount = rs.setCount > 0 ? rs.setCount : rs.setNames.count
        ruleSetDetails = rs.setDetails
        ruleVersionText = rs.versionText
        ruleUpdatedAt = rs.loadedAt
        cloudNotice = ConfigStore.shared.cloudNotice
    }

    /// 规则只在防护开启的过程中下发
    ///
    /// `requireTunnel` 为 true（设置页 / 规则页手动同步）时，隧道没跑就先拒绝；
    /// 开关流程本身是「先拉规则再起隧道」，所以内部调用传 false。
    func loadRules(force: Bool,
                   requireTunnel: Bool = true,
                   completion: ((Bool) -> Void)? = nil) {
        if requireTunnel && !tunnel.isConnected {
            rulesError = "开启防护后才会下发规则"
            if force { publishResult("开启防护后才会下发规则") }
            completion?(false)
            return
        }
        let pin = ConfigStore.shared.pin
        let code = ConfigStore.shared.license.code
        guard !code.isEmpty else {
            rulesError = "需要先激活卡密"
            completion?(false)
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
                /* 隧道已经在跑、又是手动同步：把新规则推进扩展（扩展会顺带重算路由）。
                   送不进去就重启一次隧道，让新规则随启动配置生效。 */
                if force, self.tunnel.isConnected {
                    self.tunnel.pushRules(text) { ok in
                        if !ok { self.tunnel.restart() }
                    }
                }
                if force {
                    let c = self.ruleCounts
                    var detail = "IP \(c.ips) / 域名 \(c.domains)"
                    if self.rulePorts > 0 { detail += " / 端口 \(self.rulePorts)" }
                    let sets = self.ruleSets.isEmpty ? "" : " · \(self.ruleSetCount) 套：\(self.ruleSets.joined(separator: " / "))"
                    self.publishResult("规则已更新\(sets)（\(detail)）")
                }
                completion?(true)
            case .failure(let err):
                self.rulesError = err.localizedDescription
                if force {
                    self.publishResult("规则更新失败：\(err.localizedDescription)")
                }
                completion?(false)
            }
        }
    }

    /// 规则是不是过期了：每 15 分钟问一次服务端的规则版本，变了才下载
    ///
    /// 为什么需要：App 常驻后台时内存里那份规则会一直是旧的 —— 后台换了规则，
    /// 客户端毫无感觉，用户看到的就是「服务端规则更新了，可一点没生效」。
    /// 只在隧道跑着、授权有效时做，且走版本号比对，不会反复下载和重建路由。
    private var lastRuleCheck = Date.distantPast

    private func checkRuleFreshness() {
        guard authorized, tunnel.isConnected else { return }
        guard Date().timeIntervalSince(lastRuleCheck) > 900 else { return }
        lastRuleCheck = Date()
        let pin = ConfigStore.shared.pin
        let code = ConfigStore.shared.license.code
        guard !code.isEmpty else { return }

        RuleService.shared.remoteVersion(pin: pin, code: code) { [weak self] remote in
            guard let self = self, let remote = remote, !remote.isEmpty else { return }
            guard remote != RuleService.shared.version else { return }
            self.loadRules(force: true, requireTunnel: false)
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
                    if lic.isHardInvalid { RuleService.shared.clear() }

                case .failure(let err):
                    /* 网络问题不改判定，交给窗口 + 宽限兜住 */
                    let lic = ConfigStore.shared.license
                    ok = lic.isUsable()
                    alert = ok ? nil : err.localizedDescription
                    snapshot = lic
                }

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
                    /* 1.2.2：只有服务端明确判死（作废/到期/封禁/强下线）才断隧道。
                       「窗口过期」「刚联网还没校验上」以前也走这里，于是一回到
                       前台、网络还没恢复的那一下，正在跑的防护就被掐了 ——
                       用户看到的正是「挂后台一会儿就断」。 */
                    if self.license.isHardInvalid {
                        self.refreshRules()
                        if self.tunnel.isConnected { self.tunnel.stop() }
                    } else if self.tunnel.isConnected && !RuleService.shared.isLoaded {
                        /* 只有隧道在跑才需要规则；没开防护就不下发 */
                        self.loadRules(force: false, requireTunnel: false)
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
                        self.publishResult("授权成功，有效期至 \(st.expireText) · 开启防护后自动下发规则")
                        self.closeSettingsRequest = UUID()
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
                    let dead = lic.isHardInvalid
                    if dead { RuleService.shared.clear() }

                    WorkQueue.main {
                        if !silent { self.busy = false }
                        self.license = lic
                        self.authorized = ok
                        self.refreshRules()
                        /* 1.2.2：心跳回来的结论也分软硬。
                           只有作废 / 到期 / 封禁 / 强下线才停隧道；
                           窗口过期（后台太久没续上）只提示，防护继续跑，
                           下一次心跳成功就自动恢复正常。 */
                        if dead {
                            self.authAlert = lic.blockReason
                            if self.tunnel.isConnected { self.tunnel.stop() }
                            if !silent { self.publishResult("授权已失效：\(lic.blockReason ?? "")") }
                            return
                        }
                        if !ok {
                            self.authAlert = nil
                            return
                        }
                        self.renewFailures = 0
                        if silent { self.checkRuleFreshness() }
                        if ok && self.tunnel.isConnected && !RuleService.shared.isLoaded {
                            self.loadRules(force: false, requireTunnel: false)
                        }
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
                            RuleService.shared.clear()
                            self.refreshRules()
                            if self.tunnel.isConnected { self.tunnel.stop() }
                            self.renewFailures = 0
                            if !silent { self.publishResult("授权已失效：\(lic.blockReason)") }
                        } else {
                            /* 1.1.1：网络失败不再卸载规则、不再断隧道。
                               以前心跳连续两次（60 秒一次，也就是两分钟）失败就 stop，
                               锁屏、切网、地铁里信号差都会踩到 —— 用户体感就是「VPN 老是断开」。
                               规则已经在本地，服务端连不上只影响复核，防护照常跑。 */
                            self.renewFailures += 1
                            if self.renewFailures == 2 {
                                self.publishResult("服务端暂时连不上，防护继续运行，恢复网络后会自动复核")
                            } else if !silent {
                                self.toast = err.localizedDescription
                            }
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
            /* 关防护 = 立刻把规则从内存里卸掉，不留在设备上 */
            wantsProtection = false
            autoStartCount = 0
            tunnel.stop()
            RuleService.shared.clear()
            refreshRules()
            publishResult("防护已关闭，云端规则已卸载")
            completion()
            return
        }
        guard !ConfigStore.shared.license.code.isEmpty else {
            showLicense = true
            toast = "请先激活卡密"
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
            /* 规则只在这一刻下发：拉取 → 解密 → 校验 → 进内存，然后才起隧道。
               拉不到就不开防护，避免出现「隧道在跑但规则是空的」这种假防护。 */
            self.loadRules(force: false, requireTunnel: false) { loaded in
                guard loaded else {
                    self.switching = false
                    self.busy = false
                    self.publishResult(self.rulesError ?? "规则下发失败，防护未开启")
                    completion()
                    return
                }
                self.tunnel.start { result in
                    WorkQueue.main {
                        self.switching = false
                        self.busy = false
                        switch result {
                        case .success:
                            self.wantsProtection = true
                            self.autoStartCount = 0
                            if let notice = ConfigStore.shared.cloudNotice, !notice.isEmpty {
                                self.toast = notice
                            }
                        case .failure(let err):
                            /* 隧道没起来，规则也别留在内存里 */
                            RuleService.shared.clear()
                            self.refreshRules()
                            self.toast = "启动失败：\(err.localizedDescription)"
                        }
                        completion()
                    }
                }
            }
        }
    }

    // MARK: - 拦截模式（1.2.3）

    /// 切换模式：落盘 → 隧道在跑就按新配置重连一次（约 2 秒断流）
    func setMode(_ mode: InterceptMode) {
        guard interceptMode != mode else { return }
        ConfigStore.shared.mode = mode
        interceptMode = mode

        guard tunnel.isConnected else {
            publishResult("已切换为\(mode.title) · \(mode.brief)")
            return
        }
        /* 隧道已经在跑：配置是启动时带进去的，必须重连才会按新路由生效 */
        toast = "已切换为\(mode.title)，正在重新应用…"
        switching = true
        tunnel.restart()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.switching = false
        }
    }

    /// #PORT 段开关：同样要重连才生效
    func setPortBlocking(_ on: Bool) {
        guard portBlocking != on else { return }
        ConfigStore.shared.portBlocking = on
        portBlocking = on
        if tunnel.isConnected {
            toast = on ? "端口拦截已开启，正在重新应用…" : "端口拦截已关闭，正在重新应用…"
            switching = true
            tunnel.restart()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.switching = false
            }
        } else {
            publishResult(on ? "端口拦截已开启（核心端口仍然放行）" : "端口拦截已关闭")
        }
    }

    // MARK: - 版本

    func checkUpdate() {
        /* 强制更新一旦判下来就先钉在本地：只要没真的升到那个版本，
           这一次检查哪怕被 hook 成「无更新」，界面照样锁在更新页。
           真正的兜底在服务端：低于最低 build 的客户端拿不到规则包。 */
        if UpdatePin.build > AppConfig.buildNumber {
            updateInfo = UpdatePin.info()
            forceUpdate = true
        }

        VersionService.shared.check(pin: pin) { [weak self] hasUpdate, force, info, ops in
            guard let self = self else { return }

            /* 运维状态先落地：维护页与熔断跟版本弹窗互不影响 */
            WorkQueue.main {
                self.maintenanceReason = ops.maintenance
                    ? (ops.maintenanceReason.isEmpty ? "系统维护中，请稍后再试" : ops.maintenanceReason)
                    : nil
            }
            OpsService.enforce(ops)

            WorkQueue.main {
                if hasUpdate, force, let info = info {
                    UpdatePin.pin(info)
                    self.updateInfo = info
                    self.forceUpdate = true
                    return
                }
                if let info = info, info.build > 0, AppConfig.buildNumber >= info.build {
                    UpdatePin.clear()
                }
                if UpdatePin.build > AppConfig.buildNumber {
                    self.updateInfo = UpdatePin.info()
                    self.forceUpdate = true
                    return
                }
                self.updateInfo = info
                self.forceUpdate = false
                if hasUpdate { self.showUpdate = true }
            }
        }
    }

    // MARK: - 统计

    func pollStats() {
        tunnel.fetchStats { [weak self] obj, channel in
            guard let self = self else { return }
            if !obj.isEmpty {
                self.applyStats(obj, source: channel.isEmpty ? "隧道回包" : channel)
                return
            }
            /* 回包丢了（扩展忙 / 会话刚建立 / 正在切网）：直接读扩展每 2 秒落盘的快照。
               这条通道不依赖消息机制，是「拦截在生效但面板全是 0」的兜底。 */
            let bridged = StatsBridge.read()
            if !bridged.isEmpty {
                self.applyStats(bridged, source: StatsBridge.isFresh(bridged) ? "扩展落盘" : "上次快照")
            }
        }
    }

    private func applyStats(_ obj: [String: Any], source: String) {
        WorkQueue.main {
            self.stats = obj
            self.statsSource = source
        }
    }

    /// 统计字段容错读取
    ///
    /// JSON 往返后数字可能是 Int / NSNumber / Double，甚至被别的字段串成字符串。
    /// 之前用 `as? Int` 一刀切，只要有一个字段被覆盖成字符串（比如 dns 被填成地址），
    /// 那一格就永远显示 0。
    private func num(_ key: String) -> Int {
        if let v = stats[key] as? Int { return v }
        if let v = stats[key] as? NSNumber { return v.intValue }
        if let v = stats[key] as? Double { return Int(v) }
        if let v = stats[key] as? String, let d = Double(v) { return Int(d) }
        return 0
    }

    /// 拦截链路自检：隧道收包 / DNS 查询 / 拦截数 / 路由方案 / 扩展心跳
    /// 收包 0 = 系统流量没进隧道；DNS 0 = DNS 没接管；心跳不新鲜 = 扩展没在跑
    var diagText: String {
        guard !stats.isEmpty else {
            return tunnel.isConnected
                ? "隧道已连接，但扩展没回传统计（三条通道都没通，不是没流量）"
                : "隧道未连接"
        }
        let tunnelPackets = num("tunnel")
        let dns = num("dns")
        let blocked = num("blocked")
        let stray = num("stray")
        let phase = (stats["phase"] as? String) ?? "running"
        let routes = (stats["routes"] as? String) ?? "—"
        var line = "\(interceptMode.shortTitle)模式 · 收包 \(tunnelPackets) · DNS \(dns) · 拦截 \(blocked)"
        if stray > 0 { line += " · 旁路 \(stray)" }
        if let age = StatsBridge.age(stats) { line += " · 心跳 \(age)秒前" }
        /* 1.1.0 起是窄口模型：路由只覆盖规则段 + 假 DNS，不再有「补集装不下」的降级。
           routeCount = 0 说明 IP 层没接管上，只剩域名拦截。 */
        let routeCount = num("routeCount")
        if routeCount == 0 { line += " · 无 IP 路由·仅域名拦截" }
        return line + " · \(phase) · \(routes) · \(statsSource)"
    }

    var blockedText: String { "\(num("blocked"))" }
    var domainText: String { "\(num("domains"))" }
    var tcpText: String { "\(num("tcp"))" }
    var udpText: String { "\(num("udp"))" }
    var connText: String { "\(num("conn"))" }

    var uptimeText: String {
        let s = num("uptime")
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return "\(h)时\(m)分" }
        if m > 0 { return "\(m)分\(sec)秒" }
        return "\(sec)秒"
    }

    func dismissToast() {
        toast = nil
    }
}

/// 强制更新的本地钉子
///
/// 判过一次「必须更新」就落盘，升级到位之前一直有效。
/// 目的很直接：把这次检查 hook 掉、或者断网，都绕不过已经记下来的结论。
private enum UpdatePin {

    private static let buildKey  = "hm.update.forceBuild"
    private static let verKey    = "hm.update.forceVersion"
    private static let urlKey    = "hm.update.forceURL"
    private static let notesKey  = "hm.update.forceNotes"

    private static var d: UserDefaults { .standard }

    static var build: Int { d.integer(forKey: buildKey) }

    static func pin(_ info: AppUpdateInfo) {
        d.set(info.build, forKey: buildKey)
        d.set(info.version, forKey: verKey)
        d.set(info.url, forKey: urlKey)
        d.set(info.notes, forKey: notesKey)
    }

    static func clear() {
        d.removeObject(forKey: buildKey)
        d.removeObject(forKey: verKey)
        d.removeObject(forKey: urlKey)
        d.removeObject(forKey: notesKey)
    }

    static func info() -> AppUpdateInfo {
        AppUpdateInfo(version: d.string(forKey: verKey) ?? "",
                      build: d.integer(forKey: buildKey),
                      url: d.string(forKey: urlKey) ?? "",
                      notes: d.string(forKey: notesKey) ?? "",
                      minVersion: "",
                      force: true)
    }
}
