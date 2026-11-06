// Retired in 1.0.3 (build 4).
//
// WidgetPlanner now lives in Shared/WidgetPlannerCore.swift, because the DeepSeekPulseWidgets
// extension compiles WidgetSources + Shared + Sources/RequestPolicy.swift and cannot see Sources/.
// This file declares no symbols.
//
// The shared copy is named *Core.swift because Swift rejects two files with the same basename inside
// one target ("Filename WidgetPlanner.swift used twice"), and Sources/ plus Shared/ are both part of
// the app target.
