import UIKit

// DeepSeek Pulse — the Settings save path.
//
// Split out of SettingsViewController in 1.0.7 so the form construction and the validated write are
// separate, readable units. Everything here runs on the main thread from the Save button; each guard
// aborts the whole save rather than writing a half-valid configuration.
//
// The key rule: the key is stored through SettingsStore.replaceAPIKey, which writes non-destructively
// and reads the value back. A Keychain that refuses the write leaves the previous key, the cached
// balance and the widget snapshot untouched, and the user is told so instead of seeing a success.

extension SettingsViewController {

    @objc func saveTapped() {
        view.endEditing(true)
        let store = SettingsStore.shared

        guard let intervals = validatedIntervals() else { return }

        let coverageStart = (coverageStartField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let coverageEnd = (coverageEndField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard validatedCoverage(start: coverageStart, end: coverageEnd) else { return }

        for key in holidays where PricingSchedule.date(fromDayKey: key) == nil {
            alert("Check the holiday dates", key + " is not a yyyy-MM-dd date.")
            return
        }

        guard let models = validatedModels(from: store) else { return }

        let official = RateSeeds.schedule
        let sortedNew = intervals.sorted { $0.startMinuteUTC < $1.startMinuteUTC }
        let isCustom = scheduleSwitch.isOn != official.discountsEnabled
            || peakDays != official.peakWeekdays
            || sortedNew != official.sortedIntervals

        let existing = store.schedule.holidays
        let newStart: String? = coverageStart.isEmpty ? nil : coverageStart
        let newEnd: String? = coverageEnd.isEmpty ? nil : coverageEnd
        var verifiedAsOf = existing.verifiedAsOf
        if newStart != existing.coverageStart || newEnd != existing.coverageEnd {
            verifiedAsOf = PricingSchedule.dayKey(Date())
        }
        let calendar = HolidayCalendar(dates: holidays,
                                       coverageStart: newStart,
                                       coverageEnd: newEnd,
                                       verifiedAsOf: verifiedAsOf,
                                       source: existing.source)

        let updatedSchedule = PricingSchedule(peakWeekdays: peakDays.isEmpty ? official.peakWeekdays : peakDays,
                                              intervals: sortedNew,
                                              holidays: calendar,
                                              discountsEnabled: scheduleSwitch.isOn,
                                              sourceURL: official.sourceURL,
                                              verifiedAsOf: official.verifiedAsOf)

        let ratesAreCustom = models != RateSeeds.models

        // The key is written before anything else, and a failure stops the save so the screen can
        // never report success for a key that is not in the Keychain.
        let key = keyField.text ?? ""
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch store.replaceAPIKey(key) {
            case .storeFailed:
                alert("Keychain error", "The API key could not be stored in the iOS Keychain. Your previous key and cached balance are unchanged. Try again.")
                return
            case .saved:
                break
            }
        }

        store.saveSchedule(updatedSchedule, isCustom: isCustom)
        store.saveModels(models, isCustom: ratesAreCustom)

        // Rewrite the widget snapshot so the Home Screen follows the schedule, the rate change and the
        // key state immediately; iOS still decides when the timeline is actually redrawn.
        WidgetBridge.refresh(store: store)

        NotificationCenter.default.post(name: .deepSeekSettingsChanged, object: nil)
        onSaved?()
        dismiss(animated: true)
    }

    /// Peak windows as typed, or nil when the screen has already shown what is wrong.
    private func validatedIntervals() -> [PeakInterval]? {
        var intervals: [PeakInterval] = []
        for index in 0..<windowFields.count {
            let startText = (windowFields[index][0].text ?? "").trimmingCharacters(in: .whitespaces)
            let endText = (windowFields[index][1].text ?? "").trimmingCharacters(in: .whitespaces)
            if startText.isEmpty && endText.isEmpty { continue }
            guard let start = parseMinutePublic(startText), let end = parseMinutePublic(endText) else {
                alert("Check window " + String(index + 1), "Enter both edges as HH:MM in 24-hour UTC, for example 01:00 and 04:00.")
                return nil
            }
            guard start < end else {
                alert("Check window " + String(index + 1), "The start must be earlier than the end; a window cannot cross midnight.")
                return nil
            }
            intervals.append(PeakInterval(startMinuteUTC: start, endMinuteUTC: end))
        }
        if scheduleSwitch.isOn && intervals.isEmpty {
            alert("Check the schedule", "Add at least one peak window, or switch off-peak discounts off.")
            return nil
        }
        if scheduleSwitch.isOn && peakDays.isEmpty {
            alert("Check the schedule", "Select at least one peak weekday, or switch off-peak discounts off.")
            return nil
        }
        return intervals
    }

    private func validatedCoverage(start: String, end: String) -> Bool {
        guard !start.isEmpty || !end.isEmpty else { return true }
        guard PricingSchedule.date(fromDayKey: start) != nil,
              PricingSchedule.date(fromDayKey: end) != nil else {
            alert("Check the holiday range", "Enter both range ends as yyyy-MM-dd, for example 2026-01-01 and 2027-12-31.")
            return false
        }
        guard start <= end else {
            alert("Check the holiday range", "The range start must not be later than the range end.")
            return false
        }
        return true
    }

    /// Every rate and discount as typed, or nil when a field is not a usable number.
    private func validatedModels(from store: SettingsStore) -> [ModelRate]? {
        var models: [ModelRate] = []
        for model in store.models {
            var standard = model.standard
            if let fields = rateFields[model.id] {
                for component in RateComponent.allCases {
                    guard let field = fields[component],
                          let value = parseNumberPublic(field.text),
                          value >= 0 else {
                        alert("Check the rates", "Enter a valid non-negative USD price for " + model.name + " - " + component.title + ".")
                        return nil
                    }
                    switch component {
                    case .cacheHit: standard.cacheHit = value
                    case .cacheMiss: standard.cacheMiss = value
                    case .output: standard.output = value
                    }
                }
            }
            guard let discountField = discountFields[model.id],
                  let discount = parseNumberPublic(discountField.text),
                  discount >= 0, discount <= 100 else {
                alert("Check the discount", "Enter the off-peak discount for " + model.name + " as a percentage between 0 and 100.")
                return nil
            }
            models.append(ModelRate(id: model.id,
                                    name: model.name,
                                    label: model.label,
                                    standard: standard,
                                    offPeakDiscountPercent: discount))
        }
        return models
    }

    private func parseMinutePublic(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private func parseNumberPublic(_ text: String?) -> Double? {
        guard let text = text else { return nil }
        return Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
