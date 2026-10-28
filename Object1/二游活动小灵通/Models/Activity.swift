import Foundation
import SwiftData

@Model
final class UserPreferences {
    var followedGameSlugs: [String]
    var completedEventIds: [String]
    var mutedEventIds: [String]
    var notificationLeadHours: Int
    var notificationHour: Int
    var notificationMinute: Int
    var dailyReminderEnabled: Bool
    var cachedGenshinJSON: Data?
    var cachedStarrailJSON: Data?
    var cachedZenlessJSON: Data?
    var lastFetchedAt: Date?

    init(
        followedGameSlugs: [String] = ["genshin", "starrail", "zenless"],
        completedEventIds: [String] = [],
        mutedEventIds: [String] = [],
        notificationLeadHours: Int = 24,
        notificationHour: Int = 21,
        notificationMinute: Int = 0,
        dailyReminderEnabled: Bool = true
    ) {
        self.followedGameSlugs = followedGameSlugs
        self.completedEventIds = completedEventIds
        self.mutedEventIds = mutedEventIds
        self.notificationLeadHours = notificationLeadHours
        self.notificationHour = notificationHour
        self.notificationMinute = notificationMinute
        self.dailyReminderEnabled = dailyReminderEnabled
    }

    var followedGames: [HoYoGame] {
        followedGameSlugs.compactMap { HoYoGame(rawValue: $0) }
    }

    func isFollowing(_ game: HoYoGame) -> Bool {
        followedGameSlugs.contains(game.rawValue)
    }

    func toggleGame(_ game: HoYoGame) {
        if let idx = followedGameSlugs.firstIndex(of: game.rawValue) {
            followedGameSlugs.remove(at: idx)
        } else {
            followedGameSlugs.append(game.rawValue)
        }
    }

    func markCompleted(_ eventId: String) {
        guard !completedEventIds.contains(eventId) else { return }
        completedEventIds = completedEventIds + [eventId]
    }

    func isMuted(_ eventId: String) -> Bool { mutedEventIds.contains(eventId) }

    func toggleMute(_ eventId: String) {
        if let idx = mutedEventIds.firstIndex(of: eventId) {
            mutedEventIds.remove(at: idx)
        } else {
            mutedEventIds = mutedEventIds + [eventId]
        }
    }

    // Remove completed IDs that are no longer in the current live event list.
    // Call after a successful network fetch to prevent unbounded growth.
    func pruneCompletedIds(keeping liveIds: Set<String>) {
        completedEventIds = completedEventIds.filter { liveIds.contains($0) }
    }

    func pruneMutedIds(keeping liveIds: Set<String>) {
        mutedEventIds = mutedEventIds.filter { liveIds.contains($0) }
    }

    // Challenge IDs used to be "{game}_challenge_{apiId}". The API can reuse the
    // same numeric ID for different challenges, so those saved states are
    // ambiguous and must not be applied to the new compound IDs.
    func removeLegacyChallengeState() {
        let legacyPrefixes = HoYoGame.allCases.map { "\($0.rawValue)_challenge_" }

        func isLegacyChallengeID(_ id: String) -> Bool {
            guard let prefix = legacyPrefixes.first(where: { id.hasPrefix($0) }) else {
                return false
            }
            return id.dropFirst(prefix.count).allSatisfy(\.isNumber)
        }

        completedEventIds = completedEventIds.filter { !isLegacyChallengeID($0) }
        mutedEventIds = mutedEventIds.filter { !isLegacyChallengeID($0) }
    }

    func markIncomplete(_ eventId: String) {
        completedEventIds = completedEventIds.filter { $0 != eventId }
    }

    func isCompleted(_ eventId: String) -> Bool {
        completedEventIds.contains(eventId)
    }

    func cachedJSON(for game: HoYoGame) -> Data? {
        switch game {
        case .genshin:  return cachedGenshinJSON
        case .starrail: return cachedStarrailJSON
        case .zenless:  return cachedZenlessJSON
        }
    }

    func setCachedJSON(_ data: Data, for game: HoYoGame) {
        switch game {
        case .genshin:  cachedGenshinJSON = data
        case .starrail: cachedStarrailJSON = data
        case .zenless:  cachedZenlessJSON = data
        }
    }


}
