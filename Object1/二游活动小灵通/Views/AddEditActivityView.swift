import SwiftUI
import SwiftData
import UIKit
import UserNotifications

nonisolated private struct HorizontalSliceShape: Shape {
    let index: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        let sliceHeight = rect.height / CGFloat(count)
        return Path(
            CGRect(
                x: rect.minX,
                y: rect.minY + CGFloat(index) * sliceHeight,
                width: rect.width,
                height: sliceHeight
            )
        )
    }
}

// Settings page: game selection + notification lead time.
struct SettingsView: View {
    @Query private var prefsQuery: [UserPreferences]

    private var prefs: UserPreferences? { prefsQuery.first }

    var body: some View {
        if let prefs {
            SettingsFormView(prefs: prefs)
        } else {
            ProgressView()
        }
    }
}

// Separate sub-view so @Bindable works on the @Model object.
private struct SettingsFormView: View {
    @Bindable var prefs: UserPreferences
    @Environment(\.isWideLayout) private var isWide

    @Environment(\.openURL)      private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase)   private var scenePhase
    @Environment(PurchaseService.self) private var purchaseService
    @Query private var customGames: [CustomGame]
    @State private var showAISearch  = false
    @State private var showPremium   = false
    @State private var addLimitMessage: String? = nil
    @State private var deleteErrorMessage: String? = nil
    @State private var deletingGameID: String? = nil
    @State private var deleteFragmentsSeparated = false
    @State private var addSuccessVisible = false
    @State private var previousCustomGameCount = 0
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        ZStack {
            Color.hoyoBg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Settings header card
                    settingsHeaderCard

                    // Stacked on phones; account and app sections side by side when the Duo unfolds.
                    AdaptiveTwoColumn {
                        VStack(spacing: 20) { accountSections }
                    } trailing: {
                        VStack(spacing: 20) { appSections }
                    }

                    Text("此 App 使用社区第三方 API 获取活动数据，与米哈游官方无关。")
                        .font(.caption2)
                        .foregroundStyle(Color.hoyoNavy.opacity(0.30))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.bottom, isWide ? 24 : 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .fontDesign(.rounded)
        .sheet(isPresented: $showAISearch) { AIGameSearchView() }
        .onAppear { previousCustomGameCount = customGames.count }
        .onChange(of: customGames.count) { oldCount, newCount in
            previousCustomGameCount = newCount
            guard newCount > oldCount else { return }
            addSuccessVisible = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(850))
                withAnimation(.easeOut(duration: 0.2)) { addSuccessVisible = false }
            }
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
        .alert("删除失败", isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .onAppear { refreshNotifStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshNotifStatus() }
        }
    }

    // 会员、关注的游戏、自定义游戏：账号和游戏相关
    @ViewBuilder
    private var accountSections: some View {
        sectionLabel(icon: "crown.fill", iconColor: Color.hoyoYellow, title: "会员权益")
        membershipCard

        sectionLabel(icon: "bookmark.fill", iconColor: Color.hoyoPink, title: "关注的游戏")
        followedGamesCard

        sectionLabel(icon: "shippingbox.fill", iconColor: Color(hex: "E8895A"), title: "自定义游戏")
        addGameButton
    }

    // 提醒设置、隐私与合规：App 行为相关
    @ViewBuilder
    private var appSections: some View {
        sectionLabel(icon: "bell.badge.fill", iconColor: Color.hoyoPink, title: "提醒设置")
        notificationCard

        sectionLabel(icon: "hand.raised.fill", iconColor: Color(hex: "4A72C4"), title: "隐私与合规")
        complianceCard
    }

    private var complianceCard: some View {
        NavigationLink {
            ComplianceCenterView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(hex: "4A72C4"), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text("隐私与合规中心")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.hoyoNavy)
                    Text("政策、AI 公示、备案信息与数据管理")
                        .font(.caption)
                        .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.hoyoNavy.opacity(0.25))
            }
            .padding(16)
            .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Settings Header Card

    private var settingsHeaderCard: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 14) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color(hex: "4A72C4"))
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("设置")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(.white)
                    Text("婉婉按你的习惯来")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .kerning(0.8)
                }
                Spacer()
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [Color(hex: "4A72C4"), Color(hex: "6B5EA8")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color(hex: "4A72C4").opacity(0.30), radius: 16, x: 0, y: 6)

            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.hoyoYellow)
                .padding(14)
        }
    }

    // MARK: - Membership Card

    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: purchaseService.isPremium ? "crown.fill" : "lock.open.fill")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(purchaseService.isPremium ? Color.hoyoYellow : Color.hoyoPink, in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(purchaseService.tier.displayName)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(Color.hoyoNavy)
                    Text("自定义游戏 \(customGames.count)/\(purchaseService.tier.maxCustomGames) · 每日提取 \(purchaseService.tier.dailyAIQueries) 次")
                        .font(.caption)
                        .foregroundStyle(Color.hoyoNavy.opacity(0.46))
                }

                Spacer()
            }

            Button {
                showPremium = true
            } label: {
                Text(purchaseService.isPremium ? "管理会员" : "升级会员")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.hoyoPink, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.5)
        )
        .shadow(color: Color.hoyoNavy.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - Section Label

    @ViewBuilder
    private func sectionLabel(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(iconColor, in: RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.hoyoNavy)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Followed Games Card

    private var followedGamesCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(HoYoGame.allCases.filter { prefs.isFollowing($0) }.enumerated()), id: \.element.rawValue) { idx, game in
                if idx > 0 {
                    Rectangle()
                        .fill(Color.hoyoNavy.opacity(0.06))
                        .frame(height: 1)
                        .overlay(
                            HStack(spacing: 4) {
                                ForEach(0..<30, id: \.self) { _ in
                                    Rectangle()
                                        .fill(Color.hoyoNavy.opacity(0.10))
                                        .frame(width: 4, height: 1)
                                    Spacer().frame(width: 4)
                                }
                            }
                        )
                        // The dashes are wider than the card; clip them to the divider's own width.
                        .clipped()
                        .padding(.horizontal, 16)
                }
                HStack(spacing: 12) {
                    Text(game.emoji)
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(game.cardHeaderColor.opacity(0.15))
                        )
                    Text(game.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.hoyoNavy)
                    Spacer()
                    Button {
                        prefs.toggleGame(game)
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.hoyoNavy.opacity(0.20), lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.hoyoNavy.opacity(0.40))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Show un-followed games as addable rows
            let unfollowed = HoYoGame.allCases.filter { !prefs.isFollowing($0) }
            if !unfollowed.isEmpty {
                if prefs.followedGames.count > 0 {
                    Divider().padding(.horizontal, 16)
                }
                ForEach(unfollowed, id: \.rawValue) { game in
                    Button {
                        prefs.toggleGame(game)
                    } label: {
                        HStack(spacing: 12) {
                            Text(game.emoji)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.hoyoNavy.opacity(0.06))
                                )
                            Text(game.displayName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                            Spacer()
                            Image(systemName: "plus.circle")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.hoyoPink.opacity(0.60))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.5)
        )
        .shadow(color: Color.hoyoNavy.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - Custom Games Card

    @ViewBuilder
    private var customGamesSection: some View {
        if !customGames.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(customGames.enumerated()), id: \.element.id) { idx, game in
                    if idx > 0 { Divider().padding(.horizontal, 16) }
                    deletableCustomGameRow(game)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.5)
            )
            .shadow(color: Color.hoyoNavy.opacity(0.06), radius: 10, x: 0, y: 3)
        }
    }

    private func customGameRowContent(_ game: CustomGame) -> some View {
        HStack(spacing: 12) {
            Text(game.emoji)
                .font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(game.accentColor.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.hoyoNavy)
                Text("\(game.activeEvents.count) 个进行中")
                    .font(.caption)
                    .foregroundStyle(Color.hoyoNavy.opacity(0.40))
            }
            Spacer()
            Button(role: .destructive) {
                animateDelete(game)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.hoyoNavy.opacity(0.20), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.hoyoNavy.opacity(0.40))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func deletableCustomGameRow(_ game: CustomGame) -> some View {
        let isDeleting = deletingGameID == game.id
        let xOffsets: [CGFloat] = [-34, 20, -28]
        let yOffsets: [CGFloat] = [-5, 1, 6]
        let rotations: [Double] = [-2.0, 1.2, -1.4]

        return ZStack {
            customGameRowContent(game)
                .opacity(isDeleting ? 0 : 1)

            if isDeleting {
                ForEach(0..<3, id: \.self) { slice in
                    customGameRowContent(game)
                        .clipShape(HorizontalSliceShape(index: slice, count: 3))
                        .offset(
                            x: deleteFragmentsSeparated ? xOffsets[slice] : 0,
                            y: deleteFragmentsSeparated ? yOffsets[slice] : 0
                        )
                        .rotationEffect(.degrees(deleteFragmentsSeparated ? rotations[slice] : 0))
                        .scaleEffect(deleteFragmentsSeparated ? 0.94 : 1)
                        .opacity(deleteFragmentsSeparated ? 0 : 1)
                        .allowsHitTesting(false)
                }
            }
        }
        .animation(.easeOut(duration: 0.34), value: deleteFragmentsSeparated)
    }

    // MARK: - Add Game Button

    private var addGameButton: some View {
        VStack(spacing: 12) {
            customGamesSection

            Button {
                openAddGame()
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.30))
                            .frame(width: 32, height: 32)
                        Image(systemName: addSuccessVisible ? "checkmark" : "plus")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                            .rotationEffect(.degrees(addSuccessVisible ? 360 : 0))
                    }
                    Text("添加要盯的游戏")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.hoyoYellow)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.hoyoPink, Color(hex: "FF4DA6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .shadow(color: Color.hoyoPink.opacity(0.40), radius: 12, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            Text("婉婉可以联网帮你整理自定义游戏的活动")
                .font(.caption2)
                .foregroundStyle(Color.hoyoNavy.opacity(0.35))
        }
    }

    private func openAddGame() {
        guard customGames.count < purchaseService.tier.maxCustomGames else {
            addLimitMessage = purchaseService.tier.customGameLimitMessage(currentCount: customGames.count)
            return
        }
        showAISearch = true
    }

    private func animateDelete(_ game: CustomGame) {
        guard deletingGameID == nil else { return }
        deletingGameID = game.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.34)) {
                deleteFragmentsSeparated = true
            }
            try? await Task.sleep(for: .milliseconds(360))
            modelContext.delete(game)
            do {
                try modelContext.save()
                deleteErrorMessage = nil
                NotificationManager.shared.rescheduleAll()
            } catch {
                modelContext.rollback()
                deleteErrorMessage = "删除失败：\(error.localizedDescription)"
            }
            deleteFragmentsSeparated = false
            deletingGameID = nil
        }
    }

    // MARK: - Notification Card

    private var notificationCard: some View {
        VStack(spacing: 0) {

            // ── Row 1: Daily reminder toggle ──────────────────────────
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: prefs.dailyReminderEnabled ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        prefs.dailyReminderEnabled ? Color.hoyoPink : Color.hoyoNavy.opacity(0.30),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: prefs.dailyReminderEnabled)
                    .rotationEffect(.degrees(prefs.dailyReminderEnabled ? -5 : 0))

                VStack(alignment: .leading, spacing: 3) {
                    Text("每日提醒")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.hoyoNavy)
                    Text("每天在您选择的时间提醒临期活动")
                        .font(.caption)
                        .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                }

                Spacer()

                Toggle("", isOn: $prefs.dailyReminderEnabled)
                    .labelsHidden()
                    .tint(Color.hoyoPink)
                    .onChange(of: prefs.dailyReminderEnabled) { _, enabled in
                        handleDailyToggle(enabled)
                    }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .animation(.easeInOut(duration: 0.2), value: prefs.dailyReminderEnabled)

            // ── Row 2: Time picker (only when daily is enabled) ───────
            if prefs.dailyReminderEnabled {
                Divider().padding(.horizontal, 16)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("提醒时间")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.hoyoNavy.opacity(0.55))
                        Text("可选择 24 小时内任意时间")
                            .font(.caption2)
                            .foregroundStyle(Color.hoyoNavy.opacity(0.30))
                    }
                    Spacer()
                    DatePicker(
                        "",
                        selection: Binding(
                            get: {
                                Calendar.current.date(from: DateComponents(
                                    hour:   prefs.notificationHour,
                                    minute: prefs.notificationMinute
                                )) ?? Date()
                            },
                            set: { d in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                                prefs.notificationHour   = c.hour ?? 21
                                prefs.notificationMinute = c.minute ?? 0
                                // Refresh daily reminders immediately when time changes
                                NotificationManager.shared.rescheduleAll()
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Row 3: Permission status ───────────────────────────────
            Divider().padding(.horizontal, 16)
            HStack(spacing: 10) {
                Image(systemName: notifStatusIcon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(notifStatusColor, in: RoundedRectangle(cornerRadius: 6))
                Text("通知权限")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.hoyoNavy.opacity(0.55))
                Spacer()
                Text(notifStatusText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(notifStatusColor)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)

            // ── Row 4: Permission action (conditional) ─────────────────
            if notifStatus == .denied {
                Divider().padding(.horizontal, 16)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13, weight: .semibold))
                        Text("前往系统设置开启通知权限")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.hoyoPink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            } else if notifStatus == .notDetermined {
                Divider().padding(.horizontal, 16)
                Button {
                    NotificationManager.shared.requestPermission()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshNotifStatus() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("开启临期提醒")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(Color.hoyoPink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }

        }
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.5)
        )
        .shadow(color: Color.hoyoNavy.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - Toggle handler

    private func handleDailyToggle(_ enabled: Bool) {
        if enabled {
            if notifStatus == .notDetermined {
                NotificationManager.shared.requestPermission()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshNotifStatus() }
            } else {
                NotificationManager.shared.rescheduleAll()
            }
        } else {
            // Only cancel daily reminders; urgent (6-hour) reminders stay active
            NotificationManager.shared.cancelDailyNotifications()
        }
    }

    // MARK: - Permission helpers

    private var notifStatusIcon: String {
        switch notifStatus {
        case .authorized, .provisional: return "checkmark"
        case .denied:                   return "xmark"
        default:                        return "questionmark"
        }
    }

    private var notifStatusColor: Color {
        switch notifStatus {
        case .authorized, .provisional: return Color.hoyoMint
        case .denied:                   return .red
        default:                        return Color.hoyoNavy.opacity(0.40)
        }
    }

    private var notifStatusText: String {
        switch notifStatus {
        case .authorized:  return "已开启"
        case .provisional: return "临时授权"
        case .denied:      return "已拒绝"
        default:           return "未请求"
        }
    }

    private func refreshNotifStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifStatus = settings.authorizationStatus
        }
    }

}
