// Retired in 1.0.3 (build 4).
//
// The real WidgetPlanner implementation lives in Shared/WidgetPlanner.swift, compiled into both the
// app target and the DeepSeekPulseWidgets extension. This marker file exists only to keep the
// original path documented and declares no symbols.
//
// Why the old file was replaced: Swift rejects two files with the same basename inside one target
// ("Filename WidgetPlanner.swift used twice"), even when one of them declares nothing. Sources/
// and Shared/ are both part of the app target, so the duplicate name broke the archive step.
