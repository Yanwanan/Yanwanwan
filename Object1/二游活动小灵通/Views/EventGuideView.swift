import SwiftUI
import SwiftData

struct EventGuideView: View {
    let event: RemoteEvent

    @Environment(ActivityService.self) private var service
    @Environment(\.openURL)            private var openURL
    @Environment(\.dismiss)            private var dismiss
    @Environment(\.hasVerticalBar)     private var hasVerticalBar
    @Environment(\.isWideLayout) private var isWideLayout
    @Query private var prefsQuery: [UserPreferences]

    private var prefs: UserPreferences? { prefsQuery.first }
    private var isUrgent: Bool { event.urgency == .critical || event.urgency == .warning }

    private var bilibiliSearchKeyword: String {
        let q = "\(event.game.displayName) \(event.title) 攻略"
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
            // Top row: game tag
            HStack(alignment: .top) {
                Text(event.game.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.hoyoNavy.opacity(0.45), in: Capsule())

                Spacer()
            }
            .padding(.bottom, 14)

            // Event title
            Text(event.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(2)
                .padding(.bottom, 6)

            // Large countdown
            Text(event.remainingText)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.bottom, 18)

            // Bottom badges
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                    Text(event.endDateShort + "结束")
                        .font(.system(size: 12, weight: .semibold))
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
                colors: [event.game.cardHeaderColor, event.game.cardHeaderColor.opacity(0.70), Color.hoyoLavender],
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.hoyoNavy)
                    Text(event.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.hoyoNavy.opacity(0.40))
                        .lineLimit(1)
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
            // Header
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

            let isUrgentTime = event.remaining > 0 && event.remaining <= 2 * 86400
            let rows: [(String, String, String, Bool)] = [
                ("gamecontroller.fill", "所属游戏", event.game.emoji + " " + event.game.displayName, false),
                ("tag.fill",            "活动类型", event.category,                                   false),
                ("calendar",           "结束时间", event.endDateShort + "结束",                       false),
                ("clock",              "剩余时间", event.remaining > 0 ? event.remainingText : "已结束", true),
            ]

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle().fill(Color.hoyoNavy.opacity(0.06)).frame(height: 1).padding(.horizontal, 16)
                HStack(spacing: 10) {
                    Image(systemName: row.0)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(row.3 && isUrgentTime ? Color.hoyoPink : Color.hoyoNavy.opacity(0.40))
                        .frame(width: 20)
                    Text(row.1)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                        .frame(width: 64, alignment: .leading)
                    Text(row.2)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.3 && isUrgentTime ? Color.hoyoPink : Color.hoyoNavy)
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
            if isUrgent && !event.isDone {
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
        guard let p = prefs else { return }
        if event.isDone {
            p.markIncomplete(event.id)
        } else {
            p.markCompleted(event.id)
        }
        service.applyCompletion(completedIds: Set(p.completedEventIds))
        NotificationManager.shared.rescheduleAll()
    }
}
