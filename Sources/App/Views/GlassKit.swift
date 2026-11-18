import SwiftUI

// MARK: - 主题色

enum HK {
    static let bg       = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let bgDeep   = Color(red: 0.03, green: 0.05, blue: 0.11)
    static let cyan     = Color(red: 0.18, green: 0.84, blue: 1.00)
    static let blue     = Color(red: 0.20, green: 0.42, blue: 1.00)
    static let violet   = Color(red: 0.48, green: 0.36, blue: 1.00)
    static let pink     = Color(red: 1.00, green: 0.36, blue: 0.62)
    static let mint     = Color(red: 0.28, green: 0.94, blue: 0.72)
    static let amber    = Color(red: 1.00, green: 0.72, blue: 0.30)
    static let text     = Color.white
    static let textDim  = Color.white.opacity(0.58)
    static let textFaint = Color.white.opacity(0.36)
}

// MARK: - 背景：三层光斑 + 细网格

struct AuroraBackground: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(colors: [HK.bg, HK.bgDeep, HK.bg],
                           startPoint: .top, endPoint: .bottom)

            // 光斑
            Circle()
                .fill(HK.cyan.opacity(0.30))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: -120 + phase * 16, y: -220)

            Circle()
                .fill(HK.violet.opacity(0.32))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 130 - phase * 12, y: -60)

            Circle()
                .fill(HK.pink.opacity(0.20))
                .frame(width: 260, height: 260)
                .blur(radius: 110)
                .offset(x: -60 + phase * 20, y: 300)

            Circle()
                .fill(HK.blue.opacity(0.24))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 100, y: 420)

            // 极细网格，增加"企业级"质感
            GridPattern()
                .stroke(Color.white.opacity(0.028), lineWidth: 0.5)
                .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

struct GridPattern: Shape {
    var step: CGFloat = 34
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x < rect.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height)); x += step }
        var y: CGFloat = 0
        while y < rect.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y)); y += step }
        return p
    }
}

// MARK: - 液态玻璃卡片

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    var corner: CGFloat = 26
    var content: () -> Content

    init(padding: CGFloat = 18, corner: CGFloat = 26, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.corner = corner
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.14), Color.white.opacity(0.03),
                                         Color.white.opacity(0.07)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    // 顶部高光
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Color.white.opacity(0.22), .clear],
                                           startPoint: .top, endPoint: .center)
                        )
                        .blendMode(.plusLighter)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [Color.white.opacity(0.45),
                                                Color.white.opacity(0.08),
                                                Color.white.opacity(0.20)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 14)
    }
}

// MARK: - 胶囊标签

struct GlassPill: View {
    let text: String
    var icon: String? = nil
    var tint: Color = HK.cyan

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(tint.opacity(0.13))
                .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 0.7))
        )
    }
}

// MARK: - 区块标题

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(HK.textDim)
                .kerning(1.4)
            if let s = subtitle {
                Text(s)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(HK.textFaint)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - 数据格

struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = HK.cyan
    var icon: String = "shield.lefthalf.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(HK.textFaint)
            }
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(HK.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(tint.opacity(0.16), lineWidth: 0.7))
        )
    }
}

// MARK: - 主开关（液态玻璃球）

struct PowerOrb: View {
    let on: Bool
    var busy: Bool = false
    var blocked: Bool = false
    @State private var spin: Double = 0
    @State private var pulse: CGFloat = 0

    var body: some View {
        ZStack {
            // 外呼吸光环
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: on
                            ? [HK.cyan.opacity(0.9), HK.violet.opacity(0.2), HK.cyan.opacity(0.9)]
                            : [Color.white.opacity(0.18), Color.white.opacity(0.03), Color.white.opacity(0.18)]),
                        center: .center),
                    lineWidth: 1.2
                )
                .frame(width: 208 + pulse * 26, height: 208 + pulse * 26)
                .rotationEffect(.degrees(spin))
                .blur(radius: 0.4)

            Circle()
                .fill(on ? HK.cyan.opacity(0.24) : Color.white.opacity(0.05))
                .frame(width: 186, height: 186)
                .blur(radius: 42)

            // 玻璃球体
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 158, height: 158)
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: on
                                    ? [HK.cyan.opacity(0.55), HK.blue.opacity(0.30), Color.black.opacity(0.18)]
                                    : [Color.white.opacity(0.22), Color.white.opacity(0.06), Color.black.opacity(0.24)],
                                center: .init(x: 0.32, y: 0.26),
                                startRadius: 4, endRadius: 118)
                        )
                )
                .overlay(
                    Circle().stroke(
                        LinearGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0.12),
                                                Color.white.opacity(0.42)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.1)
                )
                .shadow(color: on ? HK.cyan.opacity(0.55) : Color.black.opacity(0.5),
                        radius: on ? 30 : 18, x: 0, y: on ? 0 : 8)

            // 内部图标 + 文字
            VStack(spacing: 8) {
                if busy {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.1)
                } else if blocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(HK.amber)
                        .shadow(color: HK.amber.opacity(0.7), radius: 14)
                } else {
                    Image(systemName: on ? "shield.fill" : "power")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: on ? HK.cyan.opacity(0.9) : .clear, radius: 14)
                }
                Text(blocked ? "授权失效" : (on ? "运行中" : "开启防护"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(blocked ? HK.amber : .white.opacity(0.88))
                    .kerning(1.2)
            }
        }
        .frame(width: 250, height: 250)
        .onAppear {
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { spin = 360 }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { pulse = 1 }
        }
    }
}

// MARK: - 行条目

struct InfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = HK.text
    var mono: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5, weight: .regular, design: .rounded))
                .foregroundColor(HK.textDim)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold,
                              design: mono ? .monospaced : .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Color.white.opacity(0.14), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 0.6)
    }
}

// MARK: - 醒目公告条（置顶）

struct NoticeBanner: View {
    let title: String
    let content: String
    let updated: String
    @Binding var expanded: Bool

    private var shownText: String {
        if expanded { return content }
        // 收起时最多露 5 行，展开时全文；两种情况都不截断文字内容
        return content
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [HK.amber.opacity(0.95), HK.pink.opacity(0.85)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 30, height: 30)
                        .shadow(color: HK.amber.opacity(0.55), radius: 10)
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(.black.opacity(0.82))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(title.isEmpty ? "最新公告" : title)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundColor(HK.text)
                            .multilineTextAlignment(.leading)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(2)
                        Text("公告")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(HK.amber))
                            .fixedSize()
                        Spacer(minLength: 0)
                    }

                    Text(shownText)
                        .font(.system(size: 12.5, weight: .regular, design: .rounded))
                        .foregroundColor(HK.textDim)
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .lineLimit(expanded ? nil : 5)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    HStack(spacing: 6) {
                        if !updated.isEmpty {
                            Text("更新于 \(updated)")
                                .font(.system(size: 9.5, weight: .regular, design: .rounded))
                                .foregroundColor(HK.textFaint)
                        }
                        Spacer()
                        Text(expanded ? "收起" : "展开全文")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(HK.amber)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(HK.amber)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [HK.amber.opacity(0.20), HK.pink.opacity(0.08), Color.white.opacity(0.03)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(colors: [HK.amber.opacity(0.65), Color.white.opacity(0.10)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: HK.amber.opacity(0.16), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 授权异常横幅

struct AlertBanner: View {
    let text: String
    var actionTitle: String = "去处理"
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(HK.pink)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 7) {
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(HK.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = action {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.black.opacity(0.85))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(HK.pink))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(HK.pink.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(HK.pink.opacity(0.45), lineWidth: 0.9))
        )
    }
}

// MARK: - 小按钮（玻璃质感）

struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var tint: Color = HK.cyan
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .stroke(tint.opacity(0.28), lineWidth: 0.7))
            )
        }
        .buttonStyle(.plain)
    }
}
