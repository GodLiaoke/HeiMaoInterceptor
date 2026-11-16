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

                    licenseCard
                    deviceCard
                    rulesCard
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
                            model.refreshLicense()
                        } label: {
                            Text("刷新状态")
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
                            value: model.license.authorized ? "已授权" : "未授权",
                            valueColor: model.license.authorized ? HK.mint : HK.amber)
                    InfoRow(title: "到期时间",
                            value: model.license.authorized ? model.license.expireText : "—")
                    if let kid = model.license.configKid {
                        InfoRow(title: "配置版本", value: kid, mono: true)
                    }
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
                    InfoRow(title: "IP 规则", value: "\(model.ruleCounts.ips) 条")
                    InfoRow(title: "域名规则", value: "\(model.ruleCounts.domains) 条")
                    DividerLine()
                    HStack(spacing: 10) {
                        Button {
                            model.refreshLicense()
                            model.refreshRules()
                            model.toast = "规则已同步"
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
                            model.loadAnnouncement()
                            model.toast = "公告已刷新"
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
                    InfoRow(title: "应用", value: "\(AppConfig.appName) v1.0.0")
                    InfoRow(title: "兼容", value: "iOS 15.0 – iOS 27")
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
