import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject var model: AppModel
    @Environment(\.presentationMode) var presentation
    @State private var copied = false

    /// 本机安装包代码段指纹（`__TEXT,__text` 的 SHA-256 前 16 位）
    ///
    /// 这一段重签不会变、改代码必变，用户拿它跟下载页公布的指纹对一下，
    /// 就能判断手上这份是不是官方发布的那份。
    static let codeFingerprint: String = {
        guard let path = Bundle.main.executablePath,
              let d = BinarySeal.codeDigest(of: path) else { return "—" }
        let hex = String(d.prefix(16))
        return hex.replacingOccurrences(of: "(?<=.{4})", with: " ", options: .regularExpression)
    }()

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
                    aboutCard

                    Text("全网最强 · \(AppConfig.channelName)")
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// 规则卡只给「用户需要知道的」：来源、套数、版本、模式。
    ///
    /// 1.2.4：删掉了 IP / 域名 / 端口的分项条数、规则集名字和「端口段拦截」开关。
    /// 那些是规则包内部结构（#IP / #DOMAIN / #PORT / #DIRECT 段），
    /// 露在界面上既容易被拿去做指纹，也让人误以为要自己调。
    /// 端口段现在由模式决定：全局模式开、规则模式关，用户不需要也不该看见这个开关。
    private var rulesCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "规则库", subtitle: "RULES")
            GlassCard {
                VStack(spacing: 12) {
                    InfoRow(title: "来源", value: model.ruleSource)
                    InfoRow(title: "规则集", value: model.ruleSetCount > 0 ? "\(model.ruleSetCount) 套" : "—")
                    InfoRow(title: "拦截模式", value: model.interceptMode.title)
                    InfoRow(title: "下发版本", value: model.ruleVersionText, mono: true)

                    DividerLine()

                    HStack(spacing: 10) {
                        Button {
                            model.runQuickAction(.rules)
                        } label: {
                            Text(model.rulesLoading ? "同步中…" : "同步云端规则")
                                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                .foregroundColor(HK.cyan)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .fill(HK.cyan.opacity(0.12)))
                        }
                        .disabled(model.rulesLoading)

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

    // MARK: - 关于

    private var aboutCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "关于", subtitle: "ABOUT")
            GlassCard {
                VStack(spacing: 12) {
                    InfoRow(title: "应用", value: "\(AppConfig.appName) v\(AppConfig.appVersion)")
                    InfoRow(title: "版本", value: "v\(AppConfig.appVersion) · build \(AppConfig.buildNumber)")
                    InfoRow(title: "拦截状态", value: model.diagText, multiline: true)
                    InfoRow(title: "兼容", value: "iOS 14.0 – iOS 27（含 26 / 27）")
                    InfoRow(title: "内核", value: "Packet Tunnel · 用户态协议栈")
                    InfoRow(title: "代码指纹", value: Self.codeFingerprint, multiline: true)
                    DividerLine()
                    if let url = URL(string: AppConfig.channelURL) {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("加入官方频道 \(AppConfig.channelName)")
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
