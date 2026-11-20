import Foundation

/// 防破解心跳（1.2.4）
///
/// 独立于卡密的一条极轻请求：不带卡密、不看授权，只回答一个问题 ——
/// 「这台设备此刻能不能连上验证站」。
///
/// 为什么单独做一条：
///   - 熔断要即时。卡密校验有窗口、有宽限，开关落下去要好几分钟；
///     心跳 25 秒一次，后台一关熔断，最迟半分钟客户端就恢复
///   - 破解手段里最常见的是「断网 + 改包」，把授权相关的请求全挡掉。
///     这条心跳失败到阈值直接熔断，挡不挡得住都要付代价
///   - 通道仍然是 v4 裸密文，抓包看不出这是心跳，也伪造不了（签名含路由 + iv + 时间戳）
///
/// 强度与误伤之间取的是：冷启动给 90 秒宽限（正常网络启动几乎立刻成功），
/// 之后连续 6 次拿不到结果（约 150 秒）才熔断。短暂进电梯、切基站不会误杀；
/// 长时间断网、被劫持、被改包则必然命中。
final class PulseService {

    static let shared = PulseService()

    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var started = false
    private var running = false
    private var everOK = false
    private var fails = 0
    private var began = Date()
    private var foreground = true
    private var pinCode = ""

    /// 每次拿到云端结论都会回调（主线程），用来刷新维护页 / 顶部状态
    var onState: ((OpsState) -> Void)?

    private init() {}

    // MARK: - 生命周期

    func start(pin: String) {
        lock.lock()
        if started {
            pinCode = pin
            lock.unlock()
            return
        }
        started = true
        pinCode = pin
        began = Date()
        lock.unlock()

        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "hm.pulse"))
        t.schedule(deadline: .now() + 0.6,
                   repeating: AppConfig.pulseInterval,
                   leeway: .milliseconds(600))
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        t.resume()

        lock.lock()
        timer = t
        lock.unlock()
    }

    /// App 进后台暂停（iOS 会把定时器冻住，计数继续只会误杀）
    func setForeground(_ f: Bool) {
        lock.lock()
        let changed = foreground != f
        foreground = f
        if f && changed {
            /* 回前台立刻补一次，不等下一个周期 */
            fails = 0
        }
        lock.unlock()
        if f && changed { tick() }
    }

    /// 诊断用：当前状态一行字
    var statusLine: String {
        lock.lock(); defer { lock.unlock() }
        return everOK ? "心跳正常 · 失败 \(fails)" : "心跳未建立 · 失败 \(fails)"
    }

    // MARK: - 心跳

    private func tick() {
        lock.lock()
        if running || !foreground {
            lock.unlock()
            return
        }
        running = true
        let pin = pinCode
        lock.unlock()

        guard !pin.isEmpty else {
            lock.lock(); running = false; lock.unlock()
            return
        }

        SecureChannel.post(AppConfig.pulseRoute,
                           params: ["build": AppConfig.buildNumber,
                                    "ver": AppConfig.appVersion],
                           pin: pin) { [weak self] result in
            guard let self = self else { return }
            self.lock.lock()
            self.running = false
            self.lock.unlock()

            switch result {
            case .success(let obj):
                let state = OpsService.parse(obj)
                self.lock.lock()
                self.everOK = true
                self.fails = 0
                self.lock.unlock()
                DispatchQueue.main.async {
                    self.onState?(state)
                }
                /* 云端结论是唯一执行熔断的地方 */
                OpsService.apply(state)

            case .failure:
                self.registerFailure()
            }
        }
    }

    private func registerFailure() {
        lock.lock()
        let elapsed = Date().timeIntervalSince(began)
        let seenOK = everOK
        let limit = AppConfig.pulseMaxFails
        if !seenOK && elapsed < AppConfig.pulseGrace {
            /* 冷启动宽限：这段时间内还没连上过不计数 */
            lock.unlock()
            return
        }
        /* 从没连通过、本地也没有熔断钉子：说明可能是「刚装就没网」的正常用户，
           不能因为没网就把人崩掉。改过包的人拿不到规则也等于不能用，
           这里不误杀，防护强度由「连通过之后再断」这条路保证。 */
        if !seenOK && !OpsService.pendingFuse {
            lock.unlock()
            return
        }
        fails += 1
        let hit = fails >= limit
        lock.unlock()

        if hit {
            /* 到阈值还连不上：有本地熔断钉子就照钉子崩，没有也按异常环境处理。
               这条是「断网即熔断」的落点，改包 / 劫持 / 拔网线都绕不过去。 */
            OpsService.failClosed()
        }
    }
}
