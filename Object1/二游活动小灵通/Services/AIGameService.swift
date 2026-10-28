import Foundation
import Observation

// Pipeline: WKWebView 提取页面正文 → 后端调用 DeepSeek → App 确认保存

@MainActor
@Observable
final class AIGameService {
    var isSearching   = false
    var isCheckingQuota = false
    var errorMessage: String? = nil
    var quotaLimitMessage: String? = nil

    // MARK: - Entry point

    func canStartExtraction(entitlementTier: EntitlementTier, appStoreTransactionJWS: String? = nil) async -> Bool {
        guard APIConfig.isAIBackendConfigured, let url = APIConfig.quotaURL else {
            errorMessage = "请先部署提取后端，并在 APIConfig.swift 填入后端地址"
            return false
        }

        isCheckingQuota = true
        errorMessage = nil
        quotaLimitMessage = nil
        defer { isCheckingQuota = false }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyBackendAuthHeaders(to: &req, appStoreTransactionJWS: appStoreTransactionJWS)
        req.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let apiError = try? JSONDecoder().decode(ExtractionErrorResponse.self, from: data)
                let message = apiError?.message ?? String(data: data, encoding: .utf8) ?? ""
                errorMessage = "提取后端错误（\(http.statusCode)）：\(message.prefix(120))"
                return false
            }

            guard let quota = try? JSONDecoder().decode(QuotaResponse.self, from: data) else {
                errorMessage = "提取次数状态异常，请重试"
                return false
            }

            if quota.canExtract {
                return true
            }

            quotaLimitMessage = quota.message ?? entitlementTier.extractionLimitMessage
            return false
        } catch {
            if let urlError = error as? URLError {
                errorMessage = "提取次数检查失败：\(urlError.localizedDescription)"
            } else {
                errorMessage = "提取次数检查失败：\(error.localizedDescription)"
            }
            return false
        }
    }

    func extractEvents(
        from text: String,
        gameName: String,
        articleURL: URL?,
        entitlementTier: EntitlementTier,
        appStoreTransactionJWS: String? = nil
    ) async -> [AIEventDraft] {
        guard APIConfig.isAIBackendConfigured, APIConfig.aiExtractorURL != nil else {
            errorMessage = "请先部署提取后端，并在 APIConfig.swift 填入后端地址"
            return []
        }

        isSearching  = true
        errorMessage = nil
        quotaLimitMessage = nil
        defer { isSearching = false }

        let drafts = await backendExtract(
            searchText: text,
            gameName: gameName,
            articleURL: articleURL,
            entitlementTier: entitlementTier,
            appStoreTransactionJWS: appStoreTransactionJWS
        )
        if drafts.isEmpty && errorMessage == nil && quotaLimitMessage == nil {
            errorMessage = "婉婉没在这页找到活动，确认一下是不是版本公告？"
        }
        return drafts
    }

    // MARK: - Backend JSON extraction

    private func backendExtract(
        searchText: String,
        gameName: String,
        articleURL: URL?,
        entitlementTier: EntitlementTier,
        appStoreTransactionJWS: String?
    ) async -> [AIEventDraft] {
        let bjTZ = TimeZone(identifier: "Asia/Shanghai")!
        var cal = Calendar.current
        cal.timeZone = bjTZ

        let df = DateFormatter()
        df.timeZone = bjTZ
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"

        let dfDateOnly = DateFormatter()
        dfDateOnly.timeZone = bjTZ
        dfDateOnly.locale = Locale(identifier: "en_US_POSIX")
        dfDateOnly.dateFormat = "yyyy-MM-dd"

        guard let url = APIConfig.aiExtractorURL,
              let bodyData = try? JSONEncoder().encode(ExtractionRequest(
                gameName: gameName,
                articleURL: articleURL?.absoluteString,
                text: searchText
              )) else {
            errorMessage = "提取后端请求构建失败"
            return []
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyBackendAuthHeaders(to: &req, appStoreTransactionJWS: appStoreTransactionJWS)
        req.httpBody        = bodyData
        req.timeoutInterval = 120

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let apiError = try? JSONDecoder().decode(ExtractionErrorResponse.self, from: data)
                if apiError?.error == "daily_limit_exceeded" {
                    quotaLimitMessage = apiError?.message ?? entitlementTier.extractionLimitMessage
                    return []
                }
                if apiError?.error == "rate_limited" {
                    errorMessage = apiError?.message ?? "请求过于频繁，请稍后再试"
                    return []
                }
                let message = apiError?.message ?? String(data: data, encoding: .utf8) ?? ""
                errorMessage = "提取后端错误（\(http.statusCode)）：\(message.prefix(120))"
                return []
            }

            guard let wrapper = try? JSONDecoder().decode(ExtractionResponse.self, from: data) else {
                errorMessage = "提取结果格式异常，请重试"
                return []
            }

            func parseDate(_ s: String) -> Date? {
                df.date(from: s) ?? dfDateOnly.date(from: s)
            }

            let todayStart = cal.startOfDay(for: Date())
            return wrapper.events.compactMap { r in
                guard let end = parseDate(r.endDate), end > todayStart else { return nil }
                let start = parseDate(r.startDate) ?? Date()
                return AIEventDraft(
                    title:     r.title,
                    startDate: start,
                    endDate:   end,
                    category:  r.category ?? "活动"
                )
            }
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    errorMessage = "请求超时：处理长公告可能需要更久，请确认后端仍在运行后重试。"
                case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                    errorMessage = "提取后端连接失败：请确认后端已启动，且手机和 Mac 在同一 Wi-Fi。"
                case .notConnectedToInternet:
                    errorMessage = "网络不可用：请检查当前网络连接。"
                default:
                    errorMessage = "网络请求失败：\(urlError.localizedDescription)"
                }
            } else {
                errorMessage = "提取失败：\(error.localizedDescription)"
            }
            return []
        }
    }

    // MARK: - Codable models

    private func applyBackendAuthHeaders(to request: inout URLRequest, appStoreTransactionJWS: String?) {
        request.setValue(InstallID.current, forHTTPHeaderField: "X-Install-ID")

        guard let appStoreTransactionJWS,
              !appStoreTransactionJWS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        request.setValue(appStoreTransactionJWS, forHTTPHeaderField: "X-App-Store-Transaction")
    }

    private struct ExtractionRequest: Encodable {
        let gameName: String
        let articleURL: String?
        let text: String
    }

    private struct ExtractionResponse: Decodable {
        let events: [RawEvent]
    }

    private struct ExtractionErrorResponse: Decodable {
        let error: String?
        let message: String?
    }

    private struct QuotaResponse: Decodable {
        let canExtract: Bool
        let message: String?
    }

    private struct RawEvent: Decodable {
        let title:     String
        let startDate: String
        let endDate:   String
        let category:  String?
    }
}
