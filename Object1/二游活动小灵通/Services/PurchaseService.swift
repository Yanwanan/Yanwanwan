import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseService {
    static let premiumProductID = "ailesson.path.Object1.premium.monthly"
    static let lifetimeProductID = "ailesson.path.Object1.premium.lifetime"
    private static let premiumProductIDs = [premiumProductID, lifetimeProductID]

    var tier: EntitlementTier = .free
    var products: [Product] = []
    var isLoadingProducts = false
    var errorMessage: String? = nil

    private var storeKitTier: EntitlementTier = .free
    private var didStart = false
    private var transactionUpdatesTask: Task<Void, Never>?

    var premiumProduct: Product? {
        products.first { $0.id == Self.premiumProductID }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeProductID }
    }

    var isPremium: Bool { tier == .premium }

    func start() {
        guard !didStart else { return }
        didStart = true

        transactionUpdatesTask = Task {
            for await result in Transaction.updates {
                guard let transaction = try? checkVerified(result) else { continue }
                await refreshEntitlements()
                await transaction.finish()
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        errorMessage = nil
        defer { isLoadingProducts = false }

        do {
            products = try await Product.products(for: Self.premiumProductIDs)
                .sorted { lhs, rhs in
                    let lhsIndex = Self.premiumProductIDs.firstIndex(of: lhs.id) ?? .max
                    let rhsIndex = Self.premiumProductIDs.firstIndex(of: rhs.id) ?? .max
                    if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                    return lhs.displayName < rhs.displayName
                }
        } catch {
            errorMessage = "会员商品加载失败：请检查网络或稍后再试"
        }
    }

    @discardableResult
    func purchasePremium() async -> Bool {
        if premiumProduct == nil {
            await loadProducts()
        }

        guard let product = premiumProduct else {
            errorMessage = "会员商品暂不可用，请稍后再试"
            return false
        }

        return await purchase(product)
    }

    @discardableResult
    func purchaseLifetime() async -> Bool {
        if lifetimeProduct == nil {
            await loadProducts()
        }

        guard let product = lifetimeProduct else {
            errorMessage = "一休尼会员商品暂不可用，请稍后再试"
            return false
        }

        return await purchase(product)
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshEntitlements()
                await transaction.finish()
                return storeKitTier == .premium
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "购买失败：请确认网络和 App Store 账户状态后重试"
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "恢复购买失败：请确认网络和 App Store 账户状态后重试"
        }
    }

    func refreshEntitlements() async {
        var hasPremium = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard Self.premiumProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            hasPremium = true
        }

        storeKitTier = hasPremium ? .premium : .free
        applyEffectiveTier()
    }

    func currentEntitlementJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard Self.premiumProductIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            return result.jwsRepresentation
        }

        return nil
    }

    private func applyEffectiveTier() {
        tier = storeKitTier
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let signedType):
            return signedType
        }
    }

    private enum StoreError: Error {
        case failedVerification
    }
}
