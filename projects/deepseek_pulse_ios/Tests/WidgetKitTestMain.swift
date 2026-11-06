// Entry point for the widgetkit_v1 Foundation widget suite.
//
// Compiled with Sources/RequestPolicy.swift, ALL Shared/*.swift, Tests/WidgetKitTests.swift and
// this file, as a separate target from the existing foundation_policy harness.
// It calls only widgetKitChecks(), which is defined in Tests/WidgetKitTests.swift, so the two
// harnesses never depend on each other's symbols.

import Foundation

@main
struct WidgetKitTestMain {
    static func main() {
        do {
            try widgetKitChecks()
            print("widget kit suite finished")
        } catch {
            print("widget kit suite failed: " + String(describing: error))
            exit(1)
        }
    }
}
