import SwiftUI
import SwiftData

struct CustomGameDetailView: View {
    @Bindable var game: CustomGame
    // false when the page is the split view's detail root, where there is nothing to go back to.
    var showsBackButton = true
    @Environment(AppRouter.self) private var router
    @Environment(\.isWideLayout) private var isWideLayout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseService.self) private var purchaseService

    @State private var aiService     = AIGameService()
    @State private var showConfirm   = false
    @State private var showURLInput  = false
    @State private var showPremium   = false
    @State private var articleURL    = ""
    @State private var pendingDrafts:    [AIEventDraft] = []
    @State private var editingEvent:     CustomEvent? = nil
    @State private var showCompleteGuide = false
    @State private var saveErrorMessage: String? = nil
    @State private var webExtractorItem: WebExtractorTarget? = nil
    @State private var recentlyCompletedEventID: String? = nil
    @State private var showAIDisclosure = false
    @State private var pendingRefreshAfterDisclosure = false

    private struct WebExtractorTarget: Identifiable {
        let id  = UUID()
        let url: URL
    }

    private var endingSoon: [CustomEvent] {
        game.events.filter { $0.remaining > 0 && $0.remaining <= 7 * 86400 && !$0.isDone }
                   .sorted { $0.endDate < $1.endDate }
    }
    private var endingLater: [CustomEvent] {
        game.events.filter { $0.remaining > 7 * 86400 && !$0.isDone }
                   .sorted { $0.endDate < $1.endDate }
    }
    private var doneOrExpired: [CustomEvent] {
        game.events.filter { $0.isDone || $0.remaining <= 0 }
                   .sorted { $0.endDate > $1.endDate }
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var router = router
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {

                    if aiService.isSearching {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("婉婉正在读公告、整理活动…")
                                .font(.subheadline)
                                .foregroundStyle(Color.hoyoNavy.opacity(0.55))
                        }
                        .padding(.horizontal, 4)
                    }

                    if let err = aiService.errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                            .padding(.horizontal, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    AdaptiveTwoColumn {
                        // 一周内结束
                        VStack(alignment: .leading, spacing: 10) {
                            detailSectionHeader(systemImage: "bolt.fill",
                                                iconBg: endingSoon.isEmpty ? Color.hoyoNavy.opacity(0.35) : Color.hoyoPink,
                                                title: "七日内临期", count: endingSoon.count)
                            if endingSoon.isEmpty {
                                emptyState(text: "暂无临期活动", sub: "7 天内没有急事，婉婉先待命。")
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(endingSoon) { event in
                                        CustomEventRow(event: event) {
                                            toggleDone(event)
                                        } onEdit: {
                                            editingEvent = event
                                        } onGuide: {
                                            router.customEvent = event
                                        }
                                    }
                                }
                                .animation(reduceMotion ? nil : HoyoMotion.layout, value: endingSoon.map(\.id))
                                HStack(spacing: 4) {
                                    Image(systemName: "hand.tap").font(.caption2)
                                    Text("轻触查看 B站攻略，长按可编辑或标记完成").font(.caption)
                                }
                                .foregroundStyle(Color.hoyoNavy.opacity(0.30))
                                .padding(.top, 2)
                            }
                        }
                    } trailing: {
                        // 一周后待做
                        VStack(alignment: .leading, spacing: 10) {
                            detailSectionHeader(systemImage: "calendar",
                                                iconBg: Color.hoyoMint,
                                                title: "七日后待办", count: endingLater.count)
                            if endingLater.isEmpty {
                                emptyState(text: "暂无待办活动", sub: "后面暂时没有待办，婉婉继续盯着。")
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(endingLater) { event in
                                        CustomEventRow(event: event) {
                                            toggleDone(event)
                                        } onEdit: {
                                            editingEvent = event
                                        } onGuide: {
                                            router.customEvent = event
                                        }
                                    }
                                }
                                .animation(reduceMotion ? nil : HoyoMotion.layout, value: endingLater.map(\.id))
                            }
                        }
                    }

                    // 已完成 & 已结束
                    if !doneOrExpired.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            detailSectionHeader(systemImage: "checkmark.circle.fill",
                                                iconBg: Color.hoyoNavy.opacity(0.35),
                                                title: "已完成 & 已结束", count: doneOrExpired.count)
                            VStack(spacing: 8) {
                                ForEach(doneOrExpired) { event in
                                    CustomEventRow(
                                        event: event,
                                        playCompletionArrival: recentlyCompletedEventID == event.id
                                    ) {
                                        toggleDone(event)
                                    } onEdit: {
                                        editingEvent = event
                                    } onGuide: {
                                        router.customEvent = event
                                    }
                                }
                            }
                            .animation(reduceMotion ? nil : HoyoMotion.layout, value: doneOrExpired.map(\.id))
                            .opacity(0.60)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 120)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.78), value: aiService.errorMessage)
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarItems }
        .toolbarBackground(Color.hoyoBg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .fontDesign(.rounded)
        .alert(purchaseService.tier.extractionLimitTitle, isPresented: Binding(
            get: { aiService.quotaLimitMessage != nil },
            set: { if !$0 { aiService.quotaLimitMessage = nil } }
        )) {
            if purchaseService.tier == .free {
                Button("升级会员") {
                    aiService.quotaLimitMessage = nil
                    showPremium = true
                }
            }
            Button("知道了", role: .cancel) {}
        } message: {
            Text(aiService.quotaLimitMessage ?? "")
        }
        .sheet(isPresented: $showURLInput) {
            ArticleURLInputView(url: $articleURL) {
                showURLInput = false
                let raw = articleURL.trimmingCharacters(in: .whitespaces)
                let urlString = extractFirstURL(from: raw) ?? raw
                if let url = URL(string: urlString) {
                    webExtractorItem = WebExtractorTarget(url: url)
                }
            }
        }
        .sheet(item: $webExtractorItem) { item in
            WebExtractorSheet(url: item.url) { extractedText, finalURL in
                Task {
                    let entitlementProof = await purchaseService.currentEntitlementJWS()
                    let result = await aiService.extractEvents(
                        from: extractedText,
                        gameName: game.name,
                        articleURL: finalURL,
                        entitlementTier: purchaseService.tier,
                        appStoreTransactionJWS: entitlementProof
                    )
                    guard !result.isEmpty else { return }
                    pendingDrafts = result
                    showConfirm   = true
                }
            }
        }
        .sheet(isPresented: $showPremium) { PremiumView() }
        .sheet(isPresented: $showAIDisclosure) {
            AIProcessingDisclosureView {
                if pendingRefreshAfterDisclosure {
                    pendingRefreshAfterDisclosure = false
                    Task { await openRefreshInput() }
                }
            }
        }
        .sheet(isPresented: $showConfirm) {
            RefreshConfirmView(gameName: game.name, drafts: $pendingDrafts, saveErrorMessage: $saveErrorMessage) { selected in
                applyRefresh(selected)
            }
        }
        .sheet(item: $editingEvent) { event in
            EditEventView(event: event)
        }
        .navigationDestination(item: $router.customEvent) { event in
            CustomEventGuideView(event: event, gameName: game.name, gameEmoji: game.emoji)
                .verticalBarNavigation()
        }
        .sheet(isPresented: $showCompleteGuide) { CompleteTaskGuideSheet() }
    }

    // MARK: - Refresh

    private func extractFirstURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range   = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.first {
            guard let scheme = $0.url?.scheme?.lowercased() else { return false }
            return scheme == "https" || scheme == "http"
        }?.url?.absoluteString
    }

    private func applyRefresh(_ selected: [AIEventDraft]) -> Bool {
        let oldEventIds = game.replaceEvents(with: selected, in: modelContext)
        do {
            try modelContext.save()
            saveErrorMessage = nil
            NotificationManager.shared.cancelNotifications(forCustomActivityIds: oldEventIds)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationManager.shared.rescheduleAll()
            return true
        } catch {
            modelContext.rollback()
            saveErrorMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
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
                .font(.subheadline).fontWeight(.semibold)
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
    private var toolbarItems: some ToolbarContent {
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
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Text(game.emoji).font(.system(size: 18))
                Text(game.name)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(Color.hoyoNavy)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                Button { showCompleteGuide = true } label: {
                    Image(systemName: "questionmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.hoyoNavy.opacity(0.70))
                        .frame(width: 34, height: 34)
                        .background(Color.hoyoNavy.opacity(0.08), in: Circle())
                        .overlay(Circle().stroke(Color.hoyoNavy.opacity(0.12), lineWidth: 1.2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await openRefreshInput() }
                } label: {
                    if aiService.isSearching || aiService.isCheckingQuota {
                        ProgressView().scaleEffect(0.75)
                            .frame(width: 54, height: 34)
                    } else {
                        Text("更新")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(Color.hoyoPink)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Color.hoyoPink.opacity(0.12), in: Capsule())
                            .overlay(Capsule().stroke(Color.hoyoPink.opacity(0.22), lineWidth: 1.2))
                            .contentShape(Capsule())
                    }
                }
                .accessibilityLabel("更新")
                .buttonStyle(.plain)
                .disabled(aiService.isSearching || aiService.isCheckingQuota)
            }
        }
    }

    private func toggleDone(_ event: CustomEvent) {
        if event.isDone {
            recentlyCompletedEventID = nil
            event.isDone = false
        } else {
            recentlyCompletedEventID = event.id
            event.isDone = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                if recentlyCompletedEventID == event.id {
                    recentlyCompletedEventID = nil
                }
            }
        }
        NotificationManager.shared.rescheduleAll()
    }

    private func openRefreshInput() async {
        guard UserDefaults.standard.bool(forKey: PrivacyConsent.aiConsentKey) else {
            pendingRefreshAfterDisclosure = true
            showAIDisclosure = true
            return
        }
        articleURL = ""
        let entitlementProof = await purchaseService.currentEntitlementJWS()
        guard await aiService.canStartExtraction(
            entitlementTier: purchaseService.tier,
            appStoreTransactionJWS: entitlementProof
        ) else { return }
        showURLInput = true
    }
}

// MARK: - Edit Event Sheet

struct EditEventView: View {
    @Bindable var event: CustomEvent
    @Environment(\.dismiss) private var dismiss

    private let categories = ["版本活动", "周常任务", "副本挑战", "活动"]

    var body: some View {
        NavigationStack {
            Form {
                Section("活动名称") {
                    TextField("活动名称", text: $event.title)
                }

                Section("分类") {
                    Picker("分类", selection: $event.category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }

                Section("时间") {
                    DatePicker("开始", selection: $event.startDate,
                               displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束", selection: $event.endDate,
                               displayedComponents: [.date, .hourAndMinute])
                }

                Section {
                    Toggle("标记为已完成", isOn: $event.isDone)
                        .tint(Color.hoyoPink)
                        .onChange(of: event.isDone) { _, _ in
                            NotificationManager.shared.rescheduleAll()
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.hoyoBg)
            .navigationTitle("编辑活动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Refresh Confirm Sheet

struct RefreshConfirmView: View {
    let gameName: String
    @Binding var drafts: [AIEventDraft]
    @Binding var saveErrorMessage: String?
    let onConfirm: ([AIEventDraft]) -> Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($drafts) { $draft in
                        Toggle(isOn: $draft.isSelected) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(draft.title)
                                    .font(.subheadline).fontWeight(.medium)
                                Text("\(draft.endDateShort)结束 · \(draft.category)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Color.hoyoPink)
                    }
                } header: {
                    Label("AI 整理出 \(drafts.count) 个新活动", systemImage: "sparkles")
                } footer: {
                    Text("以上内容由 \(ComplianceConfig.aiModelName) 整理，仅供参考。请对照游戏官方公告核对后再保存；保存后会用勾选内容替换原活动并重建提醒。")
                        .font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.hoyoBg)
            .navigationTitle("刷新活动")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("替换活动") {
                        if onConfirm(drafts.filter(\.isSelected)) {
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(drafts.filter(\.isSelected).isEmpty)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
        }
    }
}

// MARK: - Article URL Input Sheet

struct ArticleURLInputView: View {
    @Binding var url: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showLinkGuide = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://b23.tv/...", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    HStack(spacing: 4) {
                        Text("B站公告链接")
                        Button { showLinkGuide = true } label: {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(Color.hoyoPink)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("粘贴哔哩哔哩版本公告的分享链接（b23.tv/…），应用会用内置浏览器打开，如遇验证码请手动通过后点「提取内容」。")
                }

                Section {
                    Button {
                        onConfirm()
                    } label: {
                        HStack {
                            Spacer()
                            Label("打开 B站公告页面", systemImage: "tv.fill")
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.hoyoPink)
                            Spacer()
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.hoyoBg)
            .sheet(isPresented: $showLinkGuide) { BilibiliLinkGuideSheet() }
            .navigationTitle("粘贴公告链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Custom Event Row

struct CustomEventRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showReadStamp = false
    @State private var showCompletionFlash = false
    @State private var completionEffectCount = 0
    @State private var isCompleting = false
    @State private var urgencyPulse = false
    @State private var completionArrivalVisible = false
    @State private var completionTask: Task<Void, Never>? = nil
    @Bindable var event: CustomEvent
    var playCompletionArrival: Bool = false
    let onToggleDone: () -> Void
    let onEdit: () -> Void
    var onGuide: (() -> Void)? = nil

    private var isUrgent: Bool {
        !event.isDone && event.remaining > 0 && event.remaining <= 2 * 86400
    }

    private var isCriticalSoon: Bool {
        !event.isDone && event.remaining > 0 && event.remaining <= 86400
    }

    private var compactRemaining: String {
        if event.isDone { return "已完成" }
        let rem = Int(event.remaining)
        if rem <= 0 { return "已结束" }
        let days = rem / 86400; let hours = (rem % 86400) / 3600; let mins = (rem % 3600) / 60
        if days  > 0 { return "\(days)天\(hours)时" }
        if hours > 0 { return "\(hours)时\(mins)分" }
        return "\(mins)分"
    }

    private var borderColor: Color {
        if event.isDone || event.remaining <= 0 { return Color.hoyoNavy.opacity(0.15) }
        return isUrgent ? Color.hoyoPink : Color.hoyoNavy.opacity(0.20)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            Capsule()
                .fill(event.urgencyColor.opacity(event.isDone ? 0.25 : 0.85))
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 12)

            // Tappable content
            Button { onGuide?() } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(isUrgent ? Color.hoyoPink.opacity(0.12) : event.urgencyColor.opacity(0.10))
                            .frame(width: 32, height: 32)
                        if event.isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.hoyoMint)
                        } else if event.remaining <= 0 {
                            Text("✕").font(.system(size: 12, weight: .bold)).foregroundStyle(.gray)
                        } else if isUrgent {
                            Text("!").font(.system(size: 14, weight: .black)).foregroundStyle(Color.hoyoPink)
                        } else {
                            Text("▶").font(.system(size: 10, weight: .black)).foregroundStyle(event.urgencyColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.hoyoNavy.opacity(event.isDone ? 0.40 : 1.0))
                            .strikethrough(event.isDone, color: Color.hoyoNavy.opacity(0.35))
                            .lineLimit(1)
                        if !event.isDone && event.remaining > 0 {
                            Text("\(event.endDateShort)结束 · \(event.category)")
                                .font(.caption2)
                                .foregroundStyle(Color.hoyoNavy.opacity(0.35))
                        }
                    }

                    Spacer(minLength: 4)

                    // Countdown pill
                    HStack(spacing: 3) {
                        Image(systemName: showReadStamp ? "checkmark" : "clock").font(.system(size: 10, weight: .bold))
                        Text(showReadStamp ? "已阅" : compactRemaining).font(.system(size: 12, weight: .black))
                    }
                    .foregroundStyle(showReadStamp ? Color.white : ((event.isDone || event.remaining <= 0) ? Color.secondary : (isUrgent ? Color.white : Color.hoyoNavy)))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(
                        showReadStamp ? Color.hoyoMint :
                        (event.isDone || event.remaining <= 0) ? Color.gray.opacity(0.20) :
                        (isUrgent ? Color.hoyoPink : Color.hoyoYellow)
                    )
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(
                        (event.isDone || event.remaining <= 0) ? Color.clear : Color.hoyoNavy,
                        lineWidth: 1.5
                    ))
                    .overlay(alignment: .topTrailing) {
                        if showReadStamp && !reduceMotion {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(Color.hoyoYellow)
                                .offset(x: 6, y: -7)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                                .symbolEffect(.bounce, value: completionEffectCount)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if showReadStamp && !reduceMotion {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color.hoyoPink)
                                .offset(x: -4, y: 5)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                                .symbolEffect(.bounce, value: completionEffectCount)
                        }
                    }
                    .shadow(color: showReadStamp ? Color.hoyoMint.opacity(0.58) : .clear,
                            radius: showReadStamp ? 8 : 0)
                    .scaleEffect(showReadStamp && !reduceMotion ? 1.06 : (isCriticalSoon && urgencyPulse && !reduceMotion ? 1.035 : 1))
                    .contentTransition(.opacity)
                    .animation(HoyoMotion.card, value: showReadStamp)
                    .animation(
                        isCriticalSoon && !showReadStamp && !reduceMotion
                            ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true)
                            : nil,
                        value: urgencyPulse
                    )
                }
                .padding(.leading, 10).padding(.trailing, 4)
                .contentShape(Rectangle())
                .fontDesign(.rounded)
            }
            .buttonStyle(.plain)

            // Done toggle
            Button {
                handleCompletionTap()
            } label: {
                Image(systemName: (event.isDone || showReadStamp) ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle((event.isDone || showReadStamp) ? Color.hoyoMint : Color.hoyoNavy.opacity(0.25))
                    .scaleEffect((event.isDone || showReadStamp) && !reduceMotion ? 1.18 : 1.0)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.45), value: event.isDone)
                    .symbolEffect(.bounce, value: completionEffectCount)
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
            .padding(.trailing, 14).padding(.leading, 4)
        }
        .padding(.vertical, 8)
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: isUrgent ? 2.5 : 2))
        .overlay {
            if showCompletionFlash {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.hoyoMint.opacity(0.22))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .shadow(color: isUrgent ? Color.hoyoPink.opacity(0.25) : Color.hoyoNavy.opacity(0.12), radius: 0, x: 2, y: 2)
        .opacity(event.isDone ? 0.65 : 1)
        .scaleEffect(playCompletionArrival ? (completionArrivalVisible ? 1 : 0.96) : 1)
        .offset(y: playCompletionArrival ? (completionArrivalVisible ? 0 : 8) : 0)
        .opacity(playCompletionArrival ? (completionArrivalVisible ? 1 : 0) : 1)
        .contextMenu {
            Button { onEdit() } label: { Label("编辑活动", systemImage: "pencil") }
            Button { onToggleDone() } label: {
                Label(event.isDone ? "标记为未完成" : "标记为完成",
                      systemImage: event.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
        }
        .onAppear {
            if isCriticalSoon && !reduceMotion { urgencyPulse = true }
        }
        .task(id: playCompletionArrival) {
            guard playCompletionArrival else { return }
            completionArrivalVisible = false
            guard !reduceMotion else {
                completionArrivalVisible = true
                return
            }
            await Task.yield()
            withAnimation(HoyoMotion.card) {
                completionArrivalVisible = true
            }
        }
        .onDisappear { completionTask?.cancel() }
    }

    private func handleCompletionTap() {
        guard !isCompleting else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        guard !event.isDone, !reduceMotion else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
                onToggleDone()
            }
            return
        }

        isCompleting = true
        completionEffectCount += 1
        withAnimation(HoyoMotion.card) {
            showReadStamp = true
            showCompletionFlash = true
        }
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            withAnimation(.easeOut(duration: 0.18)) { showCompletionFlash = false }
            do { try await Task.sleep(for: .milliseconds(220)) }
            catch { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(HoyoMotion.layout) {
                onToggleDone()
            }
            isCompleting = false
        }
    }
}

// MARK: - Custom Event Guide View

struct CustomEventGuideView: View {
    @Bindable var event: CustomEvent
    let gameName: String
    let gameEmoji: String

    @Environment(\.openURL)  private var openURL
    @Environment(\.dismiss)  private var dismiss
    @Environment(\.hasVerticalBar) private var hasVerticalBar
    @Environment(\.isWideLayout) private var isWideLayout
    @Query private var prefsQuery: [UserPreferences]

    private var prefs: UserPreferences? { prefsQuery.first }
    private var isUrgent: Bool { !event.isDone && event.remaining > 0 && event.remaining <= 2 * 86400 }

    private var bilibiliSearchKeyword: String {
        let q = "\(gameName) \(event.title) 攻略"
        return q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }

    private var bilibiliAppSearchURL: URL {
        URL(string: "bilibili://search?keyword=\(bilibiliSearchKeyword)")!
    }

    private var bilibiliWebSearchURL: URL {
        URL(string: "https://search.bilibili.com/all?keyword=\(bilibiliSearchKeyword)")!
    }

    // 优先唤起 B站 App，未安装时回退到网页搜索
    private func openBilibiliSearch() {
        openURL(bilibiliAppSearchURL) { accepted in
            if !accepted { openURL(bilibiliWebSearchURL) }
        }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

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
                VStack(spacing: 16) {
                    heroCard
                    bilibiliCard
                    detailCard
                }
                .padding(16)
                .padding(.bottom, 92)
            }
        }
        .overlay(alignment: .bottom) { bottomActionButton }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .fontDesign(.rounded)
    }

    private var bottomActionButton: some View {
        Button { toggleDone() } label: {
            HStack(spacing: 8) {
                Text(event.isDone ? "↩" : "✓")
                    .font(.system(size: 17, weight: .black))
                Text(event.isDone ? "标记为未完成" : "标记为已完成")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                if !event.isDone {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.hoyoYellow)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: event.isDone
                        ? [Color.hoyoMint, Color(hex: "2aa99f")]
                        : [Color.hoyoPink, Color(hex: "FF4DA6")],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .shadow(color: (event.isDone ? Color.hoyoMint : Color.hoyoPink).opacity(0.40),
                    radius: 12, x: 0, y: 4)
        }
        .buttonStyle(CardPressStyle())
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.white.opacity(0.96))
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(gameEmoji + " " + gameName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.hoyoNavy.opacity(0.45), in: Capsule())

                Spacer()
            }
            .padding(.bottom, 14)

            Text(event.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .padding(.bottom, 6)

            Text(event.remainingText)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.bottom, 18)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
                    Text(event.endDateShort + "结束").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.20), in: Capsule())

                Text(event.category)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.white.opacity(0.20), in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.hoyoPink, Color.hoyoPink.opacity(0.70), Color.hoyoMint],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.hoyoNavy, lineWidth: 2.5))
    }

    // MARK: - Bilibili Card

    private var bilibiliCard: some View {
        Button { openBilibiliSearch() } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "00A1D6"))
                    .frame(width: 48, height: 48)
                    .overlay(Text("bili").font(.system(size: 12, weight: .black)).foregroundStyle(.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hoyoNavy, lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text("在哔哩哔哩搜索攻略")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.hoyoNavy)
                    Text(event.title)
                        .font(.system(size: 12)).foregroundStyle(Color.hoyoNavy.opacity(0.40)).lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.hoyoLavender, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.hoyoNavy, lineWidth: 1.5))
            }
            .padding(16)
            .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hoyoNavy, lineWidth: 2.5))
        }
        .buttonStyle(CardPressStyle())
    }

    // MARK: - Detail Card

    private var detailCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.hoyoPink, in: RoundedRectangle(cornerRadius: 7))
                Text("活动详情")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.hoyoNavy)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            let rows: [(String, String, String, Bool)] = [
                ("gamecontroller.fill", "所属游戏", gameEmoji + " " + gameName, false),
                ("tag.fill",            "活动类型", event.category,              false),
                ("calendar",           "结束时间", event.endDateShort + "结束",  false),
                ("clock",              "剩余时间", event.remaining > 0 ? event.remainingText : "已结束", true),
            ]

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(Color.hoyoNavy.opacity(0.06)).frame(height: 1).padding(.horizontal, 16)
                HStack(spacing: 10) {
                    Image(systemName: row.0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(row.3 && isUrgent ? Color.hoyoPink : Color.hoyoNavy.opacity(0.40))
                        .frame(width: 20)
                    Text(row.1)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                        .frame(width: 64, alignment: .leading)
                    Text(row.2)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.3 && isUrgent ? Color.hoyoPink : Color.hoyoNavy)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
        }
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.hoyoNavy, lineWidth: 2.5))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // With the vertical bar, 返回 lives there instead.
            if !hasVerticalBar {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.hoyoNavy, in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        ToolbarItem(placement: .principal) {
            Text("活动攻略")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isUrgent {
                Button { } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .black))
                        Text("即将结束")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.hoyoPink, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.hoyoNavy, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func toggleDone() {
        event.isDone.toggle()
    }
}

// MARK: - Bilibili Link Guide Sheet

struct BilibiliLinkGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // ── 操作步骤 ──────────────────────────────────────────────
                Section {
                    stepRow(number: "1", title: "打开哔哩哔哩搜索版本公告",
                            detail: "在 B站搜索「游戏名 + 版本号 + 活动一览」，例如「鸣潮 2.x 版本活动一览」，找官方账号发布的综合公告专栏文章。")
                    stepRow(number: "2", title: "选整个版本的综合公告",
                            detail: "要选标题包含版本号、内容列出多个活动时间表的文章，而不是单个活动的独立介绍页。")
                    stepRow(number: "3", title: "分享 → 复制链接",
                            detail: "点击文章右上角「分享」按钮，选「复制链接」，会得到 b23.tv/xxx 格式的短链，粘贴到输入框即可。")
                } header: {
                    Label("操作步骤", systemImage: "list.number")
                        .textCase(nil)
                        .font(.subheadline).fontWeight(.semibold)
                }

                // ── 验证码说明 ────────────────────────────────────────────
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color.hoyoMint)
                            .font(.title3)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("遇到验证码怎么办")
                                .font(.subheadline).fontWeight(.semibold)
                            Text("B站有时会弹出滑动验证码。在内置浏览器里手动完成验证后，等页面内容加载完毕，再点右上角「提取内容」即可。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.hoyoPink)
                            .font(.title3)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("页面加载完再提取")
                                .font(.subheadline).fontWeight(.semibold)
                            Text("等顶部加载提示消失、文章正文完整显示后，再点「提取内容」，可以获得更准确的提取结果。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("注意事项", systemImage: "info.circle")
                        .textCase(nil)
                        .font(.subheadline).fontWeight(.semibold)
                }

                // ── 链接示例 ──────────────────────────────────────────────
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("正确示例", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.hoyoMint)
                            .font(.caption).fontWeight(.semibold)
                        Text("b23.tv/ESpbRoA")
                            .font(.caption2).foregroundStyle(.secondary).monospaced()
                        Text("（B站分享短链，指向版本综合公告专栏）")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("错误示例", systemImage: "xmark.circle.fill")
                            .foregroundStyle(Color.hoyoPink)
                            .font(.caption).fontWeight(.semibold)
                        Text("b23.tv/xxxxx（单个活动介绍页）")
                            .font(.caption2).foregroundStyle(.secondary).monospaced()
                        Text("单个活动页只有该活动信息，无法提取到全部活动时间。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Label("链接示例", systemImage: "doc.text.magnifyingglass")
                        .textCase(nil)
                        .font(.subheadline).fontWeight(.semibold)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.hoyoBg)
            .navigationTitle("如何获取公告链接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.subheadline).fontWeight(.black)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.hoyoPink, in: Circle())
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline).fontWeight(.semibold)
                Text(detail)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Complete Task Guide Sheet

struct CompleteTaskGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // ── 方法一：App 内标记 ────────────────────────────────────
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "circle")
                            .font(.title)
                            .foregroundStyle(Color.secondary)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("直接在 App 内标记")
                                .font(.subheadline).fontWeight(.semibold)
                            Text("每条活动右侧有一个圆圈按钮，办妥后点一下，圆圈会变成绿色勾选状态，同时取消该活动的后续提醒通知。")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Label("方法一", systemImage: "hand.tap")
                        .textCase(nil).font(.subheadline).fontWeight(.semibold)
                }

                // ── 方法二：通知快捷操作 ──────────────────────────────────
                Section {
                    stepRow(
                        number: "1",
                        title:  "收到每日提醒",
                        detail: "每天在你设置的时间（默认 21:00），婉婉只提醒 7 天内快结束的活动。"
                    )
                    stepRow(
                        number: "2",
                        title:  "下拉或长按通知横幅",
                        detail: "通知出现在屏幕顶部时，向下滑动通知横幅；若在锁屏上，长按通知卡片。"
                    )
                    stepRow(
                        number: "3",
                        title: "点击【已完成】",
                        detail: "展开后会出现【已完成】按钮，点击即可直接标记，不需要解锁或打开 App。"
                    )
                } header: {
                    Label("方法二：通知快捷操作", systemImage: "bell.badge")
                        .textCase(nil).font(.subheadline).fontWeight(.semibold)
                }

                // ── 说明 ──────────────────────────────────────────────────
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.hoyoMint)
                            .font(.title3).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("标记完成后")
                                .font(.subheadline).fontWeight(.semibold)
                            Text("该活动的所有后续通知会自动取消，活动行显示为半透明划掉状态。如果手误，可以长按活动行 → 选【标记为未完成】来撤销。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("说明", systemImage: "lightbulb")
                        .textCase(nil).font(.subheadline).fontWeight(.semibold)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.hoyoBg)
            .navigationTitle("如何标记完成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("知道了") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.subheadline).fontWeight(.black)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.hoyoPink, in: Circle())
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
