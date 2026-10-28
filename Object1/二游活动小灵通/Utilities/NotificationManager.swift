import Foundation
import UserNotifications
import SwiftData

// Separate plain-NSObject delegate so the ObjC runtime can always find willPresent
// regardless of @MainActor isolation on NotificationManager.
private final class _NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    var modelContainer: ModelContainer?
    var activityService: ActivityService?

    private let _delegate = _NotifDelegate()

    private init() {
        UNUserNotificationCenter.current().delegate = _delegate
    }

    // MARK: - Permission

    func requestPermission() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if granted { rescheduleAll() }
            } catch { }
        }
    }

    // MARK: - Reschedule All

    func rescheduleAll() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized ||
                  settings.authorizationStatus == .provisional else { return }

            guard let container = modelContainer else { return }
            // activityService may be nil on first launch; custom game notifications
            // still schedule normally — they don't depend on it.
            let remoteEvents = activityService?.events ?? []

            let context = container.mainContext
            guard let prefs = try? context.fetch(FetchDescriptor<UserPreferences>()).first else { return }
            let customGames = (try? context.fetch(FetchDescriptor<CustomGame>())) ?? []

            let hour               = prefs.notificationHour
            let minute             = prefs.notificationMinute
            let dailyEnabled       = prefs.dailyReminderEnabled
            let completedIds       = Set(prefs.completedEventIds)
            let mutedIds           = Set(prefs.mutedEventIds)
            let now                = Date()

            // Cancel all previously scheduled activity notifications
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            let cancelIds = pending
                .filter { $0.identifier.hasPrefix("act_") }
                .map(\.identifier)
            if !cancelIds.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: cancelIds)
            }

            // Collect active activities in stable order (used for stagger offsets)
            struct Act {
                let uid: String
                let title: String
                let gameName: String
                let endDate: Date
            }
            var acts: [Act] = []

            for event in remoteEvents.sorted(by: { $0.id < $1.id }) {
                guard event.remaining > 0,
                      !completedIds.contains(event.id),
                      !mutedIds.contains(event.id) else { continue }
                acts.append(Act(uid: "r_\(event.id)", title: event.title,
                                gameName: event.game.displayName, endDate: event.endDate))
            }
            for game in customGames.sorted(by: { $0.id < $1.id }) {
                for event in game.events.sorted(by: { $0.id < $1.id }) {
                    guard event.remaining > 0, !event.isDone else { continue }
                    acts.append(Act(uid: "c_\(event.id)", title: event.title,
                                   gameName: game.name, endDate: event.endDate))
                }
            }
            // Sort by endDate so stagger indices reflect urgency, not game type
            acts.sort { $0.endDate < $1.endDate }

            var finalRequests: [UNNotificationRequest] = []
            var dailyRequests: [UNNotificationRequest] = []
            let cal = Calendar.current

            for (idx, act) in acts.enumerated() {
                // Stagger same-time notifications by 5 seconds per activity index
                let staggerSec = idx * 2

                // Final 6-hour reminders: fire at endDate – Nh for N in 6…1
                for mark in [6, 5, 4, 3, 2, 1] {
                    let fireDate = act.endDate.addingTimeInterval(-Double(mark) * 3600)
                    guard fireDate > now else { continue }

                    let content = UNMutableNotificationContent()
                    if let late = Self.lateNightCopy(at: fireDate, gameName: act.gameName, title: act.title,
                                                     remaining: "\(mark) 小时", variant: idx + mark, calendar: cal) {
                        content.title = late.title
                        content.body = late.body
                    } else {
                        content.title = "婉婉急报：活动快结束了"
                        content.body = "《\(act.gameName)》「\(act.title)」还有 \(mark) 小时结束，老大抓紧收尾！"
                    }
                    content.sound = .default

                    let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    finalRequests.append(
                        UNNotificationRequest(identifier: "act_final_\(act.uid)_\(mark)",
                                             content: content, trigger: trigger)
                    )
                }

                // Daily reminders: only for activities ending within 7 days
                guard dailyEnabled else { continue }
                guard act.endDate.timeIntervalSinceNow <= 7 * 24 * 3600 else { continue }
                for dayOffset in 0...7 {
                    guard let dayStart = cal.date(byAdding: .day, value: dayOffset,
                                                  to: cal.startOfDay(for: now)) else { continue }
                    var comps = cal.dateComponents([.year, .month, .day], from: dayStart)
                    comps.hour   = hour
                    comps.minute = minute
                    comps.second = staggerSec   // stagger prevents same-second delivery

                    guard let fireDate = cal.date(from: comps) else { continue }
                    guard fireDate > now, fireDate < act.endDate else { continue }

                    // Remaining time at the (non-staggered) notification hour
                    let baseFireDate = fireDate.addingTimeInterval(-Double(staggerSec))
                    let remainSecs = max(0, Int(act.endDate.timeIntervalSince(baseFireDate)))
                    let days  = remainSecs / 86400
                    let hours = (remainSecs % 86400) / 3600
                    let timeText = days > 0 ? "\(days) 天 \(hours) 小时" : "\(hours) 小时"

                    let content = UNMutableNotificationContent()
                    if let late = Self.lateNightCopy(at: baseFireDate, gameName: act.gameName, title: act.title,
                                                     remaining: timeText, variant: idx + dayOffset, calendar: cal) {
                        content.title = late.title
                        content.body = late.body
                    } else {
                        content.title = "婉婉提醒：活动快到期了"
                        content.body = "《\(act.gameName)》「\(act.title)」还有 \(timeText)结束，婉婉帮你记着呢。"
                    }
                    content.sound = .default

                    let trigComps = cal.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second], from: fireDate
                    )
                    let trigger = UNCalendarNotificationTrigger(dateMatching: trigComps, repeats: false)

                    let dateTag = String(format: "%04d%02d%02d",
                                        comps.year ?? 0, comps.month ?? 1, comps.day ?? 1)
                    dailyRequests.append(
                        UNNotificationRequest(identifier: "act_daily_\(act.uid)_\(dateTag)",
                                             content: content, trigger: trigger)
                    )
                }
            }

            // Merge and sort all requests by trigger date so the 64-slot iOS limit
            // always keeps the most upcoming notifications regardless of type.
            // (If final requests filled all 64 slots first, daily reminders would never fire.)
            let allRequests = (finalRequests + dailyRequests).sorted {
                (self.triggerDate(of: $0) ?? .distantFuture) <
                (self.triggerDate(of: $1) ?? .distantFuture)
            }

            for request in allRequests.prefix(64) {
                try? await UNUserNotificationCenter.current().add(request)
            }
        }
    }

    // MARK: - Cancel single activity's notifications

    func cancelNotifications(for activityId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter {
                $0.identifier.contains("_r_\(activityId)_") ||
                $0.identifier.contains("_c_\(activityId)_")
            }.map(\.identifier)
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func cancelNotifications(forCustomActivityIds activityIds: [String]) {
        let tokens = activityIds.map { "_c_\($0)_" }
        guard !tokens.isEmpty else { return }

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { request in
                tokens.contains { request.identifier.contains($0) }
            }.map(\.identifier)
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // Cancel only daily reminders (act_daily_*), leaving urgent final reminders untouched.
    func cancelDailyNotifications() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix("act_daily_") }
                .map(\.identifier)
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Badge

    func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func clearBadge() {
        Task {
            try? await UNUserNotificationCenter.current().setBadgeCount(0)
        }
    }

    // MARK: - Test

    func scheduleTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "婉婉试铃"
        content.body = "婉婉能准时提醒你啦，这条通知说明推送正常。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "act_test_\(UInt32.random(in: 1...UInt32.max))",
                content: content, trigger: trigger
            )
        )
    }

    // MARK: - Private helpers

    // Reminders that land between 23:00 and 5:00 drop the formal tone and nudge the player to
    // finish up and go to sleep. `variant` rotates the lines so a busy night doesn't repeat one.
    private static func lateNightCopy(
        at date: Date, gameName: String, title: String, remaining: String, variant: Int, calendar: Calendar
    ) -> (title: String, body: String)? {
        let hour = calendar.component(.hour, from: date)
        guard hour >= 23 || hour < 5 else { return nil }
        let lines: [(String, String)] = [
            ("老大太晚啦", "《\(gameName)》「\(title)」还剩 \(remaining)，清完这波体力赶紧睡吧！"),
            ("老大，今晚的还没做", "《\(gameName)》「\(title)」今晚还没做，还剩 \(remaining)，做完就去睡！"),
            ("夜深啦老大", "《\(gameName)》「\(title)」还剩 \(remaining)就结束了，速战速决，别熬太晚哦。"),
        ]
        let line = lines[abs(variant) % lines.count]
        return (line.0, line.1)
    }

    private func triggerDate(of request: UNNotificationRequest) -> Date? {
        switch request.trigger {
        case let t as UNCalendarNotificationTrigger:     return t.nextTriggerDate()
        case let t as UNTimeIntervalNotificationTrigger: return t.nextTriggerDate()
        default:                                          return nil
        }
    }
}
