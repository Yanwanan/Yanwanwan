import SwiftUI
import SwiftData

@main
struct Object1App: App {
    @State private var activityService = ActivityService()
    @State private var purchaseService = PurchaseService()

    init() {
        applyAppearance()
    }

    private func applyAppearance() {
        // Tab bar
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Color.hoyoBg)
        tabAppearance.stackedLayoutAppearance.selected.iconColor   = UIColor(Color.hoyoPink)
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.hoyoPink)]
        UITabBar.appearance().standardAppearance  = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Navigation bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Color.hoyoBg)
        navAppearance.titleTextAttributes      = [.foregroundColor: UIColor(Color.hoyoDark)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.hoyoDark)]
        UINavigationBar.appearance().standardAppearance   = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor(Color.hoyoPink)
    }

    // Uses CloudKit when iCloud entitlement is available, falls back to local store otherwise.
    // If persistent storage fails, keep the on-disk data intact and run in memory.
    private let modelContainer: ModelContainer = {
        let schema = Schema([UserPreferences.self, CustomGame.self, CustomEvent.self])

        // Try iCloud-backed store first (requires iCloud + CloudKit capability in Xcode)
        // groupContainer is pinned to .none: the App Group is only used to share the
        // lightweight widget snapshot (SharedWidgetData), not the SwiftData store itself.
        let cloudConfig = ModelConfiguration(schema: schema, groupContainer: .none, cloudKitDatabase: .automatic)
        if let container = try? ModelContainer(for: schema, configurations: [cloudConfig]) {
            return container
        }

        // Fall back to local-only store (no iCloud entitlement or CloudKit unavailable)
        func makeLocal() throws -> ModelContainer {
            let config = ModelConfiguration(schema: schema, groupContainer: .none)
            return try ModelContainer(for: schema, configurations: [config])
        }

        func makeInMemory() throws -> ModelContainer {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, groupContainer: .none)
            return try ModelContainer(for: schema, configurations: [config])
        }

        do {
            return try makeLocal()
        } catch {
            if let fallback = try? makeInMemory() {
                return fallback
            }
            fatalError("Unable to create SwiftData store: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        // Keep this closure free of state. SwiftUI may re-run it on its async render thread
        // while an animation is playing, and a main-actor closure traps there. All changing
        // state lives in AppRootView, whose body SwiftUI always evaluates on the main thread.
        WindowGroup {
            AppRootView(
                modelContainer: modelContainer,
                activityService: activityService,
                purchaseService: purchaseService
            )
        }
    }
}

// Privacy consent, the splash screen and the app itself, plus foreground housekeeping.
private struct AppRootView: View {
    let modelContainer: ModelContainer
    let activityService: ActivityService
    let purchaseService: PurchaseService

    @State private var showSplash = true
    @AppStorage(PrivacyConsent.acceptedVersionKey) private var acceptedPrivacyVersion = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if acceptedPrivacyVersion == ComplianceConfig.privacyVersion {
                ContentView()
                    .modelContainer(modelContainer)
                    .environment(activityService)
                    .environment(purchaseService)
                    .transition(.opacity)
            } else {
                PrivacyConsentView {
                    acceptedPrivacyVersion = ComplianceConfig.privacyVersion
                    startConsentedServices()
                }
                .transition(.opacity)
            }

            if showSplash && acceptedPrivacyVersion == ComplianceConfig.privacyVersion {
                SplashView { showSplash = false }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.35), value: showSplash)
        .background(FullScreenWindowRequest())
        .onAppear {
            NotificationManager.shared.modelContainer = modelContainer
            NotificationManager.shared.activityService = activityService
            if acceptedPrivacyVersion == ComplianceConfig.privacyVersion {
                startConsentedServices()
            } else {
                showSplash = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                NotificationManager.shared.activityService = activityService
                NotificationManager.shared.rescheduleAll()
                NotificationManager.shared.clearDeliveredNotifications()
                NotificationManager.shared.clearBadge()
            }
        }
    }

    private func startConsentedServices() {
        NotificationManager.shared.requestPermission()
        purchaseService.start()
    }
}

// iPad windowed multitasking opens every app as a window and ignores UIRequiresFullScreen.
// A minimum size as large as the screen leaves the system no smaller window to offer.
private struct FullScreenWindowRequest: UIViewRepresentable {
    func makeUIView(context: Context) -> RequestView {
        let view = RequestView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: RequestView, context: Context) {}

    final class RequestView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard traitCollection.userInterfaceIdiom == .pad,
                  let scene = window?.windowScene else { return }
            // iPad runs landscape only, so the long side is the width.
            let screen = scene.screen.bounds.size
            let size = CGSize(width: max(screen.width, screen.height), height: min(screen.width, screen.height))
            scene.sizeRestrictions?.minimumSize = size
            scene.sizeRestrictions?.maximumSize = size
        }
    }
}
