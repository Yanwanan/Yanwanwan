import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ActivityService {
    var events: [RemoteEvent] = []
    var isLoading = false
    var errorMessage: String? = nil
    var lastUpdated: Date? = nil

    // Refresh: fetch API for all followed games, fall back to cache on failure.
    func refresh(preferences: UserPreferences) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        preferences.removeLegacyChallengeState()
        let games        = preferences.followedGames
        let completedIds = Set(preferences.completedEventIds)

        var fetched: [RemoteEvent] = []
        var hadNetworkError = false

        for game in games {
            do {
                let response = try await fetchCalendar(for: game, lang: "zh-cn")
                if let data = try? makeEncoder().encode(response) {
                    preferences.setCachedJSON(data, for: game)
                }
                fetched += buildEvents(from: response, game: game, completedIds: completedIds)
            } catch is GameNotSupported {
                // API doesn't have data for this game yet — skip silently, no error banner.
            } catch is CancellationError {
                // Task was cancelled (app backgrounded / view dismissed) — not a network error.
                break
            } catch {
                hadNetworkError = true
                if let cached = preferences.cachedJSON(for: game),
                   let response = try? makeDecoder().decode(CalendarResponse.self, from: cached) {
                    fetched += buildEvents(from: response, game: game, completedIds: completedIds)
                }
            }
        }

        if hadNetworkError && fetched.isEmpty {
            // Network failed and no cache available — keep whatever events are already shown
            // (populated by loadFromCache before this refresh ran) and surface the error.
            errorMessage = "网络开小差了，婉婉先给你看缓存数据"
        } else {
            // Success or partial cache fallback — update events list.
            events = sorted(fetched)
            SharedWidgetData.write(events: events)
            errorMessage = nil
        }

        isLoading = false

        if !hadNetworkError {
            preferences.lastFetchedAt = Date()
            lastUpdated = preferences.lastFetchedAt
            let liveIds = Set(fetched.map(\.id))
            preferences.pruneCompletedIds(keeping: liveIds)
            preferences.pruneMutedIds(keeping: liveIds)
        }

        NotificationManager.shared.rescheduleAll()
    }

    // Load cache immediately without network, to avoid blank screen on launch.
    func loadFromCache(preferences: UserPreferences) {
        preferences.removeLegacyChallengeState()
        let completedIds = Set(preferences.completedEventIds)
        var cached: [RemoteEvent] = []

        for game in preferences.followedGames {
            if let data = preferences.cachedJSON(for: game),
               let response = try? makeDecoder().decode(CalendarResponse.self, from: data) {
                cached += buildEvents(from: response, game: game, completedIds: completedIds)
            }
        }

        if !cached.isEmpty {
            events = sorted(cached)
            lastUpdated = preferences.lastFetchedAt
        }
    }

    // Update isDone flags without re-fetching.
    func applyCompletion(completedIds: Set<String>) {
        events = events.map {
            var e = $0
            e.isDone = completedIds.contains(e.id)
            return e
        }
    }

    // MARK: - Private helpers

    // Thrown when the API explicitly returns 404 for a game (not yet supported by the API).
    // Callers can silently skip rather than showing an error banner.
    private struct GameNotSupported: Error {}

    private func fetchCalendar(for game: HoYoGame, lang: String = "zh-cn") async throws -> CalendarResponse {
        // 经自己的后端缓存代理请求，上游不可用时后端会返回最近一次成功的数据。
        guard let url = APIConfig.calendarURL(game: game.rawValue, lang: lang) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 404 { throw GameNotSupported() }
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try makeDecoder().decode(CalendarResponse.self, from: data)
    }

    private func buildEvents(
        from response: CalendarResponse,
        game: HoYoGame,
        completedIds: Set<String>
    ) -> [RemoteEvent] {
        var result: [RemoteEvent] = []
        result += response.events.map     { RemoteEvent.from($0, game: game, completedIds: completedIds) }
        result += response.challenges.compactMap { RemoteEvent.from($0, game: game, completedIds: completedIds) }

        var seenIds = Set<String>()
        return result.filter {
            $0.remaining > -24 * 3600 && seenIds.insert($0.id).inserted
        }
    }

    private func sorted(_ events: [RemoteEvent]) -> [RemoteEvent] {
        events.sorted { lhs, rhs in
            let lExpired = lhs.remaining <= 0
            let rExpired = rhs.remaining <= 0
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            if lExpired   != rExpired   { return !lExpired }
            return lhs.endDate < rhs.endDate
        }
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
