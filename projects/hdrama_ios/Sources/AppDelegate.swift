import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Touch the store early so an interrupted download can reconnect to its background session.
        _ = DownloadStore.shared
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = AppColors.background
        window.rootViewController = BrowserViewController()
        window.overrideUserInterfaceStyle = .dark
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        _ = DownloadStore.shared
        completionHandler()
    }
}
