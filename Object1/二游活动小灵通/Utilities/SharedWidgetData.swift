import Foundation

// App Group identifier — must match in both main app and widget extension entitlements.
// Change this to match your actual bundle ID prefix.
let sharedAppGroupID = "group.com.object1.eventreminder"

// Lightweight snapshot written by the main app and read by the widget extension.
struct WidgetEvent: Codable {
    let id: String
    let title: String
    let gameEmoji: String
    let gameName: String
    let endDate: Date
    let urgencyLevel: Int   // 0=calm 1=normal 2=warning 3=critical
}

enum SharedWidgetData {
    private static let key = "widgetEvents"

    static func write(events: [RemoteEvent]) {
        let top = events
            .filter { !$0.isDone && $0.remaining > 0 }
            .sorted { $0.endDate < $1.endDate }
            .prefix(5)
            .map { e -> WidgetEvent in
                let level: Int
                switch e.urgency {
                case .critical: level = 3
                case .warning:  level = 2
                case .normal:   level = 1
                default:        level = 0
                }
                return WidgetEvent(
                    id:           e.id,
                    title:        e.title,
                    gameEmoji:    e.game.emoji,
                    gameName:     e.game.displayName,
                    endDate:      e.endDate,
                    urgencyLevel: level
                )
            }

        guard let defaults = UserDefaults(suiteName: sharedAppGroupID),
              let data = try? JSONEncoder().encode(Array(top)) else { return }
        defaults.set(data, forKey: key)
    }

    static func read() -> [WidgetEvent] {
        guard let defaults = UserDefaults(suiteName: sharedAppGroupID),
              let data = defaults.data(forKey: key),
              let events = try? JSONDecoder().decode([WidgetEvent].self, from: data)
        else { return [] }
        return events
    }

    static func clear() {
        UserDefaults(suiteName: sharedAppGroupID)?.removeObject(forKey: key)
    }
}
