import Foundation
import SwiftUI

// MARK: - Game

enum HoYoGame: String, CaseIterable, Identifiable {
    case genshin  = "genshin"
    case starrail = "starrail"
    case zenless  = "zenless"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .genshin:  return "原神"
        case .starrail: return "崩坏：星穹铁道"
        case .zenless:  return "绝区零"
        }
    }

    var emoji: String {
        switch self {
        case .genshin:  return "🌿"
        case .starrail: return "⭐"
        case .zenless:  return "⚡️"
        }
    }

    var accentColor: Color {
        switch self {
        case .genshin:  return .hoyoMint
        case .starrail: return .hoyoPink
        case .zenless:  return .hoyoYellow
        }
    }

    var englishName: String {
        switch self {
        case .genshin:  return "Genshin Impact"
        case .starrail: return "Honkai Star Rail"
        case .zenless:  return "Zenless Zone Zero"
        }
    }

    var cardHeaderColor: Color {
        switch self {
        case .genshin:  return Color(hex: "7B5EA7")
        case .starrail: return Color(hex: "4A72C4")
        case .zenless:  return Color(hex: "E2A900")
        }
    }
}

// Hashable lets RemoteEvent be used with navigationDestination(item:).
// Equality is id-only so deduplication works; body still always re-evaluates
// because timer-driven @State changes propagate through the view hierarchy.
extension RemoteEvent: Hashable {
    static func == (lhs: RemoteEvent, rhs: RemoteEvent) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - API Response (Codable)

struct CalendarResponse: Codable {
    var events:     [APIEvent]
    var challenges: [APIChallenge]

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        events     = (try? c.decode([APIEvent].self,     forKey: .events))     ?? []
        challenges = (try? c.decode([APIChallenge].self, forKey: .challenges)) ?? []
    }
}

struct APIEvent: Codable {
    let id:          Int
    let name:        String
    let description: String?
    let imageUrl:    String?
    let typeName:    String?
    let startTime:   Int
    let endTime:     Int
}

struct APIChallenge: Codable {
    let id:        Int
    let name:      String
    let typeName:  String?
    let startTime: Int?
    let endTime:   Int?
}

// MARK: - Unified Display Model

struct RemoteEvent: Identifiable {
    let id:        String      // "{game}_{category}_{apiId}"
    let game:      HoYoGame
    let title:     String      // Chinese display name
    let category:  String      // "活动" / "挑战"
    let startDate:    Date
    let endDate:      Date
    let subtitle:     String?
    let imageURL:     URL?
    var isDone:       Bool

    // MARK: Urgency

    enum Urgency {
        case done, expired, critical, warning, normal, calm

        var color: Color {
            switch self {
            case .done, .expired: return .gray
            case .critical:       return .hoyoPink
            case .warning:        return .orange
            case .normal:         return .hoyoMint
            case .calm:           return .blue
            }
        }
    }

    var remaining: TimeInterval { endDate.timeIntervalSinceNow }

    var endDateShort: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M月d日"
        return f.string(from: endDate)
    }

    var remainingText: String {
        if isDone { return "已完成" }
        let rem = Int(remaining)
        if rem <= 0 { return "已结束" }
        let days    = rem / 86400
        let hours   = (rem % 86400) / 3600
        let minutes = (rem % 3600) / 60
        if days  > 0 { return "剩余 \(days)天 \(hours)时" }
        if hours > 0 { return "剩余 \(hours)时 \(minutes)分" }
        return "剩余 \(minutes)分"
    }

    var urgency: Urgency {
        if isDone { return .done }
        let rem = remaining
        if rem <= 0              { return .expired }
        if rem < 24  * 3600     { return .critical }
        if rem < 72  * 3600     { return .warning }
        if rem < 7 * 24 * 3600  { return .normal }
        return .calm
    }

    // MARK: Factory

    static func from(_ e: APIEvent, game: HoYoGame, completedIds: Set<String>) -> RemoteEvent {
        let id = "\(game.rawValue)_event_\(e.id)"
        return RemoteEvent(
            id:        id,
            game:      game,
            title:     e.name,
            category:  "活动",
            startDate: Date(timeIntervalSince1970: TimeInterval(e.startTime)),
            endDate:   Date(timeIntervalSince1970: TimeInterval(e.endTime)),
            subtitle:  e.typeName,
            imageURL:  e.imageUrl.flatMap { URL(string: $0) },
            isDone:    completedIds.contains(id)
        )
    }

    static func from(_ c: APIChallenge, game: HoYoGame, completedIds: Set<String>) -> RemoteEvent? {
        guard let startTime = c.startTime, let endTime = c.endTime else { return nil }
        // Challenge IDs from the upstream API are not globally unique. For example,
        // Genshin may return both Spiral Abyss and Imaginarium Theater with id == 0.
        // Include the challenge kind and cycle so SwiftUI and persisted state can
        // distinguish them while keeping the identity stable across refreshes.
        let challengeKind = c.typeName ?? c.name
        let id = [
            game.rawValue,
            "challenge",
            String(c.id),
            challengeKind,
            String(startTime),
            String(endTime)
        ].joined(separator: "_")
        return RemoteEvent(
            id:        id,
            game:      game,
            title:     c.name,
            category:  "挑战",
            startDate: Date(timeIntervalSince1970: TimeInterval(startTime)),
            endDate:   Date(timeIntervalSince1970: TimeInterval(endTime)),
            subtitle:  c.typeName,
            imageURL:  nil,
            isDone:    completedIds.contains(id)
        )
    }
}
