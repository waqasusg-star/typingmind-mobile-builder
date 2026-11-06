import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

@main struct LogicTests {
    static func main() {
        let utc = PricingSchedule.utcCalendar

        func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
            utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
        }

        // Verified calendar anchors: 2026-11-06 is a Friday, so 11-09 is Monday and 11-14 Saturday.
        let schedule = RateSeeds.schedule
        expect(PricingSchedule.isoWeekday(utcDate(2026, 11, 6, 12, 0)) == 5, "2026-11-06 must be a Friday")
        expect(PricingSchedule.isoWeekday(utcDate(2026, 11, 9, 0, 0)) == 1, "2026-11-09 must be a Monday")
        expect(PricingSchedule.isoWeekday(utcDate(2026, 11, 14, 0, 0)) == 6, "2026-11-14 must be a Saturday")

        // 1. Official shape: two weekday intervals, no 75% reasoner, no 16:30 window.
        expect(schedule.peakWeekdays == [1, 2, 3, 4, 5], "Peak days are Monday to Friday")
        expect(schedule.intervals.count == 2, "Two peak intervals per weekday")
        expect(schedule.sortedIntervals[0] == PeakInterval(startMinuteUTC: 60, endMinuteUTC: 240), "First interval is 01:00-04:00 UTC")
        expect(schedule.sortedIntervals[1] == PeakInterval(startMinuteUTC: 360, endMinuteUTC: 600), "Second interval is 06:00-10:00 UTC")
        expect(schedule.discountsEnabled, "Off-peak discounts are on by default")
        expect(schedule.isActive, "The seeded schedule is usable")
        expect(schedule.weekdaySummary == "Mon–Fri", "Weekday summary reads Mon-Fri")
        expect(schedule.intervalSummaryUTC == "01:00–04:00, 06:00–10:00 UTC", "UTC interval summary")
        expect(schedule.holidays.dates.isEmpty, "No invented holiday dates are bundled")
        expect(!schedule.holidays.isVerified, "The empty holiday calendar is unverified")

        // 2. Exact boundaries on a Monday.
        let monday = utcDate(2026, 11, 9, 0, 0)
        func monday(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
            utcDate(2026, 11, 9, hour, minute, second)
        }
        expect(!schedule.isPeak(at: monday(0, 59, 59)), "00:59:59 UTC is off-peak")
        expect(schedule.isPeak(at: monday(1, 0)), "01:00 UTC starts peak (inclusive)")
        expect(schedule.isPeak(at: monday(3, 59, 59)), "03:59:59 UTC is peak")
        expect(!schedule.isPeak(at: monday(4, 0)), "04:00 UTC ends peak (exclusive)")
        expect(!schedule.isPeak(at: monday(5, 59)), "05:59 UTC is off-peak")
        expect(schedule.isPeak(at: monday(6, 0)), "06:00 UTC starts the second peak")
        expect(schedule.isPeak(at: monday(9, 59)), "09:59 UTC is peak")
        expect(!schedule.isPeak(at: monday(10, 0)), "10:00 UTC ends the second peak")
        expect(!schedule.isPeak(at: monday(12, 0)), "Midday UTC is off-peak")
        expect(!schedule.isPeak(at: monday(23, 59)), "Late evening UTC is off-peak")
        expect(schedule.state(at: monday(2, 0)) == .peak, "State is peak inside an interval")
        expect(schedule.state(at: monday(2, 0)).label == "PEAK", "Peak label")
        expect(schedule.state(at: monday(5, 0)) == .offPeak, "State is off-peak between intervals")
        expect(schedule.state(at: monday(5, 0)).label == "OFF-PEAK", "Off-peak label")
        _ = monday

        // 3. Weekends are off-peak all day.
        let saturday = utcDate(2026, 11, 14, 2, 0)
        let sunday = utcDate(2026, 11, 15, 7, 0)
        expect(!schedule.isPeak(at: saturday), "Saturday 02:00 UTC is off-peak")
        expect(!schedule.isPeak(at: sunday), "Sunday 07:00 UTC is off-peak")
        expect(schedule.state(at: saturday) == .offPeak, "Weekend state is off-peak")
        expect(schedule.daySchedule(for: saturday).intervals.isEmpty, "Weekend day has no peak intervals")
        expect(!schedule.isUncertain(at: saturday), "Weekends are known off-peak, not uncertain")

        // 4. Holiday overrides.
        var holidaySchedule = schedule
        holidaySchedule.holidays.dates = ["2026-11-11"]
        expect(holidaySchedule.daySchedule(for: utcDate(2026, 11, 11, 2, 0)).kind == .holiday, "Listed date is a holiday")
        expect(!holidaySchedule.isPeak(at: utcDate(2026, 11, 11, 2, 0)), "A PRC holiday has no peak window")
        expect(holidaySchedule.state(at: utcDate(2026, 11, 11, 2, 0)) == .offPeak, "Holiday state is off-peak")
        expect(holidaySchedule.isPeak(at: utcDate(2026, 11, 10, 2, 0)), "The day before a holiday keeps its peak")

        // 5. Calendar coverage and unknown state.
        expect(schedule.holidays.kind(forDay: "2026-11-09") == .unverified, "No coverage means unverified")
        var covered = schedule
        covered.holidays.coverageStart = "2026-01-01"
        covered.holidays.coverageEnd = "2026-12-31"
        covered.holidays.verifiedAsOf = "2026-11-06"
        expect(covered.holidays.kind(forDay: "2026-11-09") == .workingDay, "Inside coverage a weekday is a working day")
        expect(covered.holidays.kind(forDay: "2027-01-04") == .unverified, "Outside coverage the day is unverified")
        expect(covered.holidays.covers("2026-06-15"), "Coverage check inside the range")
        expect(!covered.holidays.covers("2027-06-15"), "Coverage check outside the range")
        expect(covered.holidays.isVerified, "A dated range with dates is verified")
        expect(schedule.isUncertain(at: monday(2, 0)), "A weekday peak is uncertain without a holiday calendar")
        expect(!covered.isUncertain(at: monday(2, 0)), "A covered weekday is not uncertain")
        var holidayInsideCoverage = covered
        holidayInsideCoverage.holidays.dates = ["2026-11-09"]
        expect(!holidayInsideCoverage.isPeak(at: monday(2, 0)), "A holiday inside coverage cancels the peak")
        expect(holidayInsideCoverage.holidays.summary.contains("2026-01-01"), "Summary names the verified range")
        expect(schedule.holidays.summary.contains("not loaded"), "Empty calendar summary says it is not loaded")

        // 6. Transitions inside a day.
        let t1 = schedule.nextTransition(after: monday(0, 30))
        expect(t1?.becomesPeak == true, "00:30 UTC leads to a peak start")
        expect(Int(t1!.date.timeIntervalSince(monday(0, 30))) == 1800, "00:30 to 01:00 is 30 minutes")
        expect(t1?.daysAhead == 0, "Same day transition")
        expect(t1?.uncertain == true, "Weekday transition is uncertain without holidays")

        let t2 = schedule.nextTransition(after: monday(2, 0))
        expect(t2?.becomesPeak == false, "Inside a peak the next change is off-peak")
        expect(Int(t2!.date.timeIntervalSince(monday(2, 0))) == 7200, "02:00 to 04:00 is 2 hours")

        let t3 = schedule.nextTransition(after: monday(4, 30))
        expect(Int(t3!.date.timeIntervalSince(monday(4, 30))) == 5400, "04:30 to 06:00 is 90 minutes")

        let t4 = schedule.nextTransition(after: monday(1, 0))
        expect(t4?.becomesPeak == false, "At the peak start the next change is off-peak")
        expect(Int(t4!.date.timeIntervalSince(monday(1, 0))) == 3 * 3600, "01:00 to 04:00 is 3 hours")

        let t5 = schedule.nextTransition(after: monday(4, 0))
        expect(t5?.becomesPeak == true, "At the peak end the next change is peak")
        expect(Int(t5!.date.timeIntervalSince(monday(4, 0))) == 2 * 3600, "04:00 to 06:00 is 2 hours")

        // 7. Multi-day search across days and weekends.
        let tuesdayFromMondayNight = schedule.nextTransition(after: monday(10, 30))
        expect(Int(tuesdayFromMondayNight!.date.timeIntervalSince(monday(10, 30))) == 14 * 3600 + 1800, "Monday 10:30 to Tuesday 01:00 is 14.5 hours")
        expect(tuesdayFromMondayNight?.daysAhead == 1, "Next working-day peak is one day ahead")

        let fridayLate = utcDate(2026, 11, 13, 10, 30)
        let fromFriday = schedule.nextTransition(after: fridayLate)
        expect(fromFriday?.becomesPeak == true, "Friday evening leads to a peak start")
        expect(Int(fromFriday!.date.timeIntervalSince(fridayLate)) == 62 * 3600 + 1800, "Friday 10:30 to Monday 01:00 is 62.5 hours")
        expect(fromFriday?.daysAhead == 3, "Monday is three UTC days ahead")
        expect(PricingSchedule.dayKey(fromFriday!.date) == "2026-11-16", "The weekend is skipped to Monday 2026-11-16")
        expect(ClockFormat.countdown(seconds: Int(fromFriday!.date.timeIntervalSince(fridayLate))) == "2d 14h 30m", "Multi-day countdown format")

        let thursdayHoliday = holidaySchedule
        let fromTuesdayWithWednesdayHoliday = thursdayHoliday.nextTransition(after: utcDate(2026, 11, 10, 10, 30))
        expect(fromTuesdayWithWednesdayHoliday?.dayKind == .unverified, "Unlisted target day stays unverified")
        expect(PricingSchedule.dayKey(fromTuesdayWithWednesdayHoliday!.date) == "2026-11-12", "A Wednesday holiday skips to Thursday")
        expect(Int(fromTuesdayWithWednesdayHoliday!.date.timeIntervalSince(utcDate(2026, 11, 10, 10, 30))) == 38 * 3600 + 1800, "Tuesday 10:30 to Thursday 01:00 is 38.5 hours")
        expect(fromTuesdayWithWednesdayHoliday?.daysAhead == 2, "Thursday is two UTC days ahead")

        // 8. Withdrawn discounts behave as standard pricing everywhere.
        var withdrawn = schedule
        withdrawn.discountsEnabled = false
        expect(withdrawn.state(at: monday(2, 0)) == .standard, "Withdrawn discounts report standard pricing")
        expect(withdrawn.state(at: monday(2, 0)).label == "STANDARD", "Standard label")
        expect(!withdrawn.isPeak(at: monday(2, 0)), "Nothing is peak when discounts are withdrawn")
        expect(withdrawn.nextTransition(after: monday(2, 0)) == nil, "No transitions when discounts are withdrawn")
        expect(withdrawn.segments(for: monday(2, 0)).count == 1, "One standard band when discounts are withdrawn")
        expect(withdrawn.segments(for: monday(2, 0)).first?.state == .standard, "Band state is standard")

        // 9. Timeline segments of a peak day are contiguous and complete.
        let segments = schedule.segments(for: monday(2, 0))
        expect(segments.count == 5, "A weekday has five bands")
        expect(segments.first?.startMinute == 0, "Bands start at 00:00")
        expect(segments.last?.endMinute == 1440, "Bands end at 24:00")
        for index in 1..<segments.count {
            expect(segments[index - 1].endMinute == segments[index].startMinute, "Bands are contiguous")
        }
        let peakMinutes = segments.reduce(0) { $0 + ($1.state == .peak ? $1.endMinute - $1.startMinute : 0) }
        expect(peakMinutes == 420, "Weekday peak covers 7 hours")
        let weekendSegments = schedule.segments(for: saturday)
        expect(weekendSegments.count == 1 && weekendSegments[0].state == .offPeak, "Weekend band is off-peak all day")
        let holidaySegments = holidaySchedule.segments(for: utcDate(2026, 11, 11, 2, 0))
        expect(holidaySegments.count == 1 && holidaySegments[0].state == .offPeak, "Holiday band is off-peak all day")

        // 10. Seven day outlook.
        let outlook = schedule.outlook(from: monday(12, 0), days: 7)
        expect(outlook.count == 7, "Outlook returns seven days")
        expect(outlook.first?.key == "2026-11-09", "Outlook starts today")
        expect(outlook.last?.key == "2026-11-15", "Outlook ends on Sunday")
        expect(outlook[5].intervals.isEmpty && outlook[6].intervals.isEmpty, "Both weekend days are off-peak")
        expect(outlook[0].intervals.count == 2, "Monday keeps both intervals")

        // 11. Local conversion.
        let reference = utcDate(2026, 11, 9, 12, 0)
        expect(ClockFormat.localLabel(minuteUTC: 60, on: reference, timeZone: TimeZone(secondsFromGMT: 0)!) == "01:00", "01:00 UTC is 01:00 at UTC")
        expect(ClockFormat.localLabel(minuteUTC: 60, on: reference, timeZone: TimeZone(secondsFromGMT: 5 * 3600 + 1800)!) == "06:30", "01:00 UTC is 06:30 at +05:30")
        expect(ClockFormat.localLabel(minuteUTC: 600, on: reference, timeZone: TimeZone(secondsFromGMT: -5 * 3600)!) == "05:00", "10:00 UTC is 05:00 at -05:00")
        expect(schedule.intervalSummaryLocal(on: reference, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!) == "09:00–12:00, 14:00–18:00", "PRC local peak windows")
        expect(ClockFormat.minuteLabel(240) == "04:00", "Minute label")
        expect(ClockFormat.countdown(seconds: 3661) == "1h 1m", "Hours shorten to minutes")
        expect(ClockFormat.countdown(seconds: 90) == "1m 30s", "Minutes keep seconds")
        expect(ClockFormat.countdown(seconds: 90061) == "1d 1h 1m", "Days come first")
        expect(ClockFormat.countdown(seconds: -5) == "0s", "Negative countdown clamps to zero")

        // 12. Verified rates for both models, including the published off-peak values.
        let flash = RateSeeds.models[0]
        let pro = RateSeeds.models[1]
        expect(flash.id == "deepseek-flash" && flash.label == "V4.1-Flash-1017", "Flash identity")
        expect(pro.id == "deepseek-v4-pro" && pro.label == "V4-Pro-0813", "Pro identity")
        expect(flash.standard.cacheHit == 0.006, "Flash peak cache-hit price")
        expect(flash.standard.cacheMiss == 0.30, "Flash peak cache-miss price")
        expect(flash.standard.output == 1.20, "Flash peak output price")
        expect(abs(flash.offPeak.cacheHit - 0.003) < 1e-9, "Flash off-peak cache-hit is 0.003")
        expect(abs(flash.offPeak.cacheMiss - 0.15) < 1e-9, "Flash off-peak cache-miss is 0.15")
        expect(abs(flash.offPeak.output - 0.60) < 1e-9, "Flash off-peak output is 0.60")
        expect(pro.standard.cacheHit == 0.044, "Pro peak cache-hit price")
        expect(pro.standard.cacheMiss == 1.32, "Pro peak cache-miss price")
        expect(pro.standard.output == 3.96, "Pro peak output price")
        expect(abs(pro.offPeak.cacheHit - 0.022) < 1e-9, "Pro off-peak cache-hit is 0.022")
        expect(abs(pro.offPeak.cacheMiss - 0.66) < 1e-9, "Pro off-peak cache-miss is 0.66")
        expect(abs(pro.offPeak.output - 1.98) < 1e-9, "Pro off-peak output is 1.98")
        expect(flash.clampedDiscount == 50 && pro.clampedDiscount == 50, "Both models are 50% off in off-peak")
        expect(RateSeeds.models.count == 2, "Only the two published models are seeded")
        expect(!RateSeeds.models.contains { $0.id == "deepseek-reasoner" }, "The retired reasoner model is gone")
        expect(RateSeeds.models.allSatisfy { $0.clampedDiscount < 75 }, "No 75% reasoner discount remains")
        expect(flash.rates(offPeakActive: false).output == flash.standard.output, "Peak uses standard rates")
        expect(abs(flash.rates(offPeakActive: true).output - 0.60) < 1e-9, "Off-peak uses discounted rates")
        var wild = flash
        wild.offPeakDiscountPercent = 140
        expect(wild.clampedDiscount == 100 && abs(wild.offPeak.output) < 1e-9, "Discount is clamped to 100%")
        wild.offPeakDiscountPercent = -20
        expect(wild.clampedDiscount == 0 && wild.offPeak.output == wild.standard.output, "Negative discount is clamped to 0%")
        expect(RateSeeds.verifiedAsOf == "2026-11-06", "Rates carry the verification date")
        expect(RateSeeds.schedule.verifiedAsOf == RateSeeds.verifiedAsOf, "Schedule carries the same verification date")

        // 13. Number formatting.
        expect(MoneyFormat.rate(0.006) == "0.006", "Small rate keeps three decimals")
        expect(MoneyFormat.rate(1.2) == "1.20", "Whole-dollar style rate")
        expect(MoneyFormat.rate(0.15) == "0.15", "Two decimal rate")
        expect(MoneyFormat.rate(3.96) == "3.96", "Pro output rate")
        expect(MoneyFormat.symbol(for: "CNY") == "¥", "CNY symbol")
        expect(MoneyFormat.symbol(for: "usd") == "$", "Currency codes are case insensitive")
        expect(MoneyFormat.amount("110.00", currency: "CNY") == "¥110.00", "Amount formatting")
        expect(MoneyFormat.amount("", currency: "USD") == "—", "Empty amount is a dash")
        expect(MoneyFormat.decimal("1,234.50") == 1234.5, "Thousand separators are ignored")

        // 14. Balance schema of https://api.deepseek.com/user/balance.
        let documented = """
        {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "110.00", "granted_balance": "10.00", "topped_up_balance": "100.00"}]}
        """.data(using: .utf8)!
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

        let partial = "{\"balance_infos\": [{\"currency\": \"CNY\"}]}".data(using: .utf8)!
        expect(BalanceParser.snapshot(from: partial)?.isAvailable == false, "Missing availability defaults to false")
        expect(BalanceParser.snapshot(from: partial)?.primary?.totalBalance == "", "Missing amount stays empty")

        let twoCurrencies = "{\"is_available\": true, \"balance_infos\": [{\"currency\": \"CNY\", \"total_balance\": \"1.00\"}, {\"currency\": \"USD\", \"total_balance\": \"2.00\"}]}".data(using: .utf8)!
        expect(BalanceParser.snapshot(from: twoCurrencies)?.primary?.currency == "USD", "USD is preferred when both are returned")
        expect(BalanceParser.snapshot(from: "not json".data(using: .utf8)!) == nil, "Invalid JSON is rejected")

        // 15. Request building stays on the balance endpoint.
        expect(DeepSeekClient.balanceURL.absoluteString == "https://api.deepseek.com/user/balance", "Balance endpoint is unchanged")
        expect(DeepSeekClient.balanceURL.host == "api.deepseek.com", "Host is api.deepseek.com")
        expect(DeepSeekClient.balanceURL.path == "/user/balance", "Path is /user/balance")
        expect(DeepSeekClient.request(apiKey: "sk-test").value(forHTTPHeaderField: "Authorization") == "Bearer sk-test", "Bearer header")
        expect(DeepSeekClient.request(apiKey: "sk-test").httpMethod == "GET", "Balance read is a GET")
        expect(DeepSeekClient.error(forStatus: 200) == nil, "200 is success")
        expect(DeepSeekClient.error(forStatus: 401) == .unauthorized, "401 is an auth error")
        expect(DeepSeekClient.error(forStatus: 429) == .rateLimited, "429 is rate limiting")
        expect(DeepSeekClient.error(forStatus: 503) == .http(503), "Other statuses surface the code")

        // 16. Settings round-trip through Codable keeps the schedule intact.
        let encoded = try! JSONEncoder().encode(covered)
        let decoded = try! JSONDecoder().decode(PricingSchedule.self, from: encoded)
        expect(decoded == covered, "Schedule survives a storage round-trip")
        expect(decoded.holidays.coverageEnd == "2026-12-31", "Coverage range survives storage")

        print("PASS: schedule, boundary, weekend, holiday, multi-day countdown, local-time, rate, formatting, balance-schema and request checks")
    }
}
