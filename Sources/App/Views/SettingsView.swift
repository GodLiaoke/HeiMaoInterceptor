import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject var model: AppModel
    @Environment(\.presentationMode) var presentation
    @State private var copied = false

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header

                    announcementCard
                    licenseCard
                    deviceCard
                    rulesCard
                    httpsCard
                    aboutCard

                    Text("公益免费 · \(AppConfig.channelName)")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textFaint)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("设置")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(HK.text)
            Spacer()
            Button {
                presentation.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(HK.textDim)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - 公告（主界面已展示，这里只留刷新入口）

    private var announcementCard: some View {
        GlassCard(padding: 14, corner: 18) {
            HStack(spacing: 10) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(HK.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("公告在主界面顶部")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundColor(HK.text)
                    Text(model.displayNotice.title)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textFaint)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    model.runQuickAction(.notice)
                } label: {
                    Text("刷新")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(HK.cyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    // MARK: - 卡密

    private var licenseCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "卡密授权", subtitle: "LICENSE")
            GlassCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        TextField("", text: $model.licenseInput)
                            .placeholder(when: model.licenseInput.isEmpty) {
                                Text("输入卡密，如 PQGL-UXW7-YMYF-KC3W")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(HK.textFaint)
                            }
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(HK.text)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .keyboardType(.asciiCapable)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.22))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7))
                    )

                    HStack(spacing: 10) {
                        Button {
                            model.activate(code: model.licenseInput)
                        } label: {
                            HStack(spacing: 6) {
                                if model.busy {
                                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: HK.bg))
                                        .scaleEffect(0.7)
                                }
                                Text("激活")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(HK.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(LinearGradient(colors: [HK.cyan, HK.blue],
                                                         startPoint: .leading, endPoint: .trailing))
                            )
                        }

                        Button {
                            model.runQuickAction(.status)
                        } label: {
                            Text(model.verifying ? "校验中…" : "刷新状态")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(HK.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .stroke(Color.white.opacity(0.16), lineWidth: 0.7))
                                )
                        }
                    }

                    DividerLine()

                    InfoRow(title: "当前状态",
                            value: model.license.statusText(),
                            valueColor: model.authorized ? HK.mint : HK.amber)
                    InfoRow(title: "卡密到期",
                            value: model.license.code.isEmpty ? "—" : model.license.expireText)
                    InfoRow(title: "剩余时间", value: model.license.remainText)
                    InfoRow(title: "本次校验", value: model.license.sessionText)
                    InfoRow(title: "最后确认",
                            value: model.license.verifiedAt.map { SettingsView.timeText($0) } ?? "未校验")
                    InfoRow(title: "规则版本", value: model.ruleSource)
                }
            }
        }
    }

    // MARK: - 设备码

    private var deviceCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "设备信息", subtitle: "DEVICE")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(title: "设备码", value: model.pin, mono: true)

                    Button {
                        UIPasteboard.general.string = model.pin
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                            Text(copied ? "已复制" : "复制设备码")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(HK.cyan)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(HK.cyan.opacity(0.12))
                                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                    .stroke(HK.cyan.opacity(0.3), lineWidth: 0.7)))
                    }
                }
            }
        }
    }

    // MARK: - 规则

    private var rulesCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "规则库", subtitle: "RULES")
            GlassCard {
                VStack(spacing: 12) {
                    InfoRow(title: "来源", value: model.ruleSource)
                    InfoRow(title: "规则集", value: model.ruleSetCount > 0 ? "\(model.ruleSetCount) 套" : "—")
                    if !model.ruleSets.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("下发内容")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(HK.textFaint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            FlowChips(items: model.ruleSets)
                        }
                    }
                    InfoRow(title: "IP 规则", value: "\(model.ruleCounts.ips) 条")
                    InfoRow(title: "域名规则", value: "\(model.ruleCounts.domains) 条")
                    InfoRow(title: "端口规则", value: "\(model.rulePorts) 条")
                    InfoRow(title: "下发版本", value: model.ruleVersionText, mono: true)
                    DividerLine()
                    HStack(spacing: 10) {
                        Button {
                            model.runQuickAction(.rules)
                        } label: {
                            Text("同步云端规则")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundColor(HK.cyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .fill(HK.cyan.opacity(0.12)))
                        }
                        Button {
                            model.runQuickAction(.notice)
                        } label: {
                            Text("刷新公告")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundColor(HK.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .fill(Color.white.opacity(0.08)))
                        }
                    }
                }
            }
        }
    }

    // MARK: - HTTPS 说明

    private var httpsCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "HTTPS 拦截", subtitle: "TLS")
            GlassCard {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(HK.mint)
                        Text("不需要安装证书")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(HK.mint)
                        Spacer()
                    }

                    Text("本应用不破解 TLS 内容，所以不用装根证书、也不用在「关于本机」里信任描述文件。")
                        .font(.system(size: 11.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textDim)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    DividerLine()

                    HttpsRow(icon: "globe", title: "域名层",
                             detail: "命中的域名直接在 DNS 阶段返回黑洞地址，HTTPS 根本连不上")
                    HttpsRow(icon: "bolt.horizontal.fill", title: "连接层",
                             detail: "连接黑洞地址的 TCP / UDP 在隧道内被当场断开，立刻失败而不是等超时")
                    HttpsRow(icon: "antenna.radiowaves.left.and.right", title: "SNI 兜底",
                             detail: "系统加密 DNS 被接管；仍走内置 DoH 的应用属于已知盲区")

                    Text("要「看清页面内容、替换成拦截提示页」才需要中间人证书。那种做法要把每个网站的证书动态签出来，性能和隐私成本都很高，本应用不做。")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textFaint)
                        .lineSpacing(2.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "关于", subtitle: "ABOUT")
            GlassCard {
                VStack(spacing: 12) {
                    InfoRow(title: "应用", value: "\(AppConfig.appName) v\(AppConfig.appVersion)")
                    InfoRow(title: "版本", value: "v\(AppConfig.appVersion) · build \(AppConfig.buildNumber)")
                    InfoRow(title: "兼容", value: "iOS 15.0 – iOS 27（含 26 / 27）")
                    InfoRow(title: "内核", value: "Packet Tunnel · 用户态协议栈")
                    DividerLine()
                    if let url = URL(string: AppConfig.channelURL) {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("加入公益频道 \(AppConfig.channelName)")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(HK.cyan)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - placeholder 辅助

extension View {
    func placeholder<Content: View>(when shouldShow: Bool,
                                    alignment: Alignment = .leading,
                                    @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}


// MARK: - 规则集名称小标签

/// 自动换行的标签流；规则集名字长短不一，单行放不下就往下折
struct FlowChips: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(HK.violet)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(HK.violet.opacity(0.13))
                                            .overlay(Capsule().stroke(HK.violet.opacity(0.28), lineWidth: 0.7)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 按字数粗略折行，iOS 15 没有 Layout 协议，手动分组最稳
    private var rows: [[String]] {
        var out: [[String]] = []
        var current: [String] = []
        var width = 0
        for name in items {
            let w = name.count + 2
            if width + w > 18, !current.isEmpty {
                out.append(current)
                current = []
                width = 0
            }
            current.append(name)
            width += w
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

// MARK: - HTTPS 说明行

private struct HttpsRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(HK.cyan)
                .frame(width: 18, height: 18)
                .background(Circle().fill(HK.cyan.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(HK.text)
                Text(detail)
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(HK.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
