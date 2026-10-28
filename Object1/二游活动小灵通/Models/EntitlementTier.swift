import Foundation

enum EntitlementTier: String, Codable, Sendable {
    case free
    case premium

    var displayName: String {
        switch self {
        case .free:    return "免费版"
        case .premium: return "会员"
        }
    }

    var maxCustomGames: Int {
        switch self {
        case .free:    return 1
        case .premium: return 10
        }
    }

    var dailyAIQueries: Int {
        switch self {
        case .free:    return 2
        case .premium: return 5
        }
    }

    var extractionLimitTitle: String {
        switch self {
        case .free:    return "免费提取次数已用完"
        case .premium: return "会员提取次数已用完"
        }
    }

    var extractionLimitMessage: String {
        switch self {
        case .free:
            return "免费版今日 \(dailyAIQueries) 次提取额度已用完。升级会员后每日可提取 \(EntitlementTier.premium.dailyAIQueries) 次。"
        case .premium:
            return "会员今日 \(dailyAIQueries) 次提取额度已用完，明天会自动恢复。"
        }
    }

    func customGameLimitMessage(currentCount: Int) -> String {
        switch self {
        case .free:
            return "免费版最多只能添加 1 个自定义游戏。当前已有 \(currentCount) 个，升级会员可添加 10 个。"
        case .premium:
            return "会员最多可添加 \(maxCustomGames) 个自定义游戏。当前已有 \(currentCount) 个，请先删除不需要的游戏后再添加。"
        }
    }
}
