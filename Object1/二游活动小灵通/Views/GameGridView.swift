import SwiftUI
import SwiftData

// MARK: - Home: game card grid

struct GameGridView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ActivityService.self) private var service
    @Environment(AppRouter.self) private var router
    @Environment(\.isWideLayout) private var isWideLayout
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsQuery: [UserPreferences]
    @Query private var customGames: [CustomGame]
    @State private var showCompleteGuide = false
    @State private var cardsAppeared     = false
    @State private var wasRefreshing = false
    @State private var showRefreshSuccess = false
    @State private var hadErrorBeforeRefresh = false
    @State private var showNetworkRecovered = false
    @State private var cheerHop = 0
    private static let cheerWidth: CGFloat = 140

    private var prefs: UserPreferences? { prefsQuery.first }
    private var followedGames: [HoYoGame] { prefs?.followedGames ?? [] }

    var body: some View {
        Group {
            if service.isLoading && service.events.isEmpty {
                skeletonGrid
            } else if followedGames.isEmpty && customGames.isEmpty {
                emptyState
            } else {
                cardGrid
            }
        }
        .sheet(isPresented: $showCompleteGuide) { CompleteTaskGuideSheet() }
        .fontDesign(.rounded)
        .onAppear {
            cardsAppeared = false
            withAnimation { cardsAppeared = true }
        }
        .refreshable {
            if let p = prefs { await service.refresh(preferences: p) }
        }
        .task(id: prefs?.followedGameSlugs.joined()) {
            guard let p = prefs else { return }
            service.loadFromCache(preferences: p)
            await service.refresh(preferences: p)
        }
        .onChange(of: service.isLoading) { oldValue, newValue in
            if newValue {
                wasRefreshing = true
                hadErrorBeforeRefresh = service.errorMessage != nil
                showRefreshSuccess = false
            } else if oldValue && wasRefreshing && !service.events.isEmpty && service.errorMessage == nil {
                wasRefreshing = false
                showRefreshSuccess = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if hadErrorBeforeRefresh {
                    showNetworkRecovered = true
                }
                hadErrorBeforeRefresh = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    withAnimation(.easeOut(duration: 0.2)) { showRefreshSuccess = false }
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeOut(duration: 0.2)) { showNetworkRecovered = false }
                }
            }
        }
        .onChange(of: service.errorMessage) { _, newValue in
            if newValue != nil { hadErrorBeforeRefresh = true }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        ZStack {
            Color.hoyoBg.ignoresSafeArea(edges: .top)
            VStack(spacing: 16) {
                customHeader
                Spacer()
                AnimatedEmptyState(
                    title: "还未选择游戏",
                    message: "老大还没选要盯的游戏，婉婉先待命。"
                )
                Spacer()
            }
        }
    }

    // MARK: Skeleton

    private var skeletonGrid: some View {
        ZStack {
            Color.hoyoBg.ignoresSafeArea(edges: .top)
            ScrollView {
                VStack(spacing: 0) {
                    customHeader
                    LazyVStack(spacing: 20) {
                        ForEach(0..<2, id: \.self) { _ in
                            GameCardSkeleton()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
            }
        }
    }

    // MARK: Card Grid

    private var cardGrid: some View {
        ZStack {
            Color.hoyoBg.ignoresSafeArea(edges: .top)

            // Polka-dot background
            if !isWideLayout {
                Canvas { ctx, size in
                    for row in stride(from: 0, through: size.height, by: 22) {
                        for col in stride(from: 0, through: size.width, by: 22) {
                            let r = CGRect(x: col - 1.5, y: row - 1.5, width: 3, height: 3)
                            ctx.fill(Path(ellipseIn: r), with: .color(Color.hoyoPink.opacity(0.12)))
                        }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            ScrollView {
                VStack(spacing: 0) {
                    customHeader

                    LazyVStack(spacing: 20) {
                        if showNetworkRecovered {
                            Label("网络已恢复，活动已更新", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.hoyoMint)
                                .font(.footnote.weight(.bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.trailing, isWideLayout ? 0 : Self.cheerWidth)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else if let msg = service.errorMessage {
                            Label(msg, systemImage: "wifi.exclamationmark")
                                .foregroundStyle(.orange)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.trailing, isWideLayout ? 0 : Self.cheerWidth)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        overviewCard
                        AdaptiveTwoColumn {
                            recentlyEndedCard
                        } trailing: {
                            gameListCard
                        }

                        // Room for the floating tab bar, which the wide layout doesn't have.
                        Color.clear.frame(height: isWideLayout ? 4 : 110)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.78), value: service.errorMessage)
                }
            }
        }
    }

    // MARK: Custom Header

    private var customHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("老大的活动清单")
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(Color.hoyoNavy)
                    Rectangle()
                        .fill(Color.hoyoPink)
                        .frame(height: 4)
                        .cornerRadius(2)
                        .padding(.trailing, 36)
                }
                Spacer()
                HStack(spacing: 10) {
                    if !service.events.isEmpty && (service.isLoading || showRefreshSuccess) {
                        ZStack {
                            if service.isLoading {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .transition(.opacity)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundStyle(Color.hoyoMint)
                                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 22, height: 22)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.65), value: service.isLoading)
                    }
                    // ? button — thick square cartoon style
                    Button { showCompleteGuide = true } label: {
                        Image(systemName: "questionmark")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Color.hoyoNavy)
                            .frame(width: 40, height: 40)
                            .background(Color.hoyoCardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hoyoNavy, lineWidth: 2.5))
                            .shadow(color: Color.hoyoNavy.opacity(0.20), radius: 0, x: 2, y: 2)
                    }
                    .buttonStyle(CartoonPressStyle())
                }
            }

            // Date badge — thick cartoon pill
            HStack(spacing: 7) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Color.hoyoYellow)
                Text(todayLabel)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color.hoyoNavy)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 2))
            .shadow(color: Color.hoyoNavy.opacity(0.18), radius: 0, x: 2, y: 2)
            .overlay(Capsule().fill(Color.white.opacity(showRefreshSuccess ? 0.20 : 0)))
            .scaleEffect(showRefreshSuccess && !reduceMotion ? 1.035 : 1)
            .animation(.easeInOut(duration: 0.28), value: showRefreshSuccess)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }

    // MARK: - Overview Stats

    private var stats: ActivityStats { ActivityStats(remoteEvents: service.events, customGames: customGames) }
    private var totalPending: Int    { stats.totalPending }
    private var totalEndingSoon: Int { stats.totalEndingSoon }
    private var totalDone: Int       { stats.totalDone }

    // Unified recent item for mixing RemoteEvent + CustomEvent
    private struct RecentItem: Identifiable {
        let id: String
        let title: String
        let gameEmoji: String
        let gameName: String
        let endDate: Date
        let isDone: Bool
    }

    private var recentItems: [RecentItem] {
        let sevenDays = 7.0 * 86400
        var items: [RecentItem] = []
        for e in service.events where !e.isDone && e.remaining > 0 && e.remaining <= sevenDays {
            items.append(RecentItem(id: e.id, title: e.title,
                                    gameEmoji: e.game.emoji, gameName: e.game.displayName,
                                    endDate: e.endDate, isDone: e.isDone))
        }
        for g in customGames {
            for e in g.events where !e.isDone && e.remaining > 0 && e.remaining <= sevenDays {
                items.append(RecentItem(id: e.id, title: e.title,
                                        gameEmoji: g.emoji, gameName: g.name,
                                        endDate: e.endDate, isDone: e.isDone))
            }
        }
        return items.sorted { $0.endDate < $1.endDate }
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            dashSectionHeader(icon: "chart.bar.fill", iconColor: Color.hoyoPink, title: "今日速报")

            HStack(spacing: 10) {
                statPill(count: totalPending,    label: "待完成",  bg: Color.hoyoPink,   fg: .white)
                statPill(count: totalEndingSoon, label: "即将结束", bg: Color.hoyoYellow, fg: Color.hoyoNavy)
                statPill(count: totalDone,       label: "已完成",  bg: Color.hoyoMint,   fg: .white)
            }
        }
        .padding(16)
        .background(Color.hoyoCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hoyoNavy, lineWidth: 2.5))
        .shadow(color: Color.hoyoNavy.opacity(0.22), radius: 0, x: 3, y: 3)
        // Wanwan stands behind the card holding up her ledger; the card hides her lower half.
        // Unfolded, she stands at the bottom of the sidebar instead.
        .background(alignment: .topTrailing) {
            if !isWideLayout {
                WanwanCheerView(width: Self.cheerWidth, stats: stats, hasGames: !followedGames.isEmpty || !customGames.isEmpty,
                                offline: service.errorMessage != nil, hopTrigger: cheerHop)
                    .offset(x: -10, y: -(Self.cheerWidth * WanwanCheerView.aspectRatio - 14))
            }
        }
        .onChange(of: totalPending) { old, new in
            if old > 0 && new == 0 { cheerHop += 1 }
        }
    }

    @ViewBuilder
    private func statPill(count: Int, label: String, bg: Color, fg: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(fg)
                .contentTransition(.numericText(value: Double(count)))
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: count)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(fg.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hoyoNavy, lineWidth: 2))
    }

    // MARK: - Recently Ended Card

    private var recentlyEndedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            dashSectionHeader(icon: "hourglass", iconColor: Color.hoyoYellow, title: "临期活动")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if recentItems.isEmpty {
                Text("7 天内没有快结束的活动，婉婉先盯着。")
                    .font(.subheadline)
                    .foregroundStyle(Color.hoyoNavy.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(recentItems.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.hoyoNavy.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                    }
                    HStack(spacing: 12) {
                        Text(item.gameEmoji)
                            .font(.system(size: 18))
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.hoyoNavy.opacity(0.07))
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.hoyoNavy)
                                .lineLimit(1)
                            Text(item.gameName)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.hoyoNavy.opacity(0.35))
                        }

                        Spacer()

                        let days = Int(item.endDate.timeIntervalSinceNow) / 86400
                        let hours = (Int(item.endDate.timeIntervalSinceNow) % 86400) / 3600
                        let remainLabel = days > 0 ? "\(days)天\(hours)时" : "\(hours)时"
                        let isUrgent = item.endDate.timeIntervalSinceNow <= 2 * 86400
                        Text(remainLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isUrgent ? Color.hoyoPink : Color.hoyoNavy)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(
                                (isUrgent ? Color.hoyoPink : Color.hoyoNavy).opacity(0.10),
                                in: Capsule()
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color.hoyoCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hoyoNavy, lineWidth: 2.5))
        .shadow(color: Color.hoyoNavy.opacity(0.22), radius: 0, x: 3, y: 3)
    }

    // MARK: - Game List Card

    private var gameListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            dashSectionHeader(icon: "gamecontroller.fill", iconColor: Color(hex: "6B5EA8"), title: "我的游戏")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            if followedGames.isEmpty && customGames.isEmpty {
                Text("还没有要盯的游戏")
                    .font(.subheadline)
                    .foregroundStyle(Color.hoyoNavy.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(Array(followedGames.enumerated()), id: \.element.rawValue) { idx, game in
                    if idx > 0 {
                        Rectangle().fill(Color.hoyoNavy.opacity(0.07)).frame(height: 1).padding(.horizontal, 16)
                    }
                    NavigationLink(value: GameRoute.remote(game)) {
                        gameListRow(emoji: game.emoji, name: game.displayName,
                                    count: activeCount(for: game), color: game.cardHeaderColor)
                    }
                    .buttonStyle(CardPressStyle())
                }
                ForEach(Array(customGames.enumerated()), id: \.element.id) { idx, game in
                    Rectangle().fill(Color.hoyoNavy.opacity(0.07)).frame(height: 1).padding(.horizontal, 16)
                    NavigationLink(value: GameRoute.custom(game.id)) {
                        gameListRow(emoji: game.emoji, name: game.name,
                                    count: game.activeEvents.count, color: game.accentColor)
                    }
                    .buttonStyle(CardPressStyle())
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
        }
        .background(Color.hoyoCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hoyoNavy, lineWidth: 2.5))
        .shadow(color: Color.hoyoNavy.opacity(0.22), radius: 0, x: 3, y: 3)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8), value: customGames.map(\.id))
    }

    @ViewBuilder
    private func gameListRow(emoji: String, name: String, count: Int, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(color.opacity(0.15))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(color.opacity(0.30), lineWidth: 1.5))
                )

            Text(name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.hoyoNavy)

            Spacer()

            if count > 0 {
                Text("\(count) 个活动")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.hoyoNavy)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.hoyoYellow)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 1.5))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.hoyoNavy.opacity(0.30))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Dashboard Section Header

    @ViewBuilder
    private func dashSectionHeader(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)
            Spacer()
        }
    }

    // MARK: Helpers

    private func activeCount(for game: HoYoGame) -> Int {
        stats.activeCount(for: game)
    }
}

// MARK: - Games Tab

struct GamesTabView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(ActivityService.self) private var service
    @Environment(AppRouter.self) private var router
    @Environment(\.isWideLayout) private var isWideLayout
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(\.modelContext)       private var modelContext
    @Query private var prefsQuery:  [UserPreferences]
    @Query private var customGames: [CustomGame]
    @State private var showAISearch  = false
    @State private var showPremium   = false
    @State private var cardsAppeared = false
    @State private var showAddGameSuccess = false
    @Environment(\.gameZoomNamespace) private var gameNavigationAnimation
    @State private var addLimitMessage: String? = nil

    private var prefs:        UserPreferences? { prefsQuery.first }
    private var followedGames: [HoYoGame]      { prefs?.followedGames ?? [] }

    var body: some View {
        ZStack {
            Color.hoyoBg.ignoresSafeArea(edges: .top)

            if !isWideLayout {
                Canvas { ctx, size in
                    for row in stride(from: 0, through: size.height, by: 22) {
                        for col in stride(from: 0, through: size.width, by: 22) {
                            let r = CGRect(x: col - 1.5, y: row - 1.5, width: 3, height: 3)
                            ctx.fill(Path(ellipseIn: r), with: .color(Color.hoyoPink.opacity(0.12)))
                        }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            if followedGames.isEmpty && customGames.isEmpty {
                VStack(spacing: 16) {
                    gamesHeader
                    Spacer()
                    AnimatedEmptyState(
                        title: "还没有游戏",
                        message: "点右上角 + 添加自定义游戏，或在设置中关注米哈游游戏。"
                    )
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        gamesHeader

                        // One column on phones, two when the Duo unfolds.
                        VStack(spacing: 20) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20, alignment: .top)],
                                      spacing: isWideLayout ? 28 : 20) {
                                gameCards
                            }
                            .padding(.top, isWideLayout ? 12 : 0)
                            footer
                                .padding(.bottom, isWideLayout ? 24 : 110)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8), value: customGames.map(\.id))
                    }
                }
            }
        }
        .sheet(isPresented: $showAISearch) { AIGameSearchView() }
        .onChange(of: customGames.count) { oldCount, newCount in
            guard newCount > oldCount else { return }
            playAddGameSuccess()
        }
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
        .fontDesign(.rounded)
        .onAppear {
            cardsAppeared = false
            withAnimation { cardsAppeared = true }
        }
    }

    // MARK: Header

    private var gamesHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("我的游戏")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color.hoyoNavy)
                Rectangle()
                    .fill(Color.hoyoPink)
                    .frame(height: 4)
                    .cornerRadius(2)
                    .padding(.trailing, 36)
            }
            Spacer()
            Button { openAddGame() } label: {
                Image(systemName: showAddGameSuccess ? "checkmark" : "plus")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.hoyoPink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hoyoNavy, lineWidth: 2.5))
                    .contentTransition(.symbolEffect(.replace))
                    .rotationEffect(.degrees(showAddGameSuccess ? 360 : 0))
                    .shadow(color: Color.hoyoNavy.opacity(0.20), radius: 0, x: 2, y: 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func openAddGame() {
        guard customGames.count < purchaseService.tier.maxCustomGames else {
            addLimitMessage = purchaseService.tier.customGameLimitMessage(currentCount: customGames.count)
            return
        }
        showAISearch = true
    }

    private func playAddGameSuccess() {
        showAddGameSuccess = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.easeOut(duration: 0.2)) { showAddGameSuccess = false }
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var gameCards: some View {
        ForEach(Array(followedGames.enumerated()), id: \.element.rawValue) { index, game in
            NavigationLink(value: GameRoute.remote(game)) {
                GameCard(
                    game: game,
                    activeCount: activeCount(for: game),
                    totalCount: totalCount(for: game),
                    urgentEvent: urgentEvent(for: game),
                    topEvents: topEvents(for: game)
                )
            }
            .buttonStyle(CardPressStyle())
            .gameNavigationSource(id: game.rawValue, in: gameNavigationAnimation)
            .opacity(cardsAppeared ? 1 : 0)
            .offset(y: cardsAppeared ? 0 : 28)
            .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(index) * 0.09), value: cardsAppeared)
        }

        ForEach(Array(customGames.enumerated()), id: \.element.id) { index, game in
            NavigationLink(value: GameRoute.custom(game.id)) {
                CustomGameCard(game: game)
            }
            .buttonStyle(CardPressStyle())
            .gameNavigationSource(id: game.id, in: gameNavigationAnimation)
            .opacity(cardsAppeared ? 1 : 0)
            .offset(y: cardsAppeared ? 0 : 28)
            .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(followedGames.count + index) * 0.09), value: cardsAppeared)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    private var footer: some View {
        Text("✦ 以上就是婉婉的今日速报 ✦")
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(Color.hoyoPink.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    // MARK: Helpers

    private var stats: ActivityStats { ActivityStats(remoteEvents: service.events, customGames: customGames) }

    private func activeCount(for game: HoYoGame) -> Int {
        stats.activeCount(for: game)
    }

    private func totalCount(for game: HoYoGame) -> Int {
        stats.totalCount(for: game)
    }

    private func urgentEvent(for game: HoYoGame) -> RemoteEvent? {
        service.events
            .filter { $0.game == game && $0.remaining > 0 && !$0.isDone }
            .min(by: { $0.remaining < $1.remaining })
    }

    private func topEvents(for game: HoYoGame) -> [RemoteEvent] {
        Array(
            service.events
                .filter { $0.game == game && $0.remaining > 0 && !$0.isDone }
                .sorted { $0.remaining < $1.remaining }
                .prefix(2)
        )
    }
}

// MARK: - Game Card Skeleton

struct GameCardSkeleton: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.primary.opacity(0.12))
                .frame(height: 80)

            RoundedRectangle(cornerRadius: 0)
                .fill(Color.primary.opacity(0.05))
                .frame(height: 120)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(shimmerOverlay)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.hoyoNavy, lineWidth: 2.5)
        )
        .shadow(color: Color.hoyoNavy.opacity(0.18), radius: 0, x: 2, y: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear,               location: 0),
                    .init(color: .white.opacity(0.25), location: 0.4),
                    .init(color: .white.opacity(0.4),  location: 0.5),
                    .init(color: .white.opacity(0.25), location: 0.6),
                    .init(color: .clear,               location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w * 2)
            .offset(x: phase * w)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Game Card

struct GameCard: View {
    let game: HoYoGame
    let activeCount: Int
    let totalCount: Int
    var urgentEvent: RemoteEvent? = nil
    var topEvents: [RemoteEvent] = []

    var body: some View {
        VStack(spacing: 0) {
            boardHeader

            if !topEvents.isEmpty {
                VStack(spacing: 10) {
                    ForEach(topEvents) { event in
                        MiniEventRow(event: event, game: game)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.hoyoCardBg)
            } else {
                HStack {
                    Text(totalCount == 0 ? "这轮清空啦，老大歇会儿吧 🎉" : "全清啦，婉婉记下了！")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.hoyoNavy.opacity(0.40))
                        .padding(.vertical, 20)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .background(Color.hoyoCardBg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.hoyoNavy, lineWidth: 3)
        )
        .overlay(alignment: .topTrailing) {
            activityBadge
                .offset(x: -10, y: -12)
        }
        .fontDesign(.rounded)
    }

    private var activityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .black))
            Text("\(activeCount) 个活动")
                .font(.system(size: 12, weight: .black))
        }
        .foregroundStyle(Color.hoyoNavy)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.hoyoYellow)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 2))
    }

    private var boardHeader: some View {
        HStack(spacing: 12) {
            Text(game.emoji)
                .font(.system(size: 30))
                .frame(width: 58, height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.92))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.60), lineWidth: 2))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(game.displayName)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.white)
                Text("QUEST BOARD · 进行中")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.80))
                    .kerning(0.8)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .padding(.trailing, 76)
        .background(game.cardHeaderColor)
        .overlay(alignment: .trailing) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .overlay(Circle().stroke(.white.opacity(0.40), lineWidth: 1.5))
                    .frame(width: 30, height: 30)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.trailing, 14)
        }
    }
}

// MARK: - Mini Event Row (inside GameCard)

struct MiniEventRow: View {
    let event: RemoteEvent
    let game: HoYoGame

    private var isUrgent: Bool { event.urgency == .critical || event.urgency == .warning }

    private var compactRemaining: String {
        let rem = Int(event.remaining)
        guard rem > 0 else { return "已结束" }
        let days    = rem / 86400
        let hours   = (rem % 86400) / 3600
        let minutes = (rem % 3600) / 60
        if days  > 0 { return "\(days)天\(hours)时" }
        if hours > 0 { return "\(hours)时\(minutes)分" }
        return "\(minutes)分"
    }

    var body: some View {
        HStack(spacing: 10) {
            // Left accent bar
            Capsule()
                .fill(isUrgent ? Color.hoyoPink : game.cardHeaderColor)
                .frame(width: 5, height: 36)

            // Icon circle
            ZStack {
                Circle()
                    .fill(isUrgent ? Color.hoyoPink.opacity(0.15) : game.cardHeaderColor.opacity(0.12))
                    .frame(width: 32, height: 32)
                    .overlay(Circle().stroke(isUrgent ? Color.hoyoPink : game.cardHeaderColor, lineWidth: 1.5))
                Text(isUrgent ? "!" : "▶")
                    .font(.system(size: isUrgent ? 15 : 10, weight: .black))
                    .foregroundStyle(isUrgent ? Color.hoyoPink : game.cardHeaderColor)
            }

            // Title
            Text(event.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.hoyoNavy)
                .lineLimit(1)

            Spacer(minLength: 4)

            // Countdown pill
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .bold))
                Text(compactRemaining)
                    .font(.system(size: 12, weight: .black))
            }
            .foregroundStyle(isUrgent ? .white : Color.hoyoNavy)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isUrgent ? Color.hoyoPink : Color.hoyoYellow)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 1.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.hoyoCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isUrgent ? Color.hoyoPink : Color.hoyoNavy.opacity(0.20), lineWidth: 2)
        )
    }
}

// MARK: - Custom Game Card

struct CustomGameCard: View {
    let game: CustomGame

    private var activeCount: Int { game.activeEvents.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(game.emoji)
                    .font(.system(size: 30))
                    .frame(width: 58, height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.92))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.60), lineWidth: 2))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                    Text("QUEST BOARD · 进行中")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.80))
                        .kerning(0.8)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .padding(.trailing, 76)
            .background(game.accentColor)
            .overlay(alignment: .trailing) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .overlay(Circle().stroke(.white.opacity(0.40), lineWidth: 1.5))
                        .frame(width: 30, height: 30)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.trailing, 14)
            }

            // Events body
            let topEvents = Array(game.activeEvents.prefix(2))
            if !topEvents.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(topEvents.enumerated()), id: \.element.id) { _, event in
                        HStack(spacing: 10) {
                            Capsule()
                                .fill(game.accentColor)
                                .frame(width: 5, height: 36)
                            ZStack {
                                Circle()
                                    .fill(game.accentColor.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(game.accentColor, lineWidth: 1.5))
                                Text("▶")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(game.accentColor)
                            }
                            Text(event.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.hoyoNavy)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            HStack(spacing: 3) {
                                Image(systemName: "clock").font(.system(size: 10, weight: .bold))
                                Text(event.remainingText.replacingOccurrences(of: "剩余 ", with: ""))
                                    .font(.system(size: 12, weight: .black))
                            }
                            .foregroundStyle(Color.hoyoNavy)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Color.hoyoYellow)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 1.5))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.hoyoCardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hoyoNavy.opacity(0.20), lineWidth: 2))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.hoyoCardBg)
            } else {
                HStack {
                    Text("暂无活动，婉婉先待命 🎉")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.hoyoNavy.opacity(0.40))
                        .padding(.vertical, 20)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .background(Color.hoyoCardBg)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.hoyoNavy, lineWidth: 3)
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .black))
                Text("\(activeCount) 个活动")
                    .font(.system(size: 12, weight: .black))
            }
            .foregroundStyle(Color.hoyoNavy)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.hoyoYellow)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 2))
            .offset(x: -10, y: -12)
        }
        .fontDesign(.rounded)
    }
}

// MARK: - Wanwan Cheer

// 婉婉举着账本轻轻摇摆；全部清完时冒出「全清啦！」，刚清完那一下还会蹦一下。点她会说话。
// Shown behind the 今日速报 card on the home page, or at the bottom of the sidebar when unfolded.
struct WanwanCheerView: View {
    // The artwork is 600×356, cut flat along the bottom so it can stand on an edge.
    static let aspectRatio: CGFloat = 356.0 / 600.0

    let width: CGFloat
    let stats: ActivityStats
    let hasGames: Bool
    let offline: Bool
    let hopTrigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hopY: CGFloat = 0
    @State private var swaying = false
    @State private var speech = WanwanSpeech()
    @State private var line: String?
    @State private var hideTask: Task<Void, Never>?

    private var cleared: Bool { stats.totalPending == 0 && stats.totalDone > 0 }

    var body: some View {
        Image("WanwanCheer")
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .rotationEffect(.degrees(swaying ? 2.5 : -2.5), anchor: .bottom)
            .offset(y: hopY)
            // The artwork's top-left corner is empty, which leaves room for the badge.
            .overlay(alignment: .topLeading) {
                if cleared && line == nil {
                    Text("全清啦！")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.hoyoPink, in: Capsule())
                        .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 2))
                        .offset(x: 2, y: 4)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            // A zero-height anchor on her top edge; the bubble hangs above it, clear of the ledger.
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: 0)
                    .overlay(alignment: .bottom) {
                        if let line {
                            SpeechBubble(text: line)
                                .frame(width: max(width, 190))
                                .padding(.bottom, 12)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                                .id(line)
                        }
                    }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.6), value: cleared)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.7), value: line)
            .contentShape(Rectangle())
            .onTapGesture { talk() }
            .onAppear {
                // Restart the loop each time she scrolls back on screen.
                swaying = false
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { swaying = true }
            }
            .onChange(of: hopTrigger) { hop() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("婉婉")
            .accessibilityValue(line ?? "")
            .accessibilityHint("轻点听婉婉说话")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { talk() }
    }

    private func talk() {
        let next = speech.next(stats: stats, hasGames: hasGames, offline: offline)
        line = next
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AccessibilityNotification.Announcement(next).post()
        hop()
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            line = nil
        }
    }

    private func hop() {
        guard !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.14)) { hopY = -14 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { hopY = 0 }
        }
    }
}

// Pink cartoon bubble with a tail pointing down at Wanwan.
private struct SpeechBubble: View {
    let text: String

    var body: some View {
        ZStack(alignment: .bottom) {
            Triangle()
                .fill(Color.hoyoPink)
                .overlay(Triangle().stroke(Color.hoyoNavy, lineWidth: 2))
                .frame(width: 14, height: 9)
                .offset(y: 7)
            Text(text)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.hoyoPink, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.hoyoNavy, lineWidth: 2))
        }
        .shadow(color: Color.hoyoNavy.opacity(0.22), radius: 0, x: 2, y: 2)
    }

    nonisolated private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// Picks what Wanwan says on each tap. The first tap after a pause leads with whatever matters
// most right now; later taps mix in progress, time-of-day and small talk without repeating the
// previous line, and quick repeated taps unlock a few easter eggs.
struct WanwanSpeech {
    private var lastLine: String?
    private var lastTap: Date?
    private var streak = 0

    mutating func next(stats: ActivityStats, hasGames: Bool, offline: Bool, now: Date = Date()) -> String {
        let quick = lastTap.map { now.timeIntervalSince($0) < 1.2 } ?? false
        let freshStart = lastTap.map { now.timeIntervalSince($0) > 30 } ?? true
        streak = quick ? streak + 1 : 1
        lastTap = now

        let line: String
        if let egg = Self.easterEgg(streak: streak) {
            line = egg
        } else if freshStart, let lead = Self.headline(stats: stats, hasGames: hasGames, offline: offline, now: now) {
            line = lead
        } else {
            let pool = Self.progressLines(stats: stats, hasGames: hasGames, offline: offline)
                + Self.timeLines(now: now) + Self.smallTalk
            line = pool.filter { $0 != lastLine }.randomElement() ?? Self.smallTalk[0]
        }
        lastLine = line
        return line
    }

    // What to lead with: anything urgent, otherwise a greeting for the time of day.
    private static func headline(stats: ActivityStats, hasGames: Bool, offline: Bool, now: Date) -> String? {
        if !hasGames { return noGamesLine }
        if let urgent = urgentLine(stats) { return urgent }
        if offline { return offlineLine }
        return timeLines(now: now).first
    }

    private static let noGamesLine = "老大还没告诉婉婉要盯哪个游戏呢！"
    private static let offlineLine = "网络开小差了，婉婉先拿旧账本顶一下！"

    private static func urgentLine(_ stats: ActivityStats) -> String? {
        guard let event = stats.mostUrgent, event.remaining <= 86400 else { return nil }
        let hours = Int(event.remaining / 3600)
        let left = hours > 0 ? "只剩 \(hours) 小时了" : "不到 1 小时就结束了"
        let title = event.title.count > 12 ? event.title.prefix(12) + "…" : event.title
        return "老大！《\(event.gameName)》「\(title)」\(left)，冲！"
    }

    private static func progressLines(stats: ActivityStats, hasGames: Bool, offline: Bool) -> [String] {
        guard hasGames else { return [noGamesLine] }
        var lines: [String] = []
        if let urgent = urgentLine(stats) { lines.append(urgent) }
        if offline { lines.append(offlineLine) }
        if stats.totalEndingSoon > 0 {
            lines.append("这周有 \(stats.totalEndingSoon) 个活动要结束，婉婉都记在账本上了！")
        }
        if stats.totalPending > 0 {
            lines.append("还有 \(stats.totalPending) 个活动没做完，老大加油！")
        } else if stats.totalDone > 0 {
            lines += ["全清啦！老大今天超厉害！", "账本上全打勾了，可以安心摸鱼啦！"]
        }
        return lines
    }

    private static func timeLines(now: Date) -> [String] {
        switch Calendar.current.component(.hour, from: now) {
        case 6..<11:  return ["早上好老大！今天的体力别忘了清！"]
        case 11..<14: return ["午饭吃了吗？吃完再上线也不迟！"]
        case 18..<23: return ["晚上好老大，日常做完了吗？"]
        case 23..<24, 0..<5: return ["老大太晚啦，清完这波体力赶紧睡吧！", "再熬夜婉婉要没收你的手机了！"]
        default: return []
        }
    }

    private static let smallTalk = [
        "婉婉的账本一笔都不会记错！",
        "戳我干嘛，是想看账本吗？",
        "树脂、开拓力、电量，该清的都清了吗？",
        "抽卡前先看看活动奖励，别白白错过！",
        "婉婉一直在帮你盯着呢！",
        "今天也要做一个不错过活动的老大！",
    ]

    private static func easterEgg(streak: Int) -> String? {
        switch streak {
        case 3:  return "嘿嘿，再戳就痒啦！"
        case 5:  return "别戳啦老大，账本要掉了！"
        case 10: return "……婉婉生气了！（才没有）"
        default: return nil
        }
    }
}
