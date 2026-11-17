import SwiftUI
import UIKit

/// 主界面
struct MainView: View {

    @EnvironmentObject var model: AppModel
    @State private var showSettings = false
    @State private var appear = false

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    topBar
                        .padding(.top, 8)

                    PowerOrb(on: model.tunnel.isConnected, busy: model.busy)
                        .padding(.vertical, 6)
                        .onTapGesture {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            model.toggle()
                        }
                        .opacity(appear ? 1 : 0)
                        .scaleEffect(appear ? 1 : 0.92)

                    statusLine

                    statusCard
                    statsSection
                    if let ann = model.announcement, !ann.content.isEmpty {
                        announcementCard(ann)
                    }
                    channelCard
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 48)
            }

            if model.forceUpdate, let info = model.updateInfo {
                ForceUpdateView(info: info)
            }

            // Toast
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
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(model)
        }
        .alert("发现新版本", isPresented: $model.showUpdate) {
            Button("稍后", role: .cancel) { }
            Button("立即更新") {
                if let info = model.updateInfo, let url = URL(string: info.url) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            if let info = model.updateInfo {
                Text("v\(info.version)\n\(info.notes.isEmpty ? "建议更新到最新版本" : info.notes)")
            } else {
                Text("建议更新到最新版本")
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
            model.refreshRules()
            model.refreshLocal()
            model.pollStats()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [HK.cyan.opacity(0.35), HK.violet.opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 42, height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 0.8))
                Image(systemName: "cat.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.white)
            }
            .shadow(color: HK.violet.opacity(0.5), radius: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppConfig.appName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(HK.text)
                Text("ENTERPRISE INTERCEPT KERNEL")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .kerning(1.3)
                    .foregroundColor(HK.textFaint)
            }

            Spacer()

            Button {
                model.loadAnnouncement()
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(HK.text)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.7))
                    )
            }
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.tunnel.isConnected ? HK.mint : HK.textFaint)
                .frame(width: 6, height: 6)
            Text(model.tunnel.statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(model.tunnel.isConnected ? HK.mint : HK.textDim)
            Text("·")
                .foregroundColor(HK.textFaint)
            Text(model.tunnel.isConnected ? "运行 \(model.uptimeText)" : "轻触上方开启")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(HK.textFaint)
        }
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        GlassCard {
            VStack(spacing: 13) {
                HStack {
                    Text("授权状态")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(HK.text)
                    Spacer()
                    GlassPill(text: model.license.statusText(),
                              icon: model.authorized ? "checkmark.seal.fill" : "lock.fill",
                              tint: model.authorized ? HK.mint : HK.amber)
                }
                DividerLine()
                InfoRow(title: "到期时间",
                        value: model.license.code.isEmpty ? "未激活卡密" : model.license.expireText,
                        valueColor: model.authorized ? HK.text : HK.amber)
                InfoRow(title: "剩余时间", value: model.license.remainText)
                InfoRow(title: "规则库来源",
                        value: model.ruleSource,
                        valueColor: HK.text)
                InfoRow(title: "规则规模",
                        value: "\(model.ruleCounts.ips) IP · \(model.ruleCounts.domains) 域名")
                InfoRow(title: "规则版本", value: model.ruleSource)
                if !model.authorized {
                    Button {
                        showSettings = true
                    } label: {
                        Text("激活卡密")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(HK.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(LinearGradient(colors: [HK.cyan, HK.blue],
                                                         startPoint: .leading, endPoint: .trailing))
                            )
                    }
                    .padding(.top, 2)
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
                StatTile(value: model.udpText, label: "UDP 丢弃", tint: HK.mint,
                         icon: "waveform.path.ecg")
            }
        }
    }

    // MARK: - 公告

    private func announcementCard(_ ann: LicenseClient.Announcement) -> some View {
        VStack(spacing: 10) {
            SectionHeader(title: "公告", subtitle: "NOTICE")
            GlassCard(padding: 16, corner: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(HK.amber)
                        Text(ann.title.isEmpty ? "最新公告" : ann.title)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundColor(HK.text)
                        Spacer()
                    }
                    Text(ann.content)
                        .font(.system(size: 12.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textDim)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    if !ann.updatedAt.isEmpty {
                        Text(ann.updatedAt)
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .foregroundColor(HK.textFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("公益频道")
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
            Text("黑猫公益 · 永久免费 · 不采集任何流量内容")
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundColor(HK.textFaint)
            Text("v\(AppConfig.appVersion) · build \(AppConfig.buildNumber)")
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundColor(HK.textFaint.opacity(0.7))
        }
        .padding(.top, 8)
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
                Capsule().fill(.ultraThinMaterial)
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
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            )
            .padding(.horizontal, 28)
        }
    }
}
