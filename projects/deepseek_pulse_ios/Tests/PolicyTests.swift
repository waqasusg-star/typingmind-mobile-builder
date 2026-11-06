import Foundation

var checkCount = 0

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    checkCount += 1
    if !value() { fatalError("FAILED: " + message) }
}

@main struct PolicyTests {

    static func main() {
        let utc = PricingSchedule.utcCalendar

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
            utc.date(from: DateComponents(year: year, month: month, day: day,
                                          hour: hour, minute: minute, second: second))!
        }

        let schedule = RateSeeds.schedule

        // MARK: 1. Verified calendar seeds
        expect(schedule.holidays.dates.count == 62, "62 verified PRC holiday dates are seeded")
        expect(schedule.holidays.coverageStart == "2026-01-01", "Calendar coverage starts 2026-01-01")
        expect(schedule.holidays.coverageEnd == "2027-12-31", "Calendar coverage ends 2027-12-31")
        expect(schedule.holidays.verifiedAsOf == "2026-11-06", "Calendar carries the verification date")
        expect(schedule.holidays.source != nil, "Calendar records its source")
        expect(schedule.holidays.sourceHost.contains("gov.cn"), "Source host is an official government site")
        expect(schedule.holidays.isVerified, "A declared coverage range counts as verified")
        expect(schedule.holidays.summary.contains("62"), "Summary reports the date count")
        expect(schedule.holidays.summary.contains("2027-12-31"), "Summary reports the coverage range")
        for key in ["2026-01-01", "2026-02-15", "2026-02-23", "2026-10-07", "2027-02-13", "2027-06-09", "2027-09-15", "2027-10-07"] {
            expect(schedule.holidays.dates.contains(key), "Verified holiday listed: " + key)
            expect(schedule.holidays.kind(forDay: key) == .holiday, "Listed day is a holiday: " + key)
        }
        for key in ["2026-01-04", "2026-02-24", "2026-11-09", "2027-10-08"] {
            expect(!schedule.holidays.dates.contains(key), "Not a holiday: " + key)
            expect(schedule.holidays.kind(forDay: key) == .workingDay, "Covered day is a working day: " + key)
        }
        expect(schedule.holidays.kind(forDay: "2025-12-31") == .unverified, "2025 is outside the verified range")
        expect(schedule.holidays.kind(forDay: "2028-01-03") == .unverified, "2028 is outside the verified range")

        // MARK: 2. Weekday anchors
        expect(PricingSchedule.isoWeekday(date(2026, 11, 6)) == 5, "2026-11-06 is a Friday")
        expect(PricingSchedule.isoWeekday(date(2026, 1, 1)) == 4, "2026-01-01 is a Thursday")
        expect(PricingSchedule.isoWeekday(date(2026, 1, 5)) == 1, "2026-01-05 is a Monday")
        expect(PricingSchedule.isoWeekday(date(2026, 11, 14)) == 6, "2026-11-14 is a Saturday")
        expect(PricingSchedule.isoWeekday(date(2027, 12, 31)) == 5, "2027-12-31 is a Friday")
        expect(PricingSchedule.isoWeekday(date(2028, 1, 3)) == 1, "2028-01-03 is a Monday")

        // MARK: 3. Both weekday peak windows and their exact boundaries
        expect(schedule.peakWeekdays == [1, 2, 3, 4, 5], "Peak days are Monday to Friday")
        expect(schedule.intervals.count == 2, "Two peak intervals per weekday")
        expect(schedule.sortedIntervals[0] == PeakInterval(startMinuteUTC: 60, endMinuteUTC: 240), "Window 1 is 01:00-04:00 UTC")
        expect(schedule.sortedIntervals[1] == PeakInterval(startMinuteUTC: 360, endMinuteUTC: 600), "Window 2 is 06:00-10:00 UTC")
        expect(schedule.intervalSummaryUTC == "01:00–04:00, 06:00–10:00 UTC", "UTC interval summary")
        expect(schedule.weekdaySummary == "Mon–Fri", "Weekday summary")
        expect(schedule.isActive, "Seeded schedule is usable")
        expect(!schedule.isPeak(at: date(2026, 11, 9, 0, 59, 59)), "00:59:59 UTC is off-peak")
        expect(schedule.isPeak(at: date(2026, 11, 9, 1, 0)), "01:00 UTC starts peak (inclusive)")
        expect(schedule.isPeak(at: date(2026, 11, 9, 3, 59, 59)), "03:59:59 UTC is peak")
        expect(!schedule.isPeak(at: date(2026, 11, 9, 4, 0)), "04:00 UTC ends peak (exclusive)")
        expect(!schedule.isPeak(at: date(2026, 11, 9, 4, 0, 1)), "04:00:01 UTC is off-peak")
        expect(!schedule.isPeak(at: date(2026, 11, 9, 5, 59)), "05:59 UTC is off-peak")
        expect(schedule.isPeak(at: date(2026, 11, 9, 6, 0)), "06:00 UTC starts peak")
        expect(schedule.isPeak(at: date(2026, 11, 9, 9, 59, 59)), "09:59:59 UTC is peak")
        expect(!schedule.isPeak(at: date(2026, 11, 9, 10, 0)), "10:00 UTC ends peak")
        expect(!schedule.isPeak(at: date(2026, 11, 9, 12, 0)), "Midday UTC is off-peak")
        expect(schedule.state(at: date(2026, 11, 9, 2, 0)) == .peak, "Inside a window the state is peak")
        expect(schedule.state(at: date(2026, 11, 9, 2, 0)).label == "PEAK", "Peak label")
        expect(schedule.state(at: date(2026, 11, 9, 5, 0)) == .offPeak, "Between windows the state is off-peak")
        expect(schedule.state(at: date(2026, 11, 9, 5, 0)).label == "OFF-PEAK", "Off-peak label")
        expect(schedule.daySchedule(for: date(2026, 11, 9, 2, 0)).intervals == schedule.sortedIntervals,
               "A working weekday carries both windows")
        expect(schedule.daySchedule(for: date(2026, 11, 9, 2, 0)).kind == .workingDay, "2026-11-09 is a covered working day")

        // MARK: 4. Holidays suppress peak windows
        expect(!schedule.isPeak(at: date(2026, 1, 1, 2, 0)), "New Year's Day 2026 is off-peak")
        expect(!schedule.isPeak(at: date(2026, 1, 1, 7, 0)), "New Year's Day 2026 has no second window")
        expect(!schedule.isPeak(at: date(2026, 1, 2, 2, 0)), "2026-01-02 is a holiday")
        expect(schedule.daySchedule(for: date(2026, 1, 1, 2, 0)).intervals.isEmpty, "Holiday day has no peak intervals")
        expect(schedule.isPeak(at: date(2026, 1, 5, 2, 0)), "The Monday after New Year is peak again")
        expect(!schedule.isPeak(at: date(2026, 2, 23, 2, 0)), "Spring Festival final day 2026 is a holiday")
        expect(schedule.isPeak(at: date(2026, 2, 24, 2, 0)), "2026-02-24 is a working day")
        expect(!schedule.isPeak(at: date(2026, 5, 4, 2, 0)), "Labour Day 2026 Monday is a holiday")
        expect(!schedule.isPeak(at: date(2027, 2, 8, 2, 0)), "2027 Spring Festival Monday is a holiday")
        expect(!schedule.isPeak(at: date(2027, 10, 7, 2, 0)), "2027-10-07 is a holiday")
        expect(schedule.isPeak(at: date(2027, 10, 8, 2, 0)), "2027-10-08 is a working Friday")
        expect(!schedule.isPeak(at: date(2026, 10, 7, 2, 0)), "2026-10-07 is a holiday")
        expect(schedule.isPeak(at: date(2026, 10, 8, 2, 0)), "2026-10-08 is a working Thursday")

        // MARK: 5. Every weekend is off-peak, including PRC make-up working days
        var weekendDays = 0
        var cursor = date(2026, 1, 1, 2, 0)
        let endDate = date(2027, 12, 31, 2, 0)
        while cursor <= endDate {
            let weekday = PricingSchedule.isoWeekday(cursor)
            if weekday == 6 || weekday == 7 {
                weekendDays += 1
                expect(!schedule.isPeak(at: cursor), "Weekend 02:00 UTC is off-peak: " + PricingSchedule.dayKey(cursor))
                expect(schedule.daySchedule(for: cursor).intervals.isEmpty,
                       "Weekend carries no peak window: " + PricingSchedule.dayKey(cursor))
                let evening = cursor.addingTimeInterval(5 * 3600)
                expect(!schedule.isPeak(at: evening), "Weekend 07:00 UTC is off-peak: " + PricingSchedule.dayKey(cursor))
            }
            cursor = cursor.addingTimeInterval(86400)
        }
        expect(weekendDays > 200, "Two years contain more than 200 weekend days")
        expect(!schedule.isPeak(at: date(2026, 2, 14, 2, 0)), "A Saturday is off-peak even near Spring Festival")
        expect(!schedule.isPeak(at: date(2026, 11, 15, 7, 0)), "Sunday is off-peak")
        expect(schedule.state(at: date(2026, 11, 14, 9, 0)) == .offPeak, "Saturday state is off-peak")

        // MARK: 6. Transitions inside the day
        let t1 = schedule.nextTransition(after: date(2026, 11, 9, 0, 30))
        expect(t1 != nil, "A transition exists before the first window")
        expect(t1?.becomesPeak == true, "00:30 UTC leads to a peak start")
        expect(Int(t1!.date.timeIntervalSince(date(2026, 11, 9, 0, 30))) == 1800, "00:30 to 01:00 is 30 minutes")
        expect(t1?.daysAhead == 0, "Same day transition")
        expect(t1?.uncertain == false, "A covered working day is not uncertain")
        expect(t1?.dayKind == .workingDay, "Transition day kind is working day")

        let t2 = schedule.nextTransition(after: date(2026, 11, 9, 2, 0))
        expect(t2?.becomesPeak == false, "Inside a peak the next change is off-peak")
        expect(Int(t2!.date.timeIntervalSince(date(2026, 11, 9, 2, 0))) == 7200, "02:00 to 04:00 is 2 hours")

        let t3 = schedule.nextTransition(after: date(2026, 11, 9, 4, 0))
        expect(t3?.becomesPeak == true, "At the window end the next change is the second peak")
        expect(Int(t3!.date.timeIntervalSince(date(2026, 11, 9, 4, 0))) == 7200, "04:00 to 06:00 is 2 hours")

        let t4 = schedule.nextTransition(after: date(2026, 11, 9, 4, 30))
        expect(Int(t4!.date.timeIntervalSince(date(2026, 11, 9, 4, 30))) == 5400, "04:30 to 06:00 is 90 minutes")

        let t5 = schedule.nextTransition(after: date(2026, 11, 9, 1, 0))
        expect(t5?.becomesPeak == false, "At the peak start the next change is off-peak")
        expect(Int(t5!.date.timeIntervalSince(date(2026, 11, 9, 1, 0))) == 10800, "01:00 to 04:00 is 3 hours")

        // MARK: 7. Multi-day countdown across nights, weekends and holidays
        let overnight = schedule.nextTransition(after: date(2026, 11, 9, 10, 30))
        expect(Int(overnight!.date.timeIntervalSince(date(2026, 11, 9, 10, 30))) == 52200, "Monday 10:30 to Tuesday 01:00 is 14.5 hours")
        expect(overnight?.daysAhead == 1, "Next working-day peak is one day ahead")

        let weekend = schedule.nextTransition(after: date(2026, 11, 13, 10, 30))
        expect(weekend?.becomesPeak == true, "Friday evening leads to a peak start")
        expect(Int(weekend!.date.timeIntervalSince(date(2026, 11, 13, 10, 30))) == 225000, "Friday 10:30 to Monday 01:00 is 62.5 hours")
        expect(weekend?.daysAhead == 3, "Monday is three UTC days ahead")
        expect(PricingSchedule.dayKey(weekend!.date) == "2026-11-16", "The weekend is skipped to 2026-11-16")
        expect(ClockFormat.countdown(seconds: 225000) == "2d 14h 30m", "Multi-day countdown format")

        let newYear = schedule.nextTransition(after: date(2026, 1, 1, 0, 30))
        expect(newYear?.becomesPeak == true, "Inside the New Year holiday the next change is a peak start")
        expect(Int(newYear!.date.timeIntervalSince(date(2026, 1, 1, 0, 30))) == 347400, "2026-01-01 00:30 to 2026-01-05 01:00 is 96.5 hours")
        expect(newYear?.daysAhead == 4, "Four UTC days ahead")
        expect(PricingSchedule.dayKey(newYear!.date) == "2026-01-05", "Holidays and the weekend are skipped")
        expect(ClockFormat.countdown(seconds: 347400) == "4d 0h 30m", "Four day countdown format")

        let springFollowUp = schedule.nextTransition(after: date(2026, 2, 23, 8, 0))
        expect(Int(springFollowUp!.date.timeIntervalSince(date(2026, 2, 23, 8, 0))) == 61200, "2026-02-23 08:00 to 2026-02-24 01:00 is 17 hours")
        expect(PricingSchedule.dayKey(springFollowUp!.date) == "2026-02-24", "Spring Festival end leads to 2026-02-24")

        // MARK: 8. Year-end unknown calendar
        let yearEnd = schedule.nextTransition(after: date(2027, 12, 31, 10, 30))
        expect(yearEnd != nil, "A transition is still found past the verified calendar")
        expect(PricingSchedule.dayKey(yearEnd!.date) == "2028-01-03", "The countdown crosses into 2028")
        expect(yearEnd?.uncertain == true, "2028 is flagged as uncertain")
        expect(yearEnd?.dayKind == .unverified, "2028 day kind is unverified")
        expect(Int(yearEnd!.date.timeIntervalSince(date(2027, 12, 31, 10, 30))) == 225000, "2027-12-31 10:30 to 2028-01-03 01:00 is 62.5 hours")
        expect(schedule.calendarWarning(at: date(2027, 12, 31, 10, 30)) == nil, "2027 is covered, so no warning")
        let warning = schedule.calendarWarning(at: date(2028, 1, 3, 2, 0))
        expect(warning != nil, "2028 produces a calendar warning")
        expect(warning!.contains("2028"), "The warning names the year")
        expect(schedule.isUncertain(at: date(2028, 1, 3, 2, 0)), "A 2028 weekday is uncertain")
        expect(!schedule.isUncertain(at: date(2026, 11, 9, 2, 0)), "A covered weekday is certain")
        expect(!schedule.isUncertain(at: date(2026, 11, 14, 2, 0)), "A weekend is not uncertain")

        // MARK: 9. Full 24 hour bands
        func checkBands(_ day: Date, _ label: String) {
            let bands = schedule.segments(for: day)
            expect(!bands.isEmpty, "Bands exist for " + label)
            expect(bands.first!.startMinute == 0, "Bands start at 00:00 for " + label)
            expect(bands.last!.endMinute == 1440, "Bands end at 24:00 for " + label)
            var total = 0
            for index in 0..<bands.count {
                total += bands[index].endMinute - bands[index].startMinute
                if index > 0 {
                    expect(bands[index - 1].endMinute == bands[index].startMinute, "Bands are contiguous for " + label)
                }
            }
            expect(total == 1440, "Bands cover exactly 24 hours for " + label)
        }
        checkBands(date(2026, 11, 9, 2, 0), "a working Monday")
        checkBands(date(2026, 11, 14, 2, 0), "a Saturday")
        checkBands(date(2026, 11, 15, 2, 0), "a Sunday")
        checkBands(date(2026, 1, 1, 2, 0), "a PRC holiday")
        checkBands(date(2028, 1, 3, 2, 0), "an unverified 2028 Monday")

        let workingBands = schedule.segments(for: date(2026, 11, 9, 2, 0))
        expect(workingBands.count == 5, "A working weekday has five bands")
        expect(workingBands[0].state == .offPeak, "00:00-01:00 is off-peak")
        expect(workingBands[1].state == .peak, "01:00-04:00 is peak")
        expect(workingBands[2].state == .offPeak, "04:00-06:00 is off-peak")
        expect(workingBands[3].state == .peak, "06:00-10:00 is peak")
        expect(workingBands[4].state == .offPeak, "10:00-24:00 is off-peak")
        var peakMinutes = 0
        for band in workingBands where band.state == .peak {
            peakMinutes += band.endMinute - band.startMinute
        }
        expect(peakMinutes == 420, "Weekday peak covers seven hours")
        let holidayBands = schedule.segments(for: date(2026, 1, 1, 2, 0))
        expect(holidayBands.count == 1 && holidayBands[0].state == .offPeak, "A holiday is one off-peak band")
        let weekendBands = schedule.segments(for: date(2026, 11, 14, 2, 0))
        expect(weekendBands.count == 1 && weekendBands[0].state == .offPeak, "A Saturday is one off-peak band")

        var withdrawn = schedule
        withdrawn.discountsEnabled = false
        expect(withdrawn.state(at: date(2026, 11, 9, 2, 0)) == .standard, "Withdrawn discounts report standard pricing")
        expect(withdrawn.state(at: date(2026, 11, 9, 2, 0)).label == "STANDARD", "Standard label")
        expect(!withdrawn.isPeak(at: date(2026, 11, 9, 2, 0)), "Nothing is peak when discounts are withdrawn")
        expect(withdrawn.nextTransition(after: date(2026, 11, 9, 2, 0)) == nil, "No transitions when discounts are withdrawn")
        expect(withdrawn.segments(for: date(2026, 11, 9, 2, 0)).count == 1, "One band when discounts are withdrawn")
        expect(withdrawn.segments(for: date(2026, 11, 9, 2, 0))[0].state == .standard, "That band is standard")

        // MARK: 10. Seven day outlook
        let outlook = schedule.outlook(from: date(2026, 1, 1, 12, 0), days: 7)
        expect(outlook.count == 7, "Outlook returns seven days")
        expect(outlook[0].key == "2026-01-01", "Outlook starts today")
        expect(outlook[1].key == "2026-01-02", "Second outlook day")
        expect(outlook[0].intervals.isEmpty && outlook[1].intervals.isEmpty, "Holiday days carry no windows")
        expect(outlook[4].key == "2026-01-05" && !outlook[4].intervals.isEmpty, "Monday regains its windows")
        expect(outlook[6].key == "2026-01-07", "Outlook ends on the seventh day")
        let weekOutlook = schedule.outlook(from: date(2026, 11, 9, 12, 0), days: 7)
        expect(weekOutlook[5].intervals.isEmpty && weekOutlook[6].intervals.isEmpty, "Both weekend days are off-peak")

        // MARK: 11. Local time conversion
        let reference = date(2026, 11, 9, 12, 0)
        expect(ClockFormat.localLabel(minuteUTC: 60, on: reference, timeZone: TimeZone(secondsFromGMT: 0)!) == "01:00", "01:00 UTC is 01:00 at UTC")
        expect(ClockFormat.localLabel(minuteUTC: 60, on: reference, timeZone: TimeZone(secondsFromGMT: 5 * 3600 + 1800)!) == "06:30", "01:00 UTC is 06:30 at +05:30")
        expect(ClockFormat.localLabel(minuteUTC: 600, on: reference, timeZone: TimeZone(secondsFromGMT: -5 * 3600)!) == "05:00", "10:00 UTC is 05:00 at -05:00")
        expect(schedule.intervalSummaryLocal(on: reference, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!) == "09:00–12:00, 14:00–18:00", "PRC local windows")
        expect(schedule.intervalSummaryLocal(on: reference, timeZone: TimeZone(secondsFromGMT: 0)!) == "01:00–04:00, 06:00–10:00", "UTC local windows")
        expect(ClockFormat.minuteLabel(240) == "04:00", "Minute label")
        expect(ClockFormat.minuteLabel(0) == "00:00", "Midnight label")
        expect(ClockFormat.countdown(seconds: 3661) == "1h 1m", "Hours shorten to minutes")
        expect(ClockFormat.countdown(seconds: 90) == "1m 30s", "Minutes keep seconds")
        expect(ClockFormat.countdown(seconds: 90061) == "1d 1h 1m", "Days come first")
        expect(ClockFormat.countdown(seconds: -5) == "0s", "Negative countdown clamps to zero")

        // MARK: 12. Verified rates
        let flash = RateSeeds.models[0]
        let pro = RateSeeds.models[1]
        expect(RateSeeds.models.count == 2, "Only the two published models are seeded")
        expect(flash.id == "deepseek-flash" && flash.label == "V4.1-Flash-1017", "Flash identity")
        expect(pro.id == "deepseek-v4-pro" && pro.label == "V4-Pro-0813", "Pro identity")
        expect(flash.standard.cacheHit == 0.006, "Flash peak cache-hit")
        expect(flash.standard.cacheMiss == 0.30, "Flash peak cache-miss")
        expect(flash.standard.output == 1.20, "Flash peak output")
        expect(abs(flash.offPeak.cacheHit - 0.003) < 1e-9, "Flash off-peak cache-hit is 0.003")
        expect(abs(flash.offPeak.cacheMiss - 0.15) < 1e-9, "Flash off-peak cache-miss is 0.15")
        expect(abs(flash.offPeak.output - 0.60) < 1e-9, "Flash off-peak output is 0.60")
        expect(pro.standard.cacheHit == 0.044, "Pro peak cache-hit")
        expect(pro.standard.cacheMiss == 1.32, "Pro peak cache-miss")
        expect(pro.standard.output == 3.96, "Pro peak output")
        expect(abs(pro.offPeak.cacheHit - 0.022) < 1e-9, "Pro off-peak cache-hit is 0.022")
        expect(abs(pro.offPeak.cacheMiss - 0.66) < 1e-9, "Pro off-peak cache-miss is 0.66")
        expect(abs(pro.offPeak.output - 1.98) < 1e-9, "Pro off-peak output is 1.98")
        expect(flash.clampedDiscount == 50 && pro.clampedDiscount == 50, "Both models are 50% off in off-peak")
        expect(!RateSeeds.models.contains { $0.id == "deepseek-reasoner" }, "The retired reasoner model is gone")
        expect(RateSeeds.models.allSatisfy { $0.clampedDiscount < 75 }, "No 75% discount remains")
        expect(abs(flash.rates(offPeakActive: true).output - 0.60) < 1e-9, "Off-peak uses discounted rates")
        expect(flash.rates(offPeakActive: false).output == flash.standard.output, "Peak uses standard rates")
        var wild = flash
        wild.offPeakDiscountPercent = 140
        expect(wild.clampedDiscount == 100 && abs(wild.offPeak.output) < 1e-9, "Discount clamps at 100%")
        wild.offPeakDiscountPercent = -20
        expect(wild.clampedDiscount == 0 && wild.offPeak.output == wild.standard.output, "Discount clamps at 0%")
        expect(RateSeeds.verifiedAsOf == "2026-11-06", "Rates carry the verification date")
        expect(RateSeeds.schedule.verifiedAsOf == RateSeeds.verifiedAsOf, "Schedule carries the same date")
        expect(RateSeeds.sourceNote.contains("api-docs.deepseek.com"), "Source note names the pricing page")

        // MARK: 13. Number formatting
        expect(MoneyFormat.rate(0.006) == "0.006", "Small rate keeps three decimals")
        expect(MoneyFormat.rate(1.2) == "1.20", "Whole style rate keeps two decimals")
        expect(MoneyFormat.rate(0.15) == "0.15", "Two decimal rate")
        expect(MoneyFormat.rate(3.96) == "3.96", "Pro output rate")
        expect(MoneyFormat.rate(0.044) == "0.044", "Pro cache-hit rate")
        expect(MoneyFormat.symbol(for: "CNY") == "¥", "CNY symbol")
        expect(MoneyFormat.symbol(for: "usd") == "$", "Currency codes are case insensitive")
        expect(MoneyFormat.amount("110.00", currency: "CNY") == "¥110.00", "Amount formatting")
        expect(MoneyFormat.amount("", currency: "USD") == "—", "Empty amount is a dash")
        expect(MoneyFormat.decimal("1,234.50") == 1234.5, "Thousand separators are ignored")

        // MARK: 14. Balance schema
        let documented = "{\"is_available\": true, \"balance_infos\": [{\"currency\": \"CNY\", \"total_balance\": \"110.00\", \"granted_balance\": \"10.00\", \"topped_up_balance\": \"100.00\"}]}".data(using: .utf8)!
        let parsed = BalanceParser.snapshot(from: documented, at: reference)
        expect(parsed?.isAvailable == true, "Availability flag is kept")
        expect(parsed?.balanceInfos.count == 1, "One balance entry")
        expect(parsed?.primary?.currency == "CNY", "Currency is upper-cased")
        expect(parsed?.primary?.total == 110.0, "Total balance parses")
        expect(parsed?.primary?.granted == 10.0, "Granted balance parses")
        expect(parsed?.primary?.toppedUp == 100.0, "Topped-up balance parses")
        expect(parsed?.fetchedAt == reference, "Fetch timestamp is attached")

        let numeric = "{\"is_available\": false, \"balance_infos\": [{\"currency\": \"usd\", \"total_balance\": 0, \"granted_balance\": 0, \"topped_up_balance\": 0}]}".data(using: .utf8)!
        expect(BalanceParser.snapshot(from: numeric)?.primary?.currency == "USD", "Lowercase currency is normalised")
        expect(BalanceParser.snapshot(from: numeric)?.primary?.total == 0, "Numeric balances are accepted")
        expect(BalanceParser.snapshot(from: numeric)?.isAvailable == false, "Numeric availability parses")

        let partial = "{\"balance_infos\": [{\"currency\": \"CNY\"}]}".data(using: .utf8)!
        expect(BalanceParser.snapshot(from: partial)?.isAvailable == false, "Missing availability defaults to false")
        expect(BalanceParser.snapshot(from: partial)?.primary?.totalBalance == "", "Missing amount stays empty")

        let twoCurrencies = "{\"is_available\": true, \"balance_infos\": [{\"currency\": \"CNY\", \"total_balance\": \"1.00\"}, {\"currency\": \"USD\", \"total_balance\": \"2.00\"}]}".data(using: .utf8)!
        expect(BalanceParser.snapshot(from: twoCurrencies)?.primary?.currency == "USD", "USD is preferred when both are returned")
        expect(BalanceParser.snapshot(from: "not json".data(using: .utf8)!) == nil, "Invalid JSON is rejected")

        let encodedSnapshot = try! JSONEncoder().encode(parsed!)
        let decodedSnapshot = try! JSONDecoder().decode(BalanceSnapshot.self, from: encodedSnapshot)
        expect(decodedSnapshot == parsed, "Cached balance survives a storage round-trip")

        // MARK: 15. Request policy
        expect(RequestPolicy.balanceEndpoint == "https://api.deepseek.com/user/balance", "Balance endpoint is unchanged")
        expect(RequestPolicy.isAllowed(url: RequestPolicy.balanceURL), "The reviewed endpoint is allowed")
        expect(!RequestPolicy.isAllowed(url: URL(string: "https://api.deepseek.com.evil.example/user/balance")!), "Lookalike hosts are rejected")
        expect(!RequestPolicy.isAllowed(url: URL(string: "http://api.deepseek.com/user/balance")!), "Cleartext is rejected")
        expect(!RequestPolicy.isAllowed(url: URL(string: "https://api.deepseek.com/user/other")!), "Other paths are rejected")
        expect(RequestPolicy.normalizedKey("  sk-test \n") == "sk-test", "Keys are trimmed")
        expect(RequestPolicy.requestIfValid(apiKey: "   ") == nil, "Blank keys build no request")
        let built = RequestPolicy.request(apiKey: "sk-test")
        expect(built.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test", "Bearer header")
        expect(built.value(forHTTPHeaderField: "Accept") == "application/json", "JSON accept header")
        expect(built.httpMethod == "GET", "Balance read is a GET")
        expect(built.url?.absoluteString == "https://api.deepseek.com/user/balance", "Request points at the balance endpoint")
        expect(built.timeoutInterval > 0, "Request has a timeout")
        expect(RequestPolicy.error(forStatus: 200) == nil, "200 is success")
        expect(RequestPolicy.error(forStatus: 401) == .unauthorized, "401 is an auth error")
        expect(RequestPolicy.error(forStatus: 403) == .unauthorized, "403 is an auth error")
        expect(RequestPolicy.error(forStatus: 429) == .rateLimited, "429 is rate limiting")
        expect(RequestPolicy.error(forStatus: 503) == .http(503), "Other statuses surface the code")
        expect(!BalanceFetchError.unauthorized.message.isEmpty, "Auth failures have a message")

        // MARK: 16. Storage round-trip of the schedule
        let encodedSchedule = try! JSONEncoder().encode(schedule)
        let decodedSchedule = try! JSONDecoder().decode(PricingSchedule.self, from: encodedSchedule)
        expect(decodedSchedule == schedule, "Schedule survives a storage round-trip")
        expect(decodedSchedule.holidays.dates.count == 62, "Holiday dates survive storage")
        expect(decodedSchedule.holidays.coverageEnd == "2027-12-31", "Coverage survives storage")

        print("PASS: " + String(checkCount) + " schedule, holiday, weekend, countdown, band, rate, formatting, balance and request checks")
    }
}
