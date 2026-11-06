import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — widget extension entry point.
//
// This file is the canonical @main of the DeepSeekPulseWidgets target. It must be compiled only
// into the extension, never into the app target (the app already has @main in AppDelegate.swift).

struct PulseWidget: Widget {
    /// Stable identifier. Changing it orphans existing Home Screen placements.
    static let kind = "DeepSeekPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PulseWidget.kind, provider: PulseTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DeepSeek Pulse")
        .description("Peak or off-peak pricing, the countdown to the next switch and your last saved balance.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium]
        if #available(iOSApplicationExtension 16.0, *) {
            // Lock Screen accessories need iOS 16; the app itself still runs on iOS 15.
            families.append(contentsOf: [.accessoryInline, .accessoryCircular, .accessoryRectangular])
        }
        return families
    }
}

@main
struct DeepSeekPulseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PulseWidget()
    }
}
