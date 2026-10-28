import SwiftUI
import StoreKit

struct PremiumView: View {
    @Environment(PurchaseService.self) private var purchaseService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRestoring = false
    @State private var purchasingProductID: String? = nil
    @State private var isEligibleForIntroOffer = false
    @State private var showPurchaseCelebration = false

    private let benefitColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.hoyoBg.ignoresSafeArea()
                backgroundPattern

                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            header
                            purchaseSection
                            benefitSection
                            planComparison
                            usageSection

                            Spacer(minLength: 16)

                            purchaseTermsNotice
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: max(0, proxy.size.height - 46), alignment: .top)
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                    }
                }

                if showPurchaseCelebration {
                    PurchaseCelebrationView()
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.75).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .navigationTitle("会员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .fontDesign(.rounded)
        }
        .task {
            await purchaseService.loadProducts()
            await purchaseService.refreshEntitlements()
            await refreshIntroOfferEligibility()
        }
    }

    private var backgroundPattern: some View {
        Canvas { ctx, size in
            for row in stride(from: 0, through: size.height, by: 24) {
                for col in stride(from: 0, through: size.width, by: 24) {
                    let rect = CGRect(x: col - 1.2, y: row - 1.2, width: 2.4, height: 2.4)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color.hoyoPink.opacity(0.10)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Label(purchaseService.isPremium ? "会员已启用" : "会员方案", systemImage: "crown.fill")
                    .font(.caption)
                    .fontWeight(.black)
                    .foregroundStyle(Color.hoyoNavy)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.hoyoYellow, in: Capsule())

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(Color.hoyoYellow)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(purchaseService.isPremium ? "更多活动已经交给二游活动小灵通盯着" : "把更多游戏交给二游活动小灵通盯着")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text("自定义游戏和公告提取额度一起升级，多款二游也能集中整理。")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                metricPill(title: "自定义游戏", value: "10 个", icon: "gamecontroller.fill")
                metricPill(title: "AI 提取", value: "5 次/日", icon: "sparkles")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.hoyoNavy, Color(hex: "4A72C4"), Color.hoyoMint],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.hoyoNavy.opacity(0.20), radius: 18, x: 0, y: 8)
    }

    private func metricPill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Color.hoyoYellow)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white.opacity(0.70))
                Text(value)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var benefitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "sparkles", title: "会员权益")

            LazyVGrid(columns: benefitColumns, spacing: 10) {
                benefitCard(
                    icon: "gamecontroller.fill",
                    title: "多游戏盯梢",
                    value: "10 个",
                    detail: "自定义游戏上限",
                    tint: Color.hoyoPink
                )
                benefitCard(
                    icon: "doc.text.magnifyingglass",
                    title: "公告提取",
                    value: "5 次/日",
                    detail: "每日 AI 整理额度",
                    tint: Color.hoyoMint
                )
                benefitCard(
                    icon: "checklist",
                    title: "活动清单",
                    value: "批量生成",
                    detail: "公告链接变待办",
                    tint: Color(hex: "4A72C4")
                )
                benefitCard(
                    icon: "arrow.clockwise",
                    title: "每日恢复",
                    value: "自动刷新",
                    detail: "额度次日继续用",
                    tint: Color.hoyoYellow
                )
            }
        }
    }

    private func benefitCard(icon: String, title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.hoyoNavy.opacity(0.52))
                Text(value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color.hoyoNavy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(detail)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hoyoNavy.opacity(0.42))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(14)
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(tint.opacity(0.24), lineWidth: 1.3)
        )
        .shadow(color: Color.hoyoNavy.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private var planComparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "tablecells.fill", title: "额度对比")

            VStack(spacing: 0) {
                comparisonHeader
                comparisonDivider
                comparisonRow(title: "自定义游戏", free: "1 个", premium: "10 个")
                comparisonDivider
                comparisonRow(title: "AI 提取", free: "2 次/日", premium: "5 次/日")
                comparisonDivider
                comparisonRow(title: "推荐场景", free: "轻量使用", premium: "多游常驻")
            }
            .padding(14)
            .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.3)
            )
            .shadow(color: Color.hoyoNavy.opacity(0.06), radius: 10, x: 0, y: 3)
        }
    }

    private var comparisonHeader: some View {
        HStack(spacing: 10) {
            Text("项目")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("免费版")
                .frame(width: 72)
            Text("会员")
                .frame(width: 72)
        }
        .font(.caption)
        .fontWeight(.black)
        .foregroundStyle(Color.hoyoNavy.opacity(0.45))
        .padding(.bottom, 8)
    }

    private var comparisonDivider: some View {
        Rectangle()
            .fill(Color.hoyoNavy.opacity(0.06))
            .frame(height: 1)
    }

    private func comparisonRow(title: String, free: String, premium: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(free)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.hoyoNavy.opacity(0.48))
                .frame(width: 72)
                .padding(.vertical, 7)
                .background(Color.hoyoNavy.opacity(0.06), in: Capsule())

            Text(premium)
                .font(.caption)
                .fontWeight(.black)
                .foregroundStyle(.white)
                .frame(width: 72)
                .padding(.vertical, 7)
                .background(Color.hoyoPink, in: Capsule())
        }
        .padding(.vertical, 10)
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "wand.and.stars", title: "适合这样用")

            VStack(spacing: 0) {
                usageRow(icon: "link.badge.plus", title: "版本公告一贴整理", detail: "复制 B站公告链接，用内置浏览器提取活动草稿。")
                comparisonDivider
                usageRow(icon: "bell.badge.fill", title: "多款游戏集中盯", detail: "活动、卡池和限时任务统一进入清单。")
            }
            .padding(.horizontal, 14)
            .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.3)
            )
            .shadow(color: Color.hoyoNavy.opacity(0.06), radius: 10, x: 0, y: 3)
        }
    }

    private var purchaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(icon: "creditcard.fill", title: "选择方案")

            if purchaseService.isPremium {
                premiumStatus
            } else if purchaseService.isLoadingProducts && purchaseService.products.isEmpty {
                loadingProductStatus
            } else if purchaseService.premiumProduct != nil || purchaseService.lifetimeProduct != nil {
                purchaseOptions
            } else {
                unavailableProductStatus
            }

            Button {
                Task {
                    isRestoring = true
                    await purchaseService.restorePurchases()
                    isRestoring = false
                    if purchaseService.isPremium { celebratePurchase() }
                }
            } label: {
                HStack(spacing: 6) {
                    if isRestoring {
                        ProgressView()
                            .scaleEffect(0.78)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                        Text("恢复购买")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.hoyoPink)
            .disabled(isRestoring || purchasingProductID != nil)

            if let message = purchaseService.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var purchaseTermsNotice: some View {
        VStack(spacing: 7) {
            Text("购买由 App Store 处理，可在系统账户中管理或取消。月度会员会自动续订，除非在当前周期结束前至少 24 小时取消。")
                .multilineTextAlignment(.center)

            if let privacyURL = APIConfig.privacyPolicyURL,
               let termsURL = APIConfig.termsOfServiceURL {
                HStack(spacing: 6) {
                    Link("隐私政策", destination: privacyURL)
                    Text("·")
                    Link("服务条款", destination: termsURL)
                }
                .foregroundStyle(Color.hoyoPink)
            }
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(Color.hoyoNavy.opacity(0.38))
        .frame(maxWidth: .infinity)
    }

    private var purchaseOptions: some View {
        VStack(spacing: 10) {
            if let product = purchaseService.premiumProduct {
                purchaseOptionButton(
                    product: product,
                    title: introductoryOfferText(for: product) ?? "月度会员",
                    subtitle: introductoryOfferText(for: product) == nil
                        ? "\(product.displayPrice)/月 · 灵活体验"
                        : "之后 \(product.displayPrice)/月，可随时取消",
                    icon: "calendar.badge.clock",
                    tint: Color.hoyoPink,
                    isPrimary: true
                )
            }

            if let product = purchaseService.lifetimeProduct {
                purchaseOptionButton(
                    product: product,
                    title: "一休尼会员",
                    subtitle: "\(product.displayPrice) · 一次买断长期使用",
                    icon: "infinity",
                    tint: Color.hoyoNavy,
                    isPrimary: false
                )
            }
        }
    }

    private var premiumStatus: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.hoyoMint, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text("当前已是会员")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.hoyoNavy)
                Text("10 个自定义游戏和 5 次每日提取已生效")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hoyoNavy.opacity(0.46))
            }

            Spacer()
        }
        .padding(14)
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.hoyoMint.opacity(0.30), lineWidth: 1.3)
        )
    }

    private var loadingProductStatus: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.hoyoPink)
            Text("正在加载会员商品")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)
            Spacer()
        }
        .padding(15)
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.3)
        )
    }

    private var unavailableProductStatus: some View {
        VStack(spacing: 10) {
            Text("会员商品暂不可用")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)
            Text("没加载到 App Store 商品时不会显示支付按钮。请确认商品 ID 已配置，或重新加载。")
                .font(.caption)
                .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await purchaseService.loadProducts()
                    await refreshIntroOfferEligibility()
                }
            } label: {
                HStack(spacing: 7) {
                    if purchaseService.isLoadingProducts {
                        ProgressView()
                            .scaleEffect(0.78)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .black))
                        Text("重新加载商品")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.hoyoPink, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(purchaseService.isLoadingProducts)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.hoyoNavy.opacity(0.10), lineWidth: 1.3)
        )
    }

    private func purchaseOptionButton(
        product: Product,
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isPrimary: Bool
    ) -> some View {
        Button {
            Task {
                purchasingProductID = product.id
                let purchased = await purchaseService.purchase(product)
                purchasingProductID = nil
                if purchased { celebratePurchase() }
            }
        } label: {
            purchaseOptionLabel(
                product: product,
                title: title,
                subtitle: subtitle,
                icon: icon,
                tint: tint,
                isPrimary: isPrimary
            )
        }
        .buttonStyle(.plain)
        .disabled(purchasingProductID != nil)
    }

    private func purchaseOptionLabel(
        product: Product,
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        isPrimary: Bool
    ) -> some View {
        let isPurchasing = purchasingProductID == product.id

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(isPrimary ? Color.hoyoNavy : .white)
                    .frame(width: 40, height: 40)
                    .background(isPrimary ? Color.hoyoYellow : tint, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    if isPurchasing {
                        Text("正在处理购买")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                        Text("请在 App Store 弹窗中确认")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .opacity(0.78)
                    } else {
                        Text(title)
                            .font(.system(size: 16, weight: .black, design: .rounded))
                        Text(subtitle)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .opacity(0.78)
                    }
                }

                Spacer()

                if isPurchasing {
                    ProgressView()
                        .tint(isPrimary ? .white : tint)
                } else {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 14, weight: .black))
                }
            }

            HStack(spacing: 7) {
                Image(systemName: isPurchasing ? "hourglass" : "creditcard.fill")
                    .font(.system(size: 12, weight: .black))
                Text(isPurchasing ? "正在拉起 App Store 支付" : purchaseCTATitle(for: product, isPrimary: isPrimary))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(isPrimary ? Color.hoyoNavy : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isPrimary ? Color.white.opacity(0.92) : tint, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isPrimary ? Color.white.opacity(0.24) : tint.opacity(0.30), lineWidth: 1.1)
            )
        }
        .foregroundStyle(isPrimary ? Color.white : Color.hoyoNavy)
        .padding(15)
        .background(purchaseOptionBackground(tint: tint, isPrimary: isPrimary), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isPrimary ? Color.white.opacity(0.18) : tint.opacity(0.24), lineWidth: 1.3)
        )
        .shadow(color: tint.opacity(isPrimary ? 0.34 : 0.10), radius: isPrimary ? 16 : 10, x: 0, y: isPrimary ? 6 : 3)
    }

    private func purchaseCTATitle(for product: Product, isPrimary: Bool) -> String {
        if introductoryOfferText(for: product) != nil {
            return "立即开通试用"
        }

        return isPrimary ? "立即支付 \(product.displayPrice)" : "购买 \(product.displayPrice)"
    }

    private func celebratePurchase() {
        guard !showPurchaseCelebration else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.68)) {
            showPurchaseCelebration = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1050))
            dismiss()
        }
    }

    private func purchaseOptionBackground(tint: Color, isPrimary: Bool) -> AnyShapeStyle {
        if isPrimary {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [tint, Color(hex: "E94B9C")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color.hoyoCardBg)
    }

    private func refreshIntroOfferEligibility() async {
        guard let product = purchaseService.premiumProduct,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else {
            isEligibleForIntroOffer = false
            return
        }

        isEligibleForIntroOffer = await product.subscription?.isEligibleForIntroOffer ?? false
    }

    private func introductoryOfferText(for product: Product) -> String? {
        guard isEligibleForIntroOffer,
              let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial
        else { return nil }

        return "免费试用 \(subscriptionPeriodText(offer.period))"
    }

    private func subscriptionPeriodText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:
            return "\(period.value) 天"
        case .week:
            return "\(period.value) 周"
        case .month:
            return "\(period.value) 个月"
        case .year:
            return "\(period.value) 年"
        @unknown default:
            return "\(period.value) 个周期"
        }
    }

    private func sectionLabel(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.hoyoPink, in: RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)
        }
        .padding(.horizontal, 2)
    }

    private func usageRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Color.hoyoPink)
                .frame(width: 32, height: 32)
                .background(Color.hoyoPink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color.hoyoNavy)
                Text(detail)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hoyoNavy.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
    }
}

private struct PurchaseCelebrationView: View {
    @State private var glow = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.hoyoYellow.opacity(0.22))
                    .frame(width: glow ? 118 : 82, height: glow ? 118 : 82)
                Image(systemName: "crown.fill")
                    .font(.system(size: 42, weight: .black))
                    .foregroundStyle(Color.hoyoYellow)
                    .symbolEffect(.bounce, value: glow)
            }
            Text("会员已启用")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Color.hoyoNavy)
            Text("更多活动已经交给二游活动小灵通盯着")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.hoyoNavy.opacity(0.52))
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.hoyoYellow, lineWidth: 2.5))
        .shadow(color: Color.hoyoYellow.opacity(0.34), radius: 22, y: 8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) { glow = true }
        }
    }
}
