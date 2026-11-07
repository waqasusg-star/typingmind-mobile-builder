import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let navigation = UINavigationController(rootViewController: DashboardViewController())
        navigation.navigationBar.prefersLargeTitles = true
        window.rootViewController = navigation
        self.window = window

        // 1.0.7: the window starts in the saved theme instead of a hard-coded dark one, and the
        // navigation bar is styled from the same palette. SettingsStore caches the appearance, so this
        // is a read, not a Keychain or network call.
        let appearance = AppAppearance.current
        window.backgroundColor = appearance.background
        window.overrideUserInterfaceStyle = appearance.interfaceStyle
        AppThemeRefresh.styleNavigationBar(navigation.navigationBar, appearance: appearance)

        window.makeKeyAndVisible()
        return true
    }

    /// The widget deep link opens the dashboard and asks it to refresh the balance.
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard WidgetPolicy.isWidgetDeepLink(url) else { return false }
        guard let navigation = window?.rootViewController as? UINavigationController,
              let dashboard = navigation.viewControllers.first as? DashboardViewController else { return false }
        navigation.popToRootViewController(animated: true)
        dashboard.refreshIfAskedByWidget(url)
        return true
    }
}
