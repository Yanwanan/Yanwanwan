import SwiftUI
import SwiftData

struct AIGameSearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss
    @Environment(\.openURL)      private var openURL
    @Environment(PurchaseService.self) private var purchaseService
    @Query private var prefsQuery: [UserPreferences]
    @Query private var customGames: [CustomGame]

    private let recommendedBilibiliSpaces: [RecommendedBilibiliSpace] = [
        .init(name: "鸣潮", emoji: "🌊", colorHex: CustomGamePalette.mint.rawValue, url: "https://b23.tv/Wdixy1J"),
        .init(name: "战双帕弥什", emoji: "⚔️", colorHex: CustomGamePalette.purple.rawValue, url: "https://b23.tv/AZBFXO0"),
        .init(name: "终末地", emoji: "🧭", colorHex: CustomGamePalette.yellow.rawValue, url: "https://b23.tv/LwktPtX"),
        .init(name: "异环", emoji: "🔮", colorHex: CustomGamePalette.violet.rawValue, url: "https://b23.tv/4zzUBvF"),
        .init(name: "幻塔", emoji: "🗼", colorHex: CustomGamePalette.pink.rawValue, url: "https://b23.tv/Akp3x70"),
        .init(name: "洛克王国世界", emoji: "👑", colorHex: CustomGamePalette.yellow.rawValue, url: "https://b23.tv/StJcE8K"),
        .init(name: "少女前线2追放", emoji: "🎯", colorHex: CustomGamePalette.violet.rawValue, url: "https://b23.tv/aNZgNA8"),
        .init(name: "碧蓝航线", emoji: "⚓", colorHex: CustomGamePalette.mint.rawValue, url: "https://b23.tv/vW1KLKz"),
        .init(name: "尘白禁区", emoji: "❄️", colorHex: CustomGamePalette.purple.rawValue, url: "https://b23.tv/0d6PbvL"),
        .init(name: "碧蓝档案", emoji: "📘", colorHex: CustomGamePalette.violet.rawValue, url: "https://b23.tv/DQmnvde")
    ]

    private enum AddGameStep {
        case chooseGame
        case pasteLink
    }

    @State private var currentStep      = AddGameStep.chooseGame
    @State private var aiService        = AIGameService()
    @State private var gameName         = ""
    @State private var gameEmoji        = "🎮"
    @State private var colorHex         = CustomGamePalette.violet.rawValue
    @State private var articleURL       = ""
    @State private var drafts:          [AIEventDraft] = []
    @State private var hasSearched      = false
    @State private var showLinkGuide    = false
    @State private var showPremium      = false
    @State private var saveLimitMessage: String? = nil
    @State private var saveErrorMessage: String? = nil
    @State private var pendingRecommendedSpace: RecommendedBilibiliSpace? = nil
    @State private var webExtractorItem: WebExtractorTarget? = nil
    @State private var showAIDisclosure = false
    @State private var pendingExtractionURL: URL? = nil

    private struct WebExtractorTarget: Identifiable {
        let id  = UUID()
        let url: URL
    }

    private struct RecommendedBilibiliSpace: Identifiable {
        let name: String
        let emoji: String
        let colorHex: String
        let url: String

        var id: String { name }
    }

    private struct BilibiliOfficialSpaceGuideSheet: View {
        let space: RecommendedBilibiliSpace
        let onOpen: () -> Void

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 12) {
                            Text(space.emoji)
                                .font(.largeTitle)
                                .frame(width: 48, height: 48)
                                .background(Color.hoyoPink.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(space.name)
                                    .font(.headline)
                                    .foregroundStyle(Color.hoyoNavy)
                                Text("B站官方空间")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section {
                        guideStep(number: "1", title: "打开官方空间",
                                  detail: "点下方按钮跳转到手机上的 B站 App。")
                        guideStep(number: "2", title: "寻找图文，选择最新版本公告",
                                  detail: "在官方空间里进入「图文」内容，选择最新版本的综合公告，不要选单个活动介绍。")
                        guideStep(number: "3", title: "分享并复制链接",
                                  detail: "在公告页点分享，复制 b23.tv 短链，回到本页点「粘贴」。")
                    } header: {
                        Label("操作步骤", systemImage: "list.number")
                            .textCase(nil)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Section {
                        Button {
                            dismiss()
                            onOpen()
                        } label: {
                            HStack {
                                Spacer()
                                Label("去 B站", systemImage: "arrow.up.forward.app")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .foregroundStyle(Color.hoyoPink)
                    } footer: {
                        Text("从 B站复制公告链接后回到本页，使用「粘贴」按钮填入公告链接。")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.hoyoBg)
                .navigationTitle("去 B站找公告")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                }
            }
        }

        @ViewBuilder
        private func guideStep(number: String, title: String, detail: String) -> some View {
            HStack(alignment: .top, spacing: 12) {
                Text(number)
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.hoyoPink, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if currentStep == .chooseGame {
                    chooseGameSections
                } else {
                    pasteLinkSections
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.hoyoBg)
            .sheet(isPresented: $showLinkGuide) { BilibiliLinkGuideSheet() }
            .sheet(item: $pendingRecommendedSpace) { space in
                BilibiliOfficialSpaceGuideSheet(space: space) {
                    openRecommendedSpace(space)
                }
            }
            .sheet(isPresented: $showPremium) { PremiumView() }
            .sheet(isPresented: $showAIDisclosure) {
                AIProcessingDisclosureView {
                    if let url = pendingExtractionURL {
                        webExtractorItem = WebExtractorTarget(url: url)
                    }
                    pendingExtractionURL = nil
                }
            }
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
            .alert("自定义游戏已达上限", isPresented: Binding(
                get: { saveLimitMessage != nil },
                set: { if !$0 { saveLimitMessage = nil } }
            )) {
                if !purchaseService.isPremium {
                    Button("升级会员") {
                        saveLimitMessage = nil
                        showPremium = true
                    }
                }
                Button("知道了", role: .cancel) {}
            } message: {
                Text(saveLimitMessage ?? "")
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .sheet(item: $webExtractorItem) { item in
                WebExtractorSheet(url: item.url) { extractedText, finalURL in
                    let name = gameName.trimmingCharacters(in: .whitespaces)
                    Task {
                        hasSearched = false
                        let entitlementProof = await purchaseService.currentEntitlementJWS()
                        drafts = await aiService.extractEvents(
                            from: extractedText,
                            gameName: name,
                            articleURL: finalURL,
                            entitlementTier: purchaseService.tier,
                            appStoreTransactionJWS: entitlementProof
                        )
                        hasSearched = true
                    }
                }
            }
            .navigationTitle(currentStep == .chooseGame ? "选择游戏" : "提取公告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep == .chooseGame {
                        Button("取消") { dismiss() }
                    } else {
                        Button("重选") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep = .chooseGame
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if currentStep == .pasteLink {
                        Button("保存") { save() }
                            .fontWeight(.semibold)
                            .disabled(
                                gameName.trimmingCharacters(in: .whitespaces).isEmpty ||
                                drafts.filter(\.isSelected).isEmpty
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chooseGameSections: some View {
        Section {
            ForEach(recommendedBilibiliSpaces) { space in
                Button {
                    selectRecommendedSpace(space)
                } label: {
                    HStack(spacing: 12) {
                        Text(space.emoji)
                            .font(.title3)
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(space.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.hoyoNavy)
                            Text("B站官方空间")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("选择游戏")
        } footer: {
            Text("先选游戏，再按引导打开对应的 B站官方空间。")
        }
    }

    @ViewBuilder
    private var pasteLinkSections: some View {
        Section {
            HStack(spacing: 12) {
                Text(gameEmoji)
                    .font(.title2)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: colorHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(gameName.isEmpty ? "未选择游戏" : gameName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hoyoNavy)
                    Text("已跳转 B站，请粘贴具体版本公告链接")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        } header: {
            Text("当前游戏")
        }

        Section {
            HStack(spacing: 10) {
                TextField("https://b23.tv/...", text: $articleURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    pasteArticleURL()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.hoyoPink)
            }
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
            Text("粘贴从 B站 App 里复制出来的具体版本公告分享链接（b23.tv/…），再用内置浏览器提取内容。")
        }

        Section {
            Button {
                Task { await openBilibiliPage() }
            } label: {
                HStack {
                    Spacer()
                    Label("打开 B站公告页面", systemImage: "tv.fill")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hoyoPink)
                    Spacer()
                }
            }
            .disabled(
                gameName.trimmingCharacters(in: .whitespaces).isEmpty ||
                articleURL.trimmingCharacters(in: .whitespaces).isEmpty ||
                aiService.isSearching ||
                aiService.isCheckingQuota
            )
        } footer: {
            if let err = aiService.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }

        if hasSearched && !drafts.isEmpty {
            Section {
                ForEach($drafts) { $draft in
                    Toggle(isOn: $draft.isSelected) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(draft.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(draft.endDateShort)结束 · \(draft.category)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.hoyoPink)
                }
            } header: {
                Label("AI 整理结果（共 \(drafts.count) 条）", systemImage: "sparkles")
            } footer: {
                Text("以上内容由 \(ComplianceConfig.aiModelName) 整理，仅供参考。请对照游戏官方公告核对名称和日期后再保存。")
            }
        } else if hasSearched && !aiService.isSearching && aiService.errorMessage == nil {
            Section {
                ContentUnavailableView {
                    Label("未找到活动", systemImage: "magnifyingglass")
                } description: {
                    Text("请确认页面内容是否为版本公告，或该游戏当前无限时活动。")
                }
                .listRowBackground(Color.clear)
            }
        }
    }

    private func openBilibiliPage() async {
        let raw = articleURL.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        let urlString = extractFirstURL(from: raw) ?? raw
        guard let url = URL(string: urlString) else {
            aiService.errorMessage = "无法解析链接，请检查格式"
            return
        }
        let entitlementProof = await purchaseService.currentEntitlementJWS()
        guard await aiService.canStartExtraction(
            entitlementTier: purchaseService.tier,
            appStoreTransactionJWS: entitlementProof
        ) else { return }
        if UserDefaults.standard.bool(forKey: PrivacyConsent.aiConsentKey) {
            webExtractorItem = WebExtractorTarget(url: url)
        } else {
            pendingExtractionURL = url
            showAIDisclosure = true
        }
    }

    private func selectRecommendedSpace(_ space: RecommendedBilibiliSpace) {
        gameName = space.name
        gameEmoji = space.emoji
        colorHex = space.colorHex
        articleURL = ""
        drafts = []
        hasSearched = false
        aiService.errorMessage = nil
        aiService.quotaLimitMessage = nil
        pendingRecommendedSpace = space
    }

    private func openRecommendedSpace(_ space: RecommendedBilibiliSpace) {
        pendingRecommendedSpace = nil
        currentStep = .pasteLink

        guard let url = URL(string: space.url) else {
            aiService.errorMessage = "无法打开 \(space.name) 的 B站主页"
            return
        }
        openURL(url)
    }

    private func pasteArticleURL() {
        let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else {
            aiService.errorMessage = "剪贴板里没有可粘贴的公告链接"
            return
        }

        articleURL = extractFirstURL(from: pasted) ?? pasted
        drafts = []
        hasSearched = false
        aiService.errorMessage = nil
        aiService.quotaLimitMessage = nil
    }

    private func extractFirstURL(from text: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range   = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.first {
            guard let scheme = $0.url?.scheme?.lowercased() else { return false }
            return scheme == "https" || scheme == "http"
        }?.url?.absoluteString
    }

    private func save() {
        let name = gameName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let currentCount = currentCustomGameCount()
        let maxCustomGames = purchaseService.tier.maxCustomGames
        guard currentCount < maxCustomGames else {
            saveLimitMessage = purchaseService.tier.customGameLimitMessage(currentCount: currentCount)
            return
        }

        let game = CustomGame(name: name, emoji: gameEmoji.isEmpty ? "🎮" : gameEmoji, colorHex: colorHex)
        modelContext.insert(game)

        let selectedDrafts = drafts.filter(\.isSelected)
        game.replaceEvents(with: selectedDrafts, in: modelContext)
        do {
            try modelContext.save()
            saveErrorMessage = nil
            NotificationManager.shared.rescheduleAll()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func currentCustomGameCount() -> Int {
        customGames.count
    }
}
