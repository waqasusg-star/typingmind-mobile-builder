import Foundation
import WidgetKit
import SwiftUI

// DeepSeek Pulse — widget extension entry point.
//
// This file is the canonical @main of the DeepSeekPulseWidgets target. It must be compiled only
// into the extension, never into the app target (the app already has @main in AppDelegate.swift).
//
// The extension deployment target is iOS 15, so Lock Screen accessory families are declared only
// behind an iOS 16 availability check. The accessory views themselves carry the same annotation.

struct PulseWidget: Widget {
    /// Stable identifier. Changing it orphans existing Home Screen placements.
    static let kind = "DeepSeekPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PulseWidget.kind, provider: PulseTimelineProvider()) { entry in
            WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("DeepSeek Pulse")
        .description("Peak or off-peak pricing, the countdown, your available balance and a refresh shortcut. Ten designs and sixteen themes in Widget Studio.")
        .supportedFamilies(PulseWidget.supportedFamilies())
    }

    /// Small and medium always; accessory families only where the SDK can provide them.
    static func supportedFamilies() -> [WidgetFamily] {
        var families: [WidgetFamily] = [.systemSmall, .systemMedium]
        if #available(iOSApplicationExtension 16.0, *) {
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
