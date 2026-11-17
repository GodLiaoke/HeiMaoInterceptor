import SwiftUI

/// 主界面上的「规则集」条：一眼看到后台到底下发了哪几套
struct RuleSetsStrip: View {

    @EnvironmentObject var model: AppModel
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(HK.violet.opacity(0.16)).frame(width: 32, height: 32)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(HK.violet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.ruleSetCount > 0 ? "\(model.ruleSetCount) 套规则" : "云端规则")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .foregroundColor(HK.text)
                        if model.rulesLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: HK.cyan))
                                .scaleEffect(0.55)
                        }
                    }
                    Text(model.ruleSets.isEmpty ? model.ruleSource : model.ruleSets.joined(separator: " · "))
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textFaint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 6)

                Text(model.ruleVersionText)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(HK.textFaint)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(HK.textFaint.opacity(0.7))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.7))
            )
        }
        .buttonStyle(.plain)
    }
}

/// 规则详情：多套规则的名字、每套条数、合并后的统计、同步时间
struct RulesDetailView: View {

    @EnvironmentObject var model: AppModel
    @Environment(\.presentationMode) var presentation

    private var mergedIPs: Int { model.ruleCounts.ips }
    private var mergedDomains: Int { model.ruleCounts.domains }
    private var mergedPorts: Int { model.rulePorts }

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        summaryCard
                        setsCard
                        explainCard

                        Button {
                            model.loadRules(force: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12.5, weight: .bold))
                                Text(model.rulesLoading ? "正在同步…" : "同步云端规则")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(HK.cyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(HK.cyan.opacity(0.13))
                                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(HK.cyan.opacity(0.32), lineWidth: 0.8)))
                        }
                        .disabled(model.rulesLoading)
                        .opacity(model.rulesLoading ? 0.6 : 1)

                        if let err = model.rulesError, !err.isEmpty {
                            Text(err)
                                .font(.system(size: 11.5, weight: .regular, design: .rounded))
                                .foregroundColor(HK.pink)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("云端规则")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(HK.text)
                Text("RULES · 后台勾选哪几套就下发哪几套")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .kerning(1.0)
                    .foregroundColor(HK.textFaint)
            }
            Spacer()
            Button {
                presentation.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(HK.textDim)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var summaryCard: some View {
        GlassCard(padding: 16, corner: 22) {
            VStack(spacing: 12) {
                HStack {
                    Text(model.ruleSource)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundColor(HK.text)
                        .lineLimit(1)
                    Spacer()
                    GlassPill(text: model.rulesLoading ? "同步中" : (RuleService.shared.isLoaded ? "已加载" : "未加载"),
                              icon: RuleService.shared.isLoaded ? "checkmark.circle.fill" : "tray",
                              tint: RuleService.shared.isLoaded ? HK.mint : HK.amber)
                }

                DividerLine()

                HStack(spacing: 10) {
                    CountCell(value: mergedIPs, label: "IP", tint: HK.cyan)
                    CountCell(value: mergedDomains, label: "域名", tint: HK.violet)
                    CountCell(value: mergedPorts, label: "端口", tint: HK.mint)
                }

                DividerLine()

                InfoRow(title: "下发版本", value: model.ruleVersionText, mono: true)
                InfoRow(title: "规则集", value: model.ruleSetCount > 0 ? "\(model.ruleSetCount) 套" : "—")
                InfoRow(title: "最近同步", value: syncText)
            }
        }
    }

    private var setsCard: some View {
        VStack(spacing: 9) {
            SectionHeader(title: "下发中的规则集", subtitle: "SETS")
            GlassCard {
                VStack(spacing: 12) {
                    if model.ruleSetDetails.isEmpty {
                        /* 老服务端不带明细，就只显示名字 */
                        if model.ruleSets.isEmpty {
                            HStack {
                                Text("服务端没有返回规则集名称")
                                    .font(.system(size: 11.5, weight: .regular, design: .rounded))
                                    .foregroundColor(HK.textFaint)
                                Spacer()
                            }
                        } else {
                            ForEach(Array(model.ruleSets.enumerated()), id: \.offset) { idx, name in
                                setRow(index: idx + 1, name: name, version: "", counts: nil)
                            }
                        }
                    } else {
                        ForEach(Array(model.ruleSetDetails.enumerated()), id: \.offset) { idx, item in
                            let name = (item["name"] as? String) ?? "规则集 \(idx + 1)"
                            let ver = (item["version"] as? String) ?? ""
                            let ip = (item["ip"] as? Int) ?? (item["ip_count"] as? Int) ?? 0
                            let dom = (item["domain"] as? Int) ?? (item["domain_count"] as? Int) ?? 0
                            let port = (item["port"] as? Int) ?? (item["port_count"] as? Int) ?? 0
                            setRow(index: idx + 1, name: name,
                                   version: ver, counts: (ip, dom, port))
                        }
                    }
                }
            }
        }
    }

    private func setRow(index: Int, name: String, version: String,
                        counts: (Int, Int, Int)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(HK.violet)
                .frame(width: 20, height: 20)
                .background(Circle().fill(HK.violet.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(HK.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let c = counts {
                    Text("\(c.0) IP · \(c.1) 域名 · \(c.2) 端口")
                        .font(.system(size: 10.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textFaint)
                    if !version.isEmpty {
                        Text("版本 \(version)")
                            .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                            .foregroundColor(HK.textFaint.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var explainCard: some View {
        GlassCard(padding: 14, corner: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(HK.cyan)
                    Text("多套规则会合并成一个加密包下发")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundColor(HK.text)
                }
                Text("后台可以同时勾选多套规则，服务端按勾选顺序合并、去重后加密下发。App 只拿一个包，所以开启速度和单套一样；这里显示的是每一套的来源和条数。")
                    .font(.system(size: 10.5, weight: .regular, design: .rounded))
                    .foregroundColor(HK.textFaint)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var syncText: String {
        guard let d = model.ruleUpdatedAt else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: d)
    }
}

private struct CountCell: View {
    let value: Int
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(HK.textFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.05)))
    }
}
