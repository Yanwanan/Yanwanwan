import SwiftUI

// MARK: - HoYo Theme Palette (Anime Quest Board)

extension Color {
    nonisolated static let hoyoPink     = Color(hex: "FF6BAB")   // 主色：棉花糖粉
    nonisolated static let hoyoMint     = Color(hex: "39C5BB")   // 副色：初音未来青
    nonisolated static let hoyoYellow   = Color(hex: "FFE082")   // 点缀：游戏金
    nonisolated static let hoyoDark     = Color(hex: "3B2060")   // 轮廓/文字：深紫
    nonisolated static let hoyoBg       = Color(hex: "FFF8FC")   // 背景：奶白粉
    nonisolated static let hoyoLavender = Color(hex: "DDB4F0")   // 薰衣草紫
    nonisolated static let hoyoNavy     = Color(hex: "3B2060")   // 卡片边框/文字：深紫
    nonisolated static let hoyoCardBg   = Color.white            // 卡片内容区背景
    nonisolated static let hoyoBlush    = Color(hex: "FFC4DD")   // 宽屏侧栏：淡粉

    nonisolated init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 200, 200, 200)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

// MARK: - Card Press Button Style

struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(HoyoMotion.micro, value: configuration.isPressed)
    }
}

enum HoyoMotion {
    nonisolated static let micro = Animation.spring(response: 0.22, dampingFraction: 0.72)
    nonisolated static let card = Animation.spring(response: 0.36, dampingFraction: 0.80)
    nonisolated static let layout = Animation.spring(response: 0.46, dampingFraction: 0.86)
}

// MARK: - Cartoon Button Press

struct CartoonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .offset(y: configuration.isPressed && !reduceMotion ? 2 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Animated Empty State

struct AnimatedEmptyState: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    let title: String
    let message: String
    var systemImage: String = "gamecontroller.fill"

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.hoyoYellow)
                    .offset(x: 39, y: floating ? -29 : -23)
                    .opacity(floating ? 1 : 0.45)

                Image(systemName: systemImage)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(Color.hoyoPink)
                    .offset(y: floating && !reduceMotion ? -4 : 2)
            }
            .frame(height: 64)

            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)

            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                .padding(.horizontal, 28)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

// MARK: - Adaptive Two Columns

// Side by side when both columns fit at their minimum width, otherwise stacked.
// Driven by the space actually available, not by device or orientation.
// A Layout (rather than switching between HStack and VStack) keeps the two views'
// identity, so folding or unfolding animates them into place instead of rebuilding them.
struct AdaptiveTwoColumn<Leading: View, Trailing: View>: View {
    var minColumnWidth: CGFloat = 300
    var spacing: CGFloat = 20
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        AdaptiveTwoColumnLayout(minColumnWidth: minColumnWidth, spacing: spacing) {
            leading
            trailing
        }
    }
}

private struct AdaptiveTwoColumnLayout: Layout {
    var minColumnWidth: CGFloat
    var spacing: CGFloat

    private func isSideBySide(_ width: CGFloat) -> Bool {
        width >= minColumnWidth * 2 + spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        if isSideBySide(width) {
            let column = ProposedViewSize(width: (width - spacing) / 2, height: nil)
            let height = subviews.map { $0.sizeThatFits(column).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let row = ProposedViewSize(width: width, height: nil)
        let heights = subviews.map { $0.sizeThatFits(row).height }
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if isSideBySide(bounds.width) {
            let columnWidth = (bounds.width - spacing) / 2
            for (index, subview) in subviews.enumerated() {
                let x = bounds.minX + CGFloat(index) * (columnWidth + spacing)
                subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: columnWidth, height: nil))
            }
        } else {
            var y = bounds.minY
            for subview in subviews {
                let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: nil))
                y += size.height + spacing
            }
        }
    }
}

extension View {
    @ViewBuilder
    func gameNavigationSource<ID: Hashable>(id: ID, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
