import WidgetKit
import SwiftUI

// MARK: - Shared data model (mirrors SharedWidgetData.swift in main app)

private let sharedAppGroupID = "group.com.object1.eventreminder"

struct WidgetEvent: Codable {
    let id: String
    let title: String
    let gameEmoji: String
    let gameName: String
    let endDate: Date
    let urgencyLevel: Int
}

private func readWidgetEvents() -> [WidgetEvent] {
    guard let defaults = UserDefaults(suiteName: sharedAppGroupID),
          let data = defaults.data(forKey: "widgetEvents"),
          let events = try? JSONDecoder().decode([WidgetEvent].self, from: data)
    else { return [] }
    return events
}

// MARK: - Timeline

struct EventEntry: TimelineEntry {
    let date: Date
    let events: [WidgetEvent]
}

struct EventTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> EventEntry {
        EventEntry(date: .now, events: [
            WidgetEvent(id: "p", title: "示例活动名称", gameEmoji: "🌿",
                        gameName: "原神", endDate: .now.addingTimeInterval(3 * 86400), urgencyLevel: 1)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (EventEntry) -> Void) {
        completion(EventEntry(date: .now, events: readWidgetEvents()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EventEntry>) -> Void) {
        let entry   = EventEntry(date: .now, events: readWidgetEvents())
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

// MARK: - Views

private func urgencyColor(_ level: Int) -> Color {
    switch level {
    case 3:  return .hoyoPink
    case 2:  return .orange
    case 1:  return .hoyoMint
    default: return .hoyoLavender
    }
}

private func daysLeft(_ e: WidgetEvent) -> String {
    let secs = e.endDate.timeIntervalSinceNow
    let days = Int(secs / 86400)
    if days > 0 { return "剩\(days)天" }
    let hours = Int(secs / 3600)
    if hours > 0 { return "剩\(hours)时" }
    return "即将结束"
}

// Countdown capsule pill, styled after the app's in-list countdown badge
private struct CountdownPill: View {
    let level: Int
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .black))
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.28), value: text)
        }
        .foregroundStyle(level >= 2 ? .white : Color.hoyoNavy)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(urgencyColor(level))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.hoyoNavy, lineWidth: 1.2))
        .fontDesign(.rounded)
    }
}

// Game emoji + name pill, styled after the app's game tag badge
private struct GameTag: View {
    let emoji: String
    let name: String
    var body: some View {
        Text(emoji + " " + name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.hoyoPink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.hoyoPink.opacity(0.14), in: Capsule())
            .fontDesign(.rounded)
    }
}

private struct EventRow: View {
    let event: WidgetEvent
    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(urgencyColor(event.urgencyLevel))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 3) {
                GameTag(emoji: event.gameEmoji, name: event.gameName)
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hoyoNavy)
                    .lineLimit(1)
                    .fontDesign(.rounded)
            }

            Spacer(minLength: 4)

            CountdownPill(level: event.urgencyLevel, text: daysLeft(event))
        }
    }
}

// Small widget: single most-urgent event
private struct SmallWidgetView: View {
    let entry: EventEntry
    var body: some View {
        if let e = entry.events.first {
            VStack(alignment: .leading, spacing: 8) {
                GameTag(emoji: e.gameEmoji, name: e.gameName)
                Text(e.title)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.hoyoNavy)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fontDesign(.rounded)
                Spacer()
                CountdownPill(level: e.urgencyLevel, text: daysLeft(e))
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 4) {
                Text("🎮")
                    .font(.system(size: 22))
                Text("暂无活动")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                    .fontDesign(.rounded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// Medium widget: up to 3 events
private struct MediumWidgetView: View {
    let entry: EventEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.hoyoPink)
                    Text("活动提醒")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.hoyoPink)
                        .fontDesign(.rounded)
                }
                Spacer()
                Text(entry.date.formatted(.dateTime.month().day()))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hoyoNavy.opacity(0.35))
                    .fontDesign(.rounded)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if entry.events.isEmpty {
                Text("暂无进行中的活动")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                    .fontDesign(.rounded)
                    .padding(.horizontal, 14)
            } else {
                ForEach(Array(entry.events.prefix(3).enumerated()), id: \.element.id) { index, event in
                    if index > 0 {
                        Divider().overlay(Color.hoyoPink.opacity(0.18)).padding(.horizontal, 14)
                    }
                    EventRow(event: event)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Widget Declaration

struct EventCountdownWidget: Widget {
    let kind = "EventCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EventTimelineProvider()) { entry in
            EventWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color.hoyoBg, Color.hoyoPink.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("二游活动小灵通倒计时")
        .description("显示最近即将结束的米哈游游戏活动。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct EventWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: EventEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        default:            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Previews

#Preview(as: .systemSmall) {
    EventCountdownWidget()
} timeline: {
    EventEntry(date: .now, events: [
        WidgetEvent(id: "1", title: "「无名歌」复刻祈愿", gameEmoji: "🌿", gameName: "原神",
                    endDate: .now.addingTimeInterval(2 * 86400 + 5 * 3600), urgencyLevel: 3)
    ])
    EventEntry(date: .now, events: [])
}

#Preview(as: .systemMedium) {
    EventCountdownWidget()
} timeline: {
    EventEntry(date: .now, events: [
        WidgetEvent(id: "1", title: "「无名歌」复刻祈愿", gameEmoji: "🌿", gameName: "原神",
                    endDate: .now.addingTimeInterval(2 * 86400 + 5 * 3600), urgencyLevel: 3),
        WidgetEvent(id: "2", title: "前路回响 唤光迎宾活动", gameEmoji: "⭐", gameName: "崩坏：星穹铁道",
                    endDate: .now.addingTimeInterval(5 * 86400), urgencyLevel: 2),
        WidgetEvent(id: "3", title: "深渊狙击模式开启", gameEmoji: "🔮", gameName: "绝区零",
                    endDate: .now.addingTimeInterval(10 * 86400), urgencyLevel: 1)
    ])
}
