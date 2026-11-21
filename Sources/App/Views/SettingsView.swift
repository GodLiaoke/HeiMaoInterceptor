import SwiftUI
import UIKit

struct SettingsView: View {

    @EnvironmentObject var model: AppModel
    @Environment(\.presentationMode) var presentation
    @State private var copied = false
    /// 卡密输入框（UIKit 版）。用来在页面出现后主动拉起键盘
    @StateObject private var cardFocus = CardCodeFocus()

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
            /* 1.2.8：进页面还没激活就把键盘调起来。
               这里不再用 ScrollViewReader 去 scrollTo —— iOS 14 上它会在 sheet 转场里
               拿到已经释放的滚动容器，是 1.2.7「点设置就闪退」的元凶之一。
               定时器只碰输入框自己，且 focus() 里会先确认字段已经在 window 上。 */
            .onAppear {
                guard model.license.code.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    cardFocus.focus()
                }
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
                    HStack(spacing: 8) {
                        /* 1.2.6：换成 UIKit 的 UITextField（见 CardCodeField.swift）。
                           iOS 14 上原来那个 SwiftUI TextField 点击拿不到焦点，键盘不弹，
                           用户根本打不进卡密。现在原生输入框 + 进页面自动聚焦，
                           再配一个「粘贴」按钮，连打字都不用。 */
                        CardCodeField(text: $model.licenseInput,
                                      placeholder: "输入卡密，如 PQGL-UXW7-YMYF-KC3W",
                                      focusBox: cardFocus,
                                      onCommit: { model.activate(code: model.licenseInput) })
                            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)

                        Button {
                            /* 从剪贴板直接灌进来：iOS 14 上哪怕键盘起不来也能激活 */
                            if let raw = UIPasteboard.general.string {
                                let code = CardCodeField.format(raw)
                                if !code.isEmpty { model.licenseInput = code }
                            }
                            cardFocus.focus()
                        } label: {
                            Text("粘贴")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundColor(HK.cyan)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(HK.cyan.opacity(0.14)))
                                .overlay(Capsule().stroke(HK.cyan.opacity(0.35), lineWidth: 0.7))
                        }
                        .buttonStyle(.plain)
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
    /// 1.2.7：按站长要求把「端口段拦截」开关加回来，独立于拦截模式，默认关闭。
    private var rulesCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "规则库", subtitle: "RULES")
            GlassCard {
                VStack(spacing: 12) {
                    InfoRow(title: "来源", value: model.ruleSource)
                    InfoRow(title: "规则集", value: model.ruleSetCount > 0 ? "\(model.ruleSetCount) 套" : "—")
                    InfoRow(title: "拦截模式", value: model.interceptMode.title)

                    /* 1.2.7：端口段开关加回来了，默认关。规则包 #PORT 段有 2650 个端口，
                       含 53/80/443 —— 默认打开会当场断网，所以默认关；
                       用户自己打开后，核心端口（AppConfig.corePorts）照样放行。 */
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("端口段拦截")
                                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(HK.text)
                                Text("按规则包 #PORT 段拦端口，核心端口始终放行；默认关闭")
                                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                                    .foregroundColor(HK.textFaint)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            /* 1.2.8：不用系统 Toggle。
                               SwitchToggleStyle(tint:) 是 iOS 15 才有的初始化器，
                               iOS 14 上渲染到这一行会直接崩（包里能查到这条动态符号）。
                               自己画一个，只用 iOS 13 就有的 Shape / offset。 */
                            HMInlineSwitch(isOn: model.portBlocking) { on in
                                model.setPortBlocking(on)
                            }
                        }
                    }

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

/// 极简开关（1.2.8）
///
/// 为什么不直接用 `Toggle` + `SwitchToggleStyle(tint:)`：
/// 那个初始化器是 iOS 15.0 起才有的。项目最低支持 iOS 14，
/// 1.2.7 在 iOS 14 上一渲染设置页就崩，包里能查到
/// `SwiftUI.SwitchToggleStyle.init(tint:)` 这条动态符号 —— 系统里根本没有。
///
/// 这里只用 Capsule / Circle / offset / withAnimation，全是 iOS 13 就有的东西，
/// 老系统上不会再出这种「符号不存在」的崩。
private struct HMInlineSwitch: View {
    var isOn: Bool
    var onToggle: (Bool) -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                onToggle(!isOn)
            }
        } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? HK.cyan.opacity(0.90) : Color.white.opacity(0.14))
                    .frame(width: 44, height: 26)
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: Color.black.opacity(0.22), radius: 1.5, x: 0, y: 1)
                    .offset(x: isOn ? 9 : -9)
            }
            .frame(width: 44, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
