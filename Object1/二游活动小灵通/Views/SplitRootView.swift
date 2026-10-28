import SwiftUI
import SwiftData

// MARK: - Vertical Bar (iPhone Duo)

extension EnvironmentValues {
    // True where the system shows the vertical bar: the Duo's outer display and
    // its inner display in landscape. False on other iPhones.
    @Entry var hasVerticalBar = false

    // True at regular width (unfolded Duo, Pro Max landscape), where the sidebar is shown
    // and pages use their wide layout. Pages also drop the polka-dot background there,
    // which gets too busy across the wide display.
    @Entry var isWideLayout = false

    // Shared by the game cards on the 游戏 tab and the zoom transition into a game's page.
    @Entry var gameZoomNamespace: Namespace.ID? = nil
}

// Reports UIKit's verticalBarEdge trait, which SwiftUI doesn't expose.
struct VerticalBarReader: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: UIView {
        var onChange: ((Bool) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            if #available(iOS 27.1, *) {
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (view: ReaderView, _) in
                    view.report()
                }
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        private func report() {
            guard #available(iOS 27.1, *) else { return }
            let hasBar = traitCollection.verticalBarEdge != .unspecified
            // Deferred so SwiftUI state isn't changed during a view update.
            DispatchQueue.main.async { [weak self] in self?.onChange?(hasBar) }
        }
    }
}

// Puts 首页 / 游戏 / 设置 and 返回 into the system vertical bar on every page that uses it.
private struct VerticalBarNavigation: ViewModifier {
    @Environment(\.hasVerticalBar) private var hasVerticalBar
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        // The availability check never changes at runtime. The bar's state is checked inside the
        // toolbar, so folding or switching tabs doesn't swap the page for a rebuilt copy.
        if #available(iOS 27.1, *) {
            content.toolbar {
                if hasVerticalBar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        tabButton(.home, title: "首页", icon: "waveform", selectedIcon: "waveform")
                        tabButton(.games, title: "游戏", icon: "gamecontroller", selectedIcon: "gamecontroller.fill")
                        tabButton(.settings, title: "设置", icon: "gearshape", selectedIcon: "gearshape.fill")
                    }
                    .axisBehavior(.verticalPreferred)

                    ToolbarItem(placement: .bottomBar) {
                        Button { router.goBack() } label: {
                            Label("返回", systemImage: "chevron.left")
                        }
                        .disabled(!router.canGoBack)
                    }
                    .axisBehavior(.verticalPreferred)
                }
            }
        } else {
            content
        }
    }

    private func tabButton(_ tab: AppTab, title: String, icon: String, selectedIcon: String) -> some View {
        let selected = router.tab == tab
        return Button { router.selectTab(tab) } label: {
            Label(title, systemImage: selected ? selectedIcon : icon)
        }
        .tint(selected ? Color.hoyoPink : Color.hoyoNavy)
    }
}

extension View {
    func verticalBarNavigation() -> some View {
        modifier(VerticalBarNavigation())
    }
}

// MARK: - Game Route Destination

struct GameRouteDestination: View {
    let route: GameRoute
    var showsBackButton = true

    @Query private var customGames: [CustomGame]
    @Environment(\.hasVerticalBar) private var hasVerticalBar

    var body: some View {
        // With the vertical bar, 返回 lives there instead of in each page's toolbar.
        let back = showsBackButton && !hasVerticalBar
        Group {
            switch route {
            case .remote(let game):
                GameDetailView(game: game, showsBackButton: back)
            case .custom(let id):
                if let game = customGames.first(where: { $0.id == id }) {
                    CustomGameDetailView(game: game, showsBackButton: back)
                } else {
                    AnimatedEmptyState(title: "游戏已删除", message: "这个自定义游戏已经不在了。")
                }
            }
        }
        .verticalBarNavigation()
    }
}

// MARK: - Sidebar

// Shown beside the page at regular width; slides in when the Duo unfolds.
struct SplitSidebar: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.hasVerticalBar) private var hasVerticalBar
    @Environment(ActivityService.self) private var service
    @Environment(PurchaseService.self) private var purchaseService
    @Query private var prefsQuery: [UserPreferences]
    @Query private var customGames: [CustomGame]
    @State private var showAISearch = false
    @State private var showPremium = false
    @State private var addLimitMessage: String? = nil
    @State private var cheerHop = 0

    private static let cheerWidth: CGFloat = 240

    private var followedGames: [HoYoGame] { prefsQuery.first?.followedGames ?? [] }
    private var stats: ActivityStats { ActivityStats(remoteEvents: service.events, customGames: customGames) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 6) {
                    miniStats
                        .padding(.bottom, 6)

                    // Unfolded landscape: these three are in the vertical bar instead.
                    if !hasVerticalBar {
                        navRow(.home, icon: "waveform", title: "首页")
                        navRow(.games, icon: "gamecontroller.fill", title: "游戏总览")
                        navRow(.settings, icon: "gearshape.fill", title: "设置")
                    }

                    Text("我的游戏")
                        .font(.system(size: 11, weight: .black))
                        .kerning(1)
                        .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                        .padding(.horizontal, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 2)

                    ForEach(followedGames) { game in
                        gameRow(
                            route: .remote(game), emoji: game.emoji, name: game.displayName,
                            color: game.cardHeaderColor, active: stats.activeCount(for: game),
                            progress: stats.progress(for: game), soonest: stats.soonestRemaining(for: game)
                        )
                    }
                    ForEach(customGames) { game in
                        gameRow(
                            route: .custom(game.id), emoji: game.emoji, name: game.name,
                            color: game.accentColor, active: game.activeEvents.count,
                            progress: stats.progress(for: game), soonest: stats.soonestRemaining(for: game)
                        )
                    }

                    Button { openAddGame() } label: {
                        Label("添加游戏", systemImage: "plus")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Color.hoyoMint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle())
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                // Leave room to scroll the last game above Wanwan.
                .padding(.bottom, 24 + Self.cheerWidth * WanwanCheerView.aspectRatio)
            }
        }
        // Wanwan stands on the bottom edge of the screen, in the space below the game list.
        .overlay(alignment: .bottomLeading) {
            WanwanCheerView(
                width: Self.cheerWidth,
                stats: stats,
                hasGames: !followedGames.isEmpty || !customGames.isEmpty,
                offline: service.errorMessage != nil,
                hopTrigger: cheerHop
            )
            .padding(.leading, 12)
            .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: stats.totalPending) { old, new in
            if old > 0 && new == 0 { cheerHop += 1 }
        }
        .background(Color.hoyoCardBg.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.hoyoNavy.opacity(0.12)).frame(width: 1).ignoresSafeArea()
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $showAISearch) { AIGameSearchView() }
        .sheet(isPresented: $showPremium) { PremiumView() }
        .alert("自定义游戏已达上限", isPresented: Binding(
            get: { addLimitMessage != nil },
            set: { if !$0 { addLimitMessage = nil } }
        )) {
            if !purchaseService.isPremium {
                Button("升级会员") {
                    addLimitMessage = nil
                    showPremium = true
                }
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text(addLimitMessage ?? "")
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("二游活动小灵通")
                .font(.system(size: 19, weight: .black))
            Text("小灵通婉婉为你的活动保驾护航")
                .font(.system(size: 11, weight: .bold))
                .opacity(0.75)
        }
        .foregroundStyle(Color.hoyoNavy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        // With the status bar moved into the vertical bar there's no top inset, so leave room here.
        .padding(.top, 30)
        .padding(.bottom, 16)
        .background {
            ZStack {
                Color.hoyoBlush
                Canvas { ctx, size in
                    for row in stride(from: 0, through: size.height, by: 14) {
                        for col in stride(from: 0, through: size.width, by: 14) {
                            let r = CGRect(x: col - 1.5, y: row - 1.5, width: 3, height: 3)
                            ctx.fill(Path(ellipseIn: r), with: .color(.white.opacity(0.5)))
                        }
                    }
                }
            }
            // Inside the ScrollView, ignoresSafeArea doesn't reach the status bar area (unfolded
            // portrait) or the overscroll above it, so extend the band upward by hand instead.
            .padding(.top, -300)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hoyoNavy).frame(height: 2.5)
        }
    }

    // MARK: Mini Stats

    private var miniStats: some View {
        HStack(spacing: 6) {
            statPill(count: stats.totalPending,    label: "待完成",  bg: Color.hoyoPink,   fg: .white)
            statPill(count: stats.totalEndingSoon, label: "即将结束", bg: Color.hoyoYellow, fg: Color.hoyoNavy)
            statPill(count: stats.totalDone,       label: "已完成",  bg: Color.hoyoMint,   fg: .white)
        }
    }

    private func statPill(count: Int, label: String, bg: Color, fg: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.system(size: 17, weight: .black))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9.5, weight: .bold))
                .opacity(0.85)
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(bg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hoyoNavy, lineWidth: 2))
    }

    // MARK: Rows

    private func navRow(_ tab: AppTab, icon: String, title: String) -> some View {
        let selected = router.game == nil && router.tab == tab
        return Button { router.selectTab(tab) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .foregroundStyle(Color.hoyoNavy)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selected ? Color.hoyoBlush : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hoyoNavy, lineWidth: selected ? 2 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(CardPressStyle())
    }

    private func gameRow(route: GameRoute, emoji: String, name: String, color: Color, active: Int,
                         progress: (done: Int, total: Int), soonest: TimeInterval?) -> some View {
        let selected = router.game == route
        let fraction = progress.total > 0 ? CGFloat(progress.done) / CGFloat(progress.total) : 0
        return Button {
            // Switch straight to the game, like a sidebar selection, instead of animating a push.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { router.openGame(route) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(emoji)
                        .font(.system(size: 16))
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(active)")
                        .font(.system(size: 11, weight: .black))
                        .monospacedDigit()
                        .foregroundStyle(active > 0 ? Color.hoyoNavy : Color.hoyoNavy.opacity(0.4))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(active > 0 ? Color.hoyoYellow : .clear, in: Capsule())
                        .overlay(Capsule().stroke(active > 0 ? Color.hoyoNavy : Color.hoyoNavy.opacity(0.2), lineWidth: 1.5))
                }

                Capsule()
                    .fill(selected ? Color.white.opacity(0.3) : Color.hoyoNavy.opacity(0.12))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(selected ? Color.white : color)
                                .frame(width: geo.size.width * fraction)
                        }
                    }

                HStack {
                    Text("已完成 \(progress.done)/\(progress.total)")
                    Spacer()
                    Text(soonest.map { "最近 " + ActivityStats.compactRemaining($0) } ?? "已全清")
                }
                .font(.system(size: 10, weight: .bold))
                .opacity(0.7)
            }
            .foregroundStyle(selected ? .white : Color.hoyoNavy)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 9)
            .background(selected ? color : color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) {
                if !selected {
                    Capsule().fill(color).frame(width: 4).padding(.vertical, 8)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hoyoNavy, lineWidth: selected ? 2 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(CardPressStyle())
    }

    private func openAddGame() {
        guard customGames.count < purchaseService.tier.maxCustomGames else {
            addLimitMessage = purchaseService.tier.customGameLimitMessage(currentCount: customGames.count)
            return
        }
        showAISearch = true
    }
}
