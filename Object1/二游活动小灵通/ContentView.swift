import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query private var prefsQuery: [UserPreferences]
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var showOnboarding = false
    @State private var router = AppRouter()
    @State private var hasVerticalBar = false
    @Namespace private var gameZoom

    // Regular width: unfolded Duo or Pro Max landscape.
    private var isWide: Bool { horizontalSizeClass == .regular }
    private static let sidebarWidth: CGFloat = 290

    var body: some View {
        // One view tree for both widths, so the current page keeps its scroll position and pushes.
        // The page jumps straight to its new frame; only the sidebar animates, sliding in from the left.
        ZStack(alignment: .leading) {
            tabLayout
                .padding(.leading, isWide ? Self.sidebarWidth : 0)

            ZStack {
                if isWide {
                    SplitSidebar()
                        .frame(width: Self.sidebarWidth)
                        // Folding removes it at once, so it never shows up on the outer display.
                        .transition(.asymmetric(insertion: .move(edge: .leading), removal: .identity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : HoyoMotion.layout, value: isWide)
        }
        .background(VerticalBarReader { hasVerticalBar = $0 })
        // Keep the window light instead of black while the system moves the app between displays.
        .background(Color.hoyoBg.ignoresSafeArea())
        .environment(router)
        .environment(\.hasVerticalBar, hasVerticalBar)
        .environment(\.isWideLayout, isWide)
        .fontDesign(.rounded)
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: {
            onboardingDone = true
        }) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .task {
            if prefsQuery.isEmpty {
                modelContext.insert(UserPreferences(followedGameSlugs: []))
            }
            if !onboardingDone {
                showOnboarding = true
            }
        }
    }

    // The current tab's page, plus the floating tab bar on ordinary iPhones.
    private var tabLayout: some View {
        ZStack(alignment: .bottom) {
            Color.white.ignoresSafeArea()

            // One NavigationStack for all tabs. The Duo's vertical bar shows the toolbar of a single
            // navigation stack; with one stack per tab, the buttons briefly fell back into the
            // page's top bar while the system handed the vertical bar from one stack to another.
            NavigationStack(path: router.path) {
                // All three pages stay alive and the inactive ones are hidden, so switching tabs never
                // rebuilds a page or re-runs its loading; only opacity, scale and offset animate.
                GeometryReader { proxy in
                    ZStack {
                        tabPage(.home, width: proxy.size.width) { GameGridView() }
                        tabPage(.games, width: proxy.size.width) { GamesTabView() }
                        tabPage(.settings, width: proxy.size.width) { SettingsView() }
                    }
                }
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.24), value: router.tab)
                .verticalBarNavigation()
                .navigationDestination(for: GameRoute.self) { gameDestination($0) }
            }
            .environment(\.gameZoomNamespace, gameZoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Wide layouts use the sidebar, and the Duo's vertical bar holds the tabs itself.
            ZStack {
                if showsTabBar {
                    FloatingTabBar(selectedTab: selectedTabIndex, onSelect: selectTab)
                        .frame(maxWidth: .infinity)
                        .background(
                            Color.white
                                .padding(.top, -40)
                                .ignoresSafeArea(edges: .bottom)
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.15) : HoyoMotion.layout, value: showsTabBar)
        }
        .ignoresSafeArea(.keyboard)
    }

    private var showsTabBar: Bool { !isWide && !hasVerticalBar }

    private var selectedTabIndex: Binding<Int> {
        Binding(
            get: { router.tab.rawValue },
            set: { router.selectTab(AppTab(rawValue: $0) ?? .home) }
        )
    }

    private func tabPage(_ tab: AppTab, width: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        let isActive = router.tab == tab
        // With the floating tab bar, inactive pages wait off to the side they sit on in the bar.
        // Tabs picked from the sidebar or the Duo's vertical bar have no left-to-right order on
        // screen, so there the page fades in while settling from slightly smaller instead.
        let slides = showsTabBar && !reduceMotion
        let side: CGFloat = tab.rawValue < router.tab.rawValue ? -1 : 1
        return content()
            .scaleEffect(isActive || slides || reduceMotion ? 1 : 0.97)
            .offset(x: isActive || !slides ? 0 : side * width)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }

    // Games opened from the 游戏 tab zoom out of their card; elsewhere they push normally.
    @ViewBuilder
    private func gameDestination(_ route: GameRoute) -> some View {
        if #available(iOS 18.0, *), router.tab == .games {
            GameRouteDestination(route: route)
                .navigationTransition(.zoom(sourceID: route.sourceID, in: gameZoom))
        } else {
            GameRouteDestination(route: route)
        }
    }

    private func selectTab(_ newTab: Int) {
        guard newTab != router.tab.rawValue, let tab = AppTab(rawValue: newTab) else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.76)) {
            router.selectTab(tab)
        }
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTab: Int
    var onSelect: ((Int) -> Void)? = nil
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, icon: "waveform",           label: "首页")
            tabButton(index: 1, icon: "gamecontroller.fill", label: "游戏")
            tabButton(index: 2, icon: "gearshape.fill",     label: "设置")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 40)
                .fill(Color.hoyoCardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(Color.hoyoNavy, lineWidth: 3)
                )
        )
        .shadow(color: Color.hoyoNavy.opacity(0.22), radius: 0, x: 3, y: 3)
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private func tabButton(index: Int, icon: String, label: String) -> some View {
        let isSelected = selectedTab == index
        Button {
            if let onSelect {
                onSelect(index)
            } else {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.76)) {
                selectedTab = index
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .black))
                    .scaleEffect(isSelected && !reduceMotion ? 1.12 : 1)
                    .rotationEffect(.degrees(isSelected && !reduceMotion ? -4 : 0))
                Text(label)
                    .font(.system(size: 15, weight: .black))
            }
            .foregroundStyle(isSelected ? .white : Color.hoyoNavy.opacity(0.50))
            .padding(.vertical, 14)
            .padding(.horizontal, isSelected ? 26 : 22)
            .frame(maxWidth: isSelected ? .infinity : nil)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.hoyoPink)
                            .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 2))
                            .matchedGeometryEffect(id: "selectedTab", in: selectionAnimation)
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: UserPreferences.self, inMemory: true)
        .environment(ActivityService())
        .environment(PurchaseService())
}
