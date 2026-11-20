import SwiftUI
import UIKit
import Combine

/// 主界面
struct MainView: View {

    @EnvironmentObject var model: AppModel

    /// iOS 14 上同一个视图挂两个 `.sheet` 只会认最后一个 —— 设置页因此永远弹不出来。
    /// 1.2.3 改成单一 `.sheet(item:)`，弹哪个由这个枚举决定。
    enum ActiveSheet: String, Identifiable {
        case settings, rules
        var id: String { rawValue }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var appear = false

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    header
                        .padding(.top, 6)

                    // 公告：永远在主界面最显眼的位置，云端拉不到也有兜底
                    NoticeBanner(title: model.displayNotice.title,
                                 content: model.displayNotice.content,
                                 updated: MainView.prettyTime(model.displayNotice.updatedAt),
                                 expanded: $model.announcementOpen)
                        .transition(.opacity.combined(with: .move(edge: .top)))

                    // 设置里那些刷新动作的结果，统一回主界面显示
                    if let msg = model.actionResult {
                        ActionResultBanner(text: msg) { model.dismissActionResult() }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // 授权出问题就顶在最上面，讲清原因
                    if let alert = model.authAlert {
                        AlertBanner(text: alert,
                                    actionTitle: model.license.code.isEmpty ? "输入卡密" : "刷新状态",
                                    action: {
                                        if model.license.code.isEmpty {
                                            activeSheet = .settings
                                        } else {
                                            model.verifyNow { _ in }
                                        }
                                    })
                    }

                    hero
                        .padding(.top, 6)

                    quickStats

                    modeSelector

                    RuleSetsStrip { activeSheet = .rules }

                    licenseCard
                    statsSection
                    channelCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 48)
            }

            if model.forceUpdate, let info = model.updateInfo {
                ForceUpdateView(info: info)
            }

            /* 维护模式：服务端一开就盖住整个界面，下方原样显示维护原因 */
            if let reason = model.maintenanceReason {
                MaintenanceView(reason: reason)
                    .transition(.opacity)
                    .zIndex(6)
            }

            if let toast = model.toast {
                VStack {
                    ToastBubble(text: toast)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                        withAnimation(.easeOut(duration: 0.25)) { model.dismissToast() }
                    }
                }
            }
        }
        /* 只留这一个挂载点：iOS 14 的 SwiftUI 同一视图挂两个 sheet，
           只有最后一个会生效（设置页因此打不开）。改成 item 版，
           弹哪个由 activeSheet 决定，14/15 都一样。 */
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .settings: SettingsView().environmentObject(model)
                case .rules:    RulesDetailView().environmentObject(model)
                }
            }
        }
        // 设置里点了刷新：收起设置页，结果在主界面顶部看
        .onReceive(model.$closeSettingsRequest.compactMap { $0 }) { _ in
            withAnimation(.easeInOut(duration: 0.22)) { activeSheet = nil }
        }
        /* 未激活时点圆球 / 点「输入卡密」，统一弹设置页 */
        .onChange(of: model.showLicense) { wants in
            if wants {
                activeSheet = .settings
                model.showLicense = false
            }
        }
        /* iOS 14 只有 .alert(isPresented:content:) 这一套；
           带 role 的按钮 + message 闭包是 iOS 15 的写法，降到 14 会编译不过。 */
        .alert(isPresented: $model.showUpdate) {
            Alert(
                title: Text("发现新版本"),
                message: Text(updateMessage),
                primaryButton: .default(Text("立即更新")) {
                    if let info = model.updateInfo, let url = URL(string: info.url) {
                        UIApplication.shared.open(url)
                    }
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
            model.loadAnnouncement()
            model.refreshRules()
            model.refreshLocal()
            model.pollStats()
        }
    }

    // MARK: - 顶栏

    /// 更新弹窗正文：iOS 14 的 Alert 要一段现成的文字，不能用闭包现场渲染
    private var updateMessage: String {
        guard let info = model.updateInfo else { return "建议更新到最新版本" }
        let notes = info.notes.isEmpty ? "建议更新到最新版本" : info.notes
        return "v\(info.version)\n\(notes)"
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [HK.cyan.opacity(0.42), HK.violet.opacity(0.42)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                    )
                Image(systemName: "cat.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: HK.violet.opacity(0.55), radius: 16, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppConfig.appName)
                    .font(.system(size: 17.5, weight: .bold, design: .rounded))
                    .foregroundColor(HK.text)
                Text("ENTERPRISE INTERCEPT KERNEL")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .kerning(1.35)
                    .foregroundColor(HK.textFaint)
            }

            Spacer()

            if model.verifying {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: HK.cyan))
                    .scaleEffect(0.72)
            }

            Button {
                model.loadAnnouncement()
                activeSheet = .settings
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(HK.text)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                            .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 0.7))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 主开关区

    private var hero: some View {
        VStack(spacing: 10) {
            /* 整个 App 只有这一个开关：点圆球开、再点一次关 */
            PowerOrb(on: model.tunnel.isConnected,
                     busy: model.busy,
                     blocked: !model.authorized)
                .scaleEffect(appear ? (model.tunnel.isConnected ? 1.05 : 1.0) : 0.9)
                .animate(.spring(response: 0.46, dampingFraction: 0.74),
                         value: model.tunnel.isConnected)
                .contentShape(Circle())
                .onTapGesture {
                    let impact = UIImpactFeedbackGenerator(style: model.tunnel.isConnected ? .light : .medium)
                    impact.impactOccurred()
                    model.toggle()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.tunnel.isConnected ? "关闭防护" : "开启防护")
                .accessibilityAddTraits(.isButton)

            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.8), radius: 6)
                Text(statusTitle)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(statusColor)
            }
            .padding(.top, 2)

            Text(statusDetail)
                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                .foregroundColor(HK.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 26)

            Text(model.tunnel.isConnected ? "轻触圆球关闭防护" : "轻触圆球开启防护")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(HK.textFaint.opacity(0.75))
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusColor: Color {
        if model.tunnel.isConnected { return HK.mint }
        return model.authorized ? HK.textDim : HK.pink
    }

    private var statusTitle: String {
        if model.tunnel.isConnected { return "防护运行中" }
        if model.busy { return "正在切换…" }
        return model.authorized ? "防护未开启" : "授权失效"
    }

    private var statusDetail: String {
        if model.tunnel.isConnected {
            return "\(model.interceptMode.shortTitle)模式 · 已拦截 \(model.blockedText) 个请求 · 运行 \(model.uptimeText)"
        }
        if !model.authorized {
            return model.license.code.isEmpty ? "请先在设置里输入卡密激活"
                                              : "卡密状态异常，点上方刷新或重新激活"
        }
        return model.interceptMode == .global
            ? "轻触上方开关，所有流量交给隧道判定"
            : "轻触上方开关，只拦截命中规则的连接"
    }

    // MARK: - 拦截模式（1.2.3）

    /// 规则 / 全局二选一。规则模式是默认档：只把规则命中的流量拉进隧道，
    /// 其余流量维持原样，所以不会出现「一开防护就上不了网」。
    private var modeSelector: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                ForEach(InterceptMode.allCases, id: \.id) { mode in
                    modeButton(mode)
                }
            }
            Text(model.interceptMode.detail)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundColor(HK.textFaint)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
    }

    private func modeButton(_ mode: InterceptMode) -> some View {
        let selected = (model.interceptMode == mode)
        let tint = (mode == .global) ? HK.amber : HK.cyan
        return Button {
            if model.interceptMode != mode {
                let gen = UISelectionFeedbackGenerator()
                gen.selectionChanged()
                model.setMode(mode)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .bold))
                    Text(mode.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                }
                .foregroundColor(selected ? tint : HK.textDim)

                Text(mode == .rules ? "只拦命中规则的" : "全部流量进隧道")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(selected ? HK.textDim : HK.textFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(selected ? tint.opacity(0.16) : Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(selected ? tint.opacity(0.45) : Color.white.opacity(0.10),
                                    lineWidth: selected ? 0.9 : 0.7)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 核心数据

    private var quickStats: some View {
        HStack(spacing: 10) {
            MiniStat(value: model.blockedText, label: "拦截", tint: HK.cyan, icon: "shield.fill")
            MiniStat(value: model.domainText, label: "域名", tint: HK.violet, icon: "globe")
            MiniStat(value: "\(model.ruleCounts.ips + model.ruleCounts.domains + model.rulePorts)",
                     label: "规则", tint: HK.mint, icon: "list.bullet")
        }
    }

    // MARK: - 授权卡

    private var licenseCard: some View {
        GlassCard(padding: 16, corner: 24) {
            VStack(spacing: 13) {
                HStack(spacing: 8) {
                    Text("授权")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(HK.text)
                    Text(model.license.tierLabel)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(HK.violet)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(HK.violet.opacity(0.14))
                        )
                    Spacer()
                    GlassPill(text: model.license.statusText(),
                              icon: model.authorized ? "checkmark.seal.fill" : "lock.fill",
                              tint: model.authorized ? HK.mint : HK.pink)
                }

                DividerLine()

                HStack(spacing: 10) {
                    LicenseCell(title: "卡密",
                                value: model.license.code.isEmpty ? "未激活" : model.license.maskedCode,
                                mono: true,
                                tint: HK.text)
                    LicenseCell(title: "到期",
                                value: model.license.code.isEmpty ? "—" : model.license.expireText,
                                mono: false,
                                tint: model.authorized ? HK.text : HK.amber)
                    LicenseCell(title: "剩余",
                                value: model.license.remainText,
                                mono: false,
                                tint: model.authorized ? HK.mint : HK.amber)
                }

                HStack(spacing: 10) {
                    GlassButton(title: model.verifying ? "校验中…" : "刷新状态",
                                icon: "arrow.triangle.2.circlepath",
                                tint: HK.cyan) {
                        model.verifyNow { _ in }
                    }
                    if !model.authorized {
                        GlassButton(title: "激活卡密", icon: "key.fill", tint: HK.amber) {
                            activeSheet = .settings
                        }
                    } else {
                        GlassButton(title: "规则详情", icon: "list.bullet.rectangle", tint: HK.violet) {
                            activeSheet = .rules
                        }
                    }
                }
            }
        }
    }

    // MARK: - 统计

    private var statsSection: some View {
        VStack(spacing: 10) {
            SectionHeader(title: "实时拦截", subtitle: "REAL-TIME")
            HStack(spacing: 10) {
                StatTile(value: model.blockedText, label: "总拦截", tint: HK.cyan,
                         icon: "shield.lefthalf.fill")
                StatTile(value: model.domainText, label: "域名黑洞", tint: HK.violet,
                         icon: "globe")
            }
            HStack(spacing: 10) {
                StatTile(value: model.tcpText, label: "TCP 断链", tint: HK.pink,
                         icon: "bolt.horizontal.fill")
                StatTile(value: model.connText, label: "HTTPS 拦断", tint: HK.mint,
                         icon: "lock.shield.fill")
            }
        }
    }

    // MARK: - 频道

    private var channelCard: some View {
        GlassCard(padding: 16, corner: 22) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(HK.cyan.opacity(0.16)).frame(width: 38, height: 38)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(HK.cyan)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("官方频道")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(HK.text)
                    Text(AppConfig.channelName)
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textDim)
                }
                Spacer()
                if let url = URL(string: AppConfig.channelURL) {
                    Link(destination: url) {
                        Text("前往")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(HK.cyan)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(HK.cyan.opacity(0.14))
                                            .overlay(Capsule().stroke(HK.cyan.opacity(0.35), lineWidth: 0.7)))
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("\(AppConfig.appName) · 全网最强 · 不采集任何流量内容")
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundColor(HK.textFaint)
            Text("v\(AppConfig.appVersion) · build \(AppConfig.buildNumber)")
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundColor(HK.textFaint.opacity(0.7))
        }
        .padding(.top, 8)
    }

    // MARK: - 工具

    /// 服务端给的是秒级时间戳字符串，转成「11-17 13:20」
    static func prettyTime(_ raw: String) -> String {
        guard let ts = Double(raw), ts > 0 else { return "" }
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 小数据格

private struct MiniStat: View {
    let value: String
    let label: String
    let tint: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(HK.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(HK.textFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7))
        )
    }
}

// MARK: - 授权字段格

private struct LicenseCell: View {
    let title: String
    let value: String
    let mono: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(HK.textFaint)
            Text(value)
                .font(.system(size: 12, weight: .semibold,
                              design: mono ? .monospaced : .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

// MARK: - Toast

struct ToastBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                GlassBlur().clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.7))
            )
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            .padding(.horizontal, 24)
    }
}


/// 强制更新：盖住主界面，只能去下载
struct ForceUpdateView: View {
    let info: AppUpdateInfo

    var body: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(HK.cyan)
                Text("需要更新后才能继续使用")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(HK.text)
                Text("当前 v\(AppConfig.appVersion) · 最新 v\(info.version)")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(HK.textDim)
                if !info.notes.isEmpty {
                    Text(info.notes)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                Button {
                    if let url = URL(string: info.url) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(info.url.isEmpty ? "下载地址未配置" : "前往下载")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundColor(HK.bg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(LinearGradient(colors: [HK.cyan, HK.blue],
                                                     startPoint: .leading, endPoint: .trailing))
                        )
                }
                .disabled(info.url.isEmpty)
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(
                GlassBlur()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            )
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - 操作结果横幅（设置里的刷新结果都显示在这里）

struct ActionResultBanner: View {
    let text: String
    var onClose: () -> Void = {}

    private var isBusy: Bool {
        text.hasSuffix("…") || text.contains("正在")
    }

    private var tint: Color {
        if isBusy { return HK.cyan }
        if text.contains("失败") || text.contains("失效") || text.contains("错误") { return HK.pink }
        return HK.mint
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isBusy ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(HK.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(HK.textFaint)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.30), lineWidth: 0.8)
                )
        )
    }
}


// MARK: - 维护页（1.2.3）

/// 系统维护：盖住主界面，只显示状态和原因
///
/// 服务端在 `/app/version` 里下发维护开关与原因，客户端每 4 分钟拉一次，
/// 正在用的设备也会在几分钟内切到这个页面，不用等重启。
struct MaintenanceView: View {
    let reason: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [HK.amber.opacity(0.9), HK.pink.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 62, height: 62)
                        .shadow(color: HK.amber.opacity(0.45), radius: 22)
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black.opacity(0.82))
                }

                Text("系统维护中")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(HK.text)

                Text(reason)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundColor(HK.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text("维护结束后重新打开应用即可")
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(HK.textFaint)
                    .padding(.top, 2)

                if let url = URL(string: AppConfig.channelURL) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("进度见 \(AppConfig.channelName)")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(HK.cyan)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(HK.cyan.opacity(0.14))
                                        .overlay(Capsule().stroke(HK.cyan.opacity(0.35), lineWidth: 0.7)))
                    }
                    .padding(.top, 6)
                }
            }
            .padding(26)
            .frame(maxWidth: 330)
            .background(
                GlassBlur()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8))
            )
            .padding(.horizontal, 28)
        }
    }
}
