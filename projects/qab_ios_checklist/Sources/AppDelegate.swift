import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let store = ChecklistStore()
        let window = UIWindow(frame: UIScreen.main.bounds)
        let root = ChecklistViewController(store: store)
        window.rootViewController = UINavigationController(rootViewController: root)
        AppDelegate.apply(theme: store.themeChoice(), to: window)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    static func apply(theme: ThemeChoice, to window: UIWindow) {
        switch theme {
        case .system:
            window.overrideUserInterfaceStyle = .unspecified
        case .light:
            window.overrideUserInterfaceStyle = .light
        case .dark:
            window.overrideUserInterfaceStyle = .dark
        }
    }
}
