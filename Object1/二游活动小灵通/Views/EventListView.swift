import SwiftUI
import SwiftData
import Combine

// Per-game detail page: shows events split into time-based sections.
struct GameDetailView: View {
    let game: HoYoGame
    // false when the page is the split view's detail root, where there is nothing to go back to.
    var showsBackButton = true

    @Environment(ActivityService.self) private var service
    @Environment(AppRouter.self)       private var router
    @Environment(\.isWideLayout) private var isWideLayout
    @Environment(\.dismiss)            private var dismiss
    @Query private var prefsQuery: [UserPreferences]

    @State private var now           = Date()
    @State private var showCompleteGuide = false
    @State private var recentlyCompletedEventID: String? = nil

    private var prefs: UserPreferences? { prefsQuery.first }

    private var gameEvents: [RemoteEvent] {
        service.events.filter { $0.game == game }
    }

    private var endingSoon: [RemoteEvent] {
        gameEvents
            .filter { $0.remaining > 0 && $0.remaining <= 7 * 24 * 3600 && !$0.isDone }
            .sorted { $0.endDate < $1.endDate }
    }

    private var endingLater: [RemoteEvent] {
        gameEvents
            .filter { $0.remaining > 7 * 24 * 3600 && !$0.isDone }
            .sorted { $0.endDate < $1.endDate }
    }

    private var doneOrExpired: [RemoteEvent] {
        gameEvents
            .filter { $0.isDone || $0.remaining <= 0 }
            .sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        @Bindable var router = router
        ZStack {
            Color.hoyoBg.ignoresSafeArea(edges: .top)

            // Polka dot background
            if !isWideLayout {
                Canvas { ctx, size in
                    for row in stride(from: 0, through: size.height, by: 24) {
                        for col in stride(from: 0, through: size.width, by: 24) {
                            let r = CGRect(x: col - 1, y: row - 1, width: 2, height: 2)
                            ctx.fill(Path(ellipseIn: r), with: .color(Color.hoyoNavy.opacity(0.05)))
                        }
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {

                    // Error
                    if let msg = service.errorMessage {
                        Label(msg, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                            .padding(.horizontal, 4)
                    }

                    AdaptiveTwoColumn {
                        // Ending soon
                        VStack(alignment: .leading, spacing: 10) {
                            detailSectionHeader(
                                systemImage: "bolt.fill",
                                iconBg: Color.hoyoPink,
                                title: "七日内临期",
                                count: endingSoon.count
                            )
                            if endingSoon.isEmpty {
                                emptyState(text: "暂无临期活动", sub: "7 天内没有急事，婉婉先待命。")
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(endingSoon) { event in
                                        EventRowView(
                                            event: event, showGameTag: false,
                                            isMuted: prefs?.isMuted(event.id) ?? false,
                                            onTap: { router.remoteEvent = event },
                                            onToggleMute: { toggleMute(event) }
                                        ) { toggleDone(event) }
                                    }
                                }
                                .animation(HoyoMotion.layout, value: endingSoon.map(\.id))
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.tap")
                                        .font(.caption2)
                                    Text("轻触查看 B站攻略，长按可静音或标记完成")
                                        .font(.caption)
                                }
                                .foregroundStyle(Color.hoyoNavy.opacity(0.30))
                                .padding(.top, 2)
                            }
                        }
                    } trailing: {
                        // Ending later
                        VStack(alignment: .leading, spacing: 10) {
                            detailSectionHeader(
                                systemImage: "calendar",
                                iconBg: Color.hoyoMint,
                                title: "七日后待办",
                                count: endingLater.count
                            )
                            if endingLater.isEmpty {
                                emptyState(text: "暂无待办活动", sub: "后面暂时没有待办，婉婉继续盯着。")
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(endingLater) { event in
                                        EventRowView(
                                            event: event, showGameTag: false,
                                            isMuted: prefs?.isMuted(event.id) ?? false,
                                            onTap: { router.remoteEvent = event },
                                            onToggleMute: { toggleMute(event) }
                                        ) { toggleDone(event) }
                                    }
                                }
                                .animation(HoyoMotion.layout, value: endingLater.map(\.id))
                            }
                        }
                    }

                    // Done / expired
                    if !doneOrExpired.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            detailSectionHeader(
                                systemImage: "checkmark.circle.fill",
                                iconBg: Color.hoyoNavy.opacity(0.35),
                                title: "已完成 & 已结束",
                                count: doneOrExpired.count
                            )
                            VStack(spacing: 8) {
                                ForEach(doneOrExpired) { event in
                                    EventRowView(
                                        event: event, showGameTag: false,
                                        onTap: { router.remoteEvent = event },
                                        playCompletionArrival: recentlyCompletedEventID == event.id
                                    ) { toggleDone(event) }
                                }
                            }
                            .animation(HoyoMotion.layout, value: doneOrExpired.map(\.id))
                            .opacity(0.60)
                        }
                    }

                }
                .padding(16)
                .padding(.bottom, 120)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .navigationDestination(item: $router.remoteEvent) { event in
            EventGuideView(event: event)
                .verticalBarNavigation()
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
        .sheet(isPresented: $showCompleteGuide) { CompleteTaskGuideSheet() }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func detailSectionHeader(systemImage: String, iconBg: Color, title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconBg, in: RoundedRectangle(cornerRadius: 8))

            Text("\(title)（\(count)）")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)

            Spacer()
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(text: String, sub: String) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.hoyoNavy.opacity(0.40))
            Text(sub)
                .font(.caption)
                .foregroundStyle(Color.hoyoNavy.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Custom back button
        ToolbarItem(placement: .topBarLeading) {
            if showsBackButton {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.hoyoNavy, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }

        // Center: emoji + name
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Text(game.emoji)
                    .font(.system(size: 18))
                Text(game.displayName)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Color.hoyoNavy)
            }
        }

        // Right: update label
        ToolbarItem(placement: .topBarTrailing) {
            if service.isLoading {
                ProgressView().scaleEffect(0.75)
            } else if let updated = service.lastUpdated {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                    Text(updatedLabel(updated))
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.hoyoMint, in: Capsule())
            }
        }
    }

    // MARK: - Helpers

    private func toggleDone(_ event: RemoteEvent) {
        guard let p = prefs else { return }
        if event.isDone {
            recentlyCompletedEventID = nil
            p.markIncomplete(event.id)
        } else {
            recentlyCompletedEventID = event.id
            p.markCompleted(event.id)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                if recentlyCompletedEventID == event.id {
                    recentlyCompletedEventID = nil
                }
            }
        }
        service.applyCompletion(completedIds: Set(p.completedEventIds))
        NotificationManager.shared.rescheduleAll()
    }

    private func toggleMute(_ event: RemoteEvent) {
        guard let p = prefs else { return }
        p.toggleMute(event.id)
        NotificationManager.shared.rescheduleAll()
    }

    private func updatedLabel(_ date: Date) -> String {
        let secs = Int(now.timeIntervalSince(date))
        if secs < 60   { return "刚刚更新" }
        if secs < 3600 { return "\(secs / 60) 分钟前" }
        return "\(secs / 3600) 小时前"
    }
}
