// Removed in 1.0.3 (build 4).
//
// WidgetPlanner now lives in Shared/WidgetPlanner.swift, because the DeepSeekPulseWidgets
// extension compiles WidgetSources + Shared + Sources/RequestPolicy.swift and cannot see Sources/.
// This file declares no symbols, so WidgetPlanner is defined exactly once and both the app and the
// extension compile the same implementation.
