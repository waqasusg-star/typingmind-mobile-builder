import UIKit

// DeepSeek Pulse — the icon helpers the app screens use.
//
// 1.0.9 adds `containerIcon`, which asks the bundle for the icon the SYSTEM compiled into Assets.car.
// The old code only tried `UIImage(named: "AppIcon")` and the Info.plist name; neither resolves for a
// catalog-compiled icon, so every build looked like it had no icon even when the archive contained
// AppIcon60x60@2x.png and Assets.car.
extension AppIconArtwork {

    /// The compiled Home Screen icon for this bundle, or nil when the bundle carries none.
    ///
    /// Reads the icon names the Info.plist exposes and asks UIKit for each one. This is a read of the
    /// installed asset catalog only: no file is written and nothing is downloaded.
    static func containerIcon(pointSize: CGFloat) -> UIImage? {
        for name in bundleIconNames() {
            if let image = UIImage(named: name) {
                return image
            }
        }
        return nil
    }

    /// Candidate icon names from the generated Info.plist.
    ///
    /// A catalog build writes CMSIconFiles / CFBundleIcons with per-size names; a legacy build writes a
    /// flat CFBundleIconFiles array. Both shapes are probed, longest name first so the largest icon is
    /// returned.
    static func bundleIconNames() -> [String] {
        var names: [String] = []
        let info = Bundle.main.infoDictionary ?? [:]

        func collect(_ value: Any?) {
            if let list = value as? [String] {
                names.append(contentsOf: list)
                return
            }
            if let dictionary = value as? [String: Any] {
                for key in dictionary.keys.sorted() {
                    collect(dictionary[key])
                }
            }
        }

        collect(info["CFBundleIconFiles"])
        collect(info["CFBundleIcons"])
        collect(info["CFBundleIcons~ipad"])
        if let primary = info["CFBundleIconName"] as? String, !primary.isEmpty {
            names.append(primary)
        }
        // The app-icon catalog name is always addressable as AppIcon.
        names.append("AppIcon")

        return Array(Set(names)).sorted { $0.count > $1.count }
    }
}
