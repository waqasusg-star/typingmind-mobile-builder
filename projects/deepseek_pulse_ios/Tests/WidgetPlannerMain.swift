// Platform-neutral widget planner checks.
//
// This file is compiled by the pipeline's `foundation_policy` profile as a second harness next to
// Tests/PolicyTests.swift, together with Sources/RequestPolicy.swift and Sources/WidgetPlanner.swift.
// It also provides a process entry point for the case where the profile links all test sources.

#if !DEEPSEEK_POLICY_MAIN
import Foundation

@main
struct WidgetPlannerTestMain {
    static func main() {
        do {
            try widgetPlannerChecks()
            print("widget planner suite finished")
        } catch {
            print("widget planner suite failed: \(error)")
            exit(1)
        }
    }
}
#endif
