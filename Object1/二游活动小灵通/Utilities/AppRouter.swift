import SwiftUI

// MARK: - Routes

enum AppTab: Int {
    case home, games, settings
}

enum GameRoute: Hashable {
    case remote(HoYoGame)
    case custom(String)   // CustomGame.id

    // Matches the ids passed to gameNavigationSource for the zoom transition.
    var sourceID: String {
        switch self {
        case .remote(let game): return game.rawValue
        case .custom(let id):   return id
        }
    }
}

// MARK: - Router

// Shared by the compact (tab bar) and regular (split view) layouts so that
// folding or unfolding keeps the user on the same game and event.
@Observable
final class AppRouter {
    var tab: AppTab = .home
    private(set) var game: GameRoute?
    var remoteEvent: RemoteEvent?
    var customEvent: CustomEvent?

    func selectTab(_ newTab: AppTab) {
        tab = newTab
        selectGame(nil)
    }

    func selectGame(_ route: GameRoute?) {
        if route != game {
            remoteEvent = nil
            customEvent = nil
        }
        game = route
    }

    // Opening a game from the sidebar or a wide dashboard files it under the games tab,
    // which is where it shows up again after folding.
    func openGame(_ route: GameRoute) {
        tab = .games
        selectGame(route)
    }

    var canGoBack: Bool {
        remoteEvent != nil || customEvent != nil || game != nil
    }

    // The vertical bar's back button: close the open event first, then the game.
    func goBack() {
        if remoteEvent != nil || customEvent != nil {
            remoteEvent = nil
            customEvent = nil
        } else {
            selectGame(nil)
        }
    }

    // The one NavigationStack shared by all tabs holds at most the selected game.
    var path: Binding<[GameRoute]> {
        Binding(
            get: { self.game.map { [$0] } ?? [] },
            set: { self.selectGame($0.last) }
        )
    }
}

// MARK: - Activity Stats

// One place for the counts shown on the home overview, game cards and the split-view sidebar.
struct ActivityStats {
    let remoteEvents: [RemoteEvent]
    let customGames: [CustomGame]

    private static let soonWindow: TimeInterval = 7 * 86400

    private var allEvents: [(remaining: TimeInterval, isDone: Bool)] {
        remoteEvents.map { ($0.remaining, $0.isDone) }
            + customGames.flatMap(\.events).map { ($0.remaining, $0.isDone) }
    }

    var totalPending: Int {
        allEvents.filter { $0.remaining > 0 && !$0.isDone }.count
    }

    var totalEndingSoon: Int {
        allEvents.filter { $0.remaining > 0 && $0.remaining <= Self.soonWindow && !$0.isDone }.count
    }

    var totalDone: Int {
        allEvents.filter(\.isDone).count
    }

    func events(for game: HoYoGame) -> [RemoteEvent] {
        remoteEvents.filter { $0.game == game }
    }

    func activeCount(for game: HoYoGame) -> Int {
        events(for: game).filter { $0.remaining > 0 && !$0.isDone }.count
    }

    func totalCount(for game: HoYoGame) -> Int {
        events(for: game).filter { $0.remaining > 0 }.count
    }

    // Completed vs. everything still relevant (completed or not yet ended).
    func progress(for game: HoYoGame) -> (done: Int, total: Int) {
        let events = events(for: game)
        return (events.filter(\.isDone).count, events.filter { $0.isDone || $0.remaining > 0 }.count)
    }

    func progress(for game: CustomGame) -> (done: Int, total: Int) {
        (game.events.filter(\.isDone).count, game.events.filter { $0.isDone || $0.remaining > 0 }.count)
    }

    func soonestRemaining(for game: HoYoGame) -> TimeInterval? {
        events(for: game).filter { $0.remaining > 0 && !$0.isDone }.map(\.remaining).min()
    }

    func soonestRemaining(for game: CustomGame) -> TimeInterval? {
        game.urgentEvent?.remaining
    }

    // The unfinished event closest to ending, across both event sources.
    var mostUrgent: (gameName: String, title: String, remaining: TimeInterval)? {
        let remote = remoteEvents
            .filter { $0.remaining > 0 && !$0.isDone }
            .map { (gameName: $0.game.displayName, title: $0.title, remaining: $0.remaining) }
        let custom = customGames.flatMap { game in
            game.events
                .filter { $0.remaining > 0 && !$0.isDone }
                .map { (gameName: game.name, title: $0.title, remaining: $0.remaining) }
        }
        return (remote + custom).min { $0.remaining < $1.remaining }
    }

    static func compactRemaining(_ remaining: TimeInterval) -> String {
        let rem = Int(remaining)
        guard rem > 0 else { return "已结束" }
        let days    = rem / 86400
        let hours   = (rem % 86400) / 3600
        let minutes = (rem % 3600) / 60
        if days  > 0 { return "\(days)天\(hours)时" }
        if hours > 0 { return "\(hours)时\(minutes)分" }
        return "\(minutes)分"
    }
}
