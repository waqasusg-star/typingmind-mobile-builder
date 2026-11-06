import Foundation

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

@main struct LogicTests {
    static func main() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        func utcDate(_ hour: Int, _ minute: Int, _ second: Int = 0, dayOffset: Int = 0) -> Date {
            let base = utc.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: hour, minute: minute, second: second))!
            return base.addingTimeInterval(Double(dayOffset) * 86400)
        }

        // 1. Documented window 16:30 -> 00:30 UTC wraps midnight.
        let window = PeakWindow.seeded
        expect(window.isActive, "Seeded schedule must be active")
        expect(window.wrapsMidnight, "16:30 to 00:30 must wrap midnight")
        expect(!window.isOffPeak(at: utcDate(16, 29)), "16:29 UTC is still peak")
        expect(window.isOffPeak(at: utcDate(16, 30)), "16:30 UTC starts off-peak (inclusive start)")
        expect(window.isOffPeak(at: utcDate(23, 59, 59)), "23:59 UTC is off-peak")
        expect(window.isOffPeak(at: utcDate(0, 0)), "Midnight UTC is off-peak")
        expect(window.isOffPeak(at: utcDate(0, 29)), "00:29 UTC is off-peak")
        expect(!window.isOffPeak(at: utcDate(0, 30)), "00:30 UTC is peak (exclusive end)")
        expect(!window.isOffPeak(at: utcDate(9, 0)), "09:00 UTC is peak")
        expect(window.stateLabel(at: utcDate(18, 0)) == "OFF-PEAK", "State label reports off-peak")
        expect(window.stateLabel(at: utcDate(12, 0)) == "PEAK", "State label reports peak")

        // 2. Next transition.
        let fromMorning = window.nextTransition(after: utcDate(10, 0))
        expect(fromMorning != nil, "Transition exists during the day")
        expect(fromMorning?.becomesOffPeak == true, "Next transition from peak is off-peak")
        expect(Int(fromMorning!.date.timeIntervalSince(utcDate(10, 0))) == 6 * 3600 + 1800, "10:00 UTC to 16:30 UTC is 6h30m")

        let fromEvening = window.nextTransition(after: utcDate(20, 0))
        expect(fromEvening?.becomesOffPeak == false, "Next transition from off-peak is peak")
        expect(Int(fromEvening!.date.timeIntervalSince(utcDate(20, 0))) == 4 * 3600 + 1800, "20:00 UTC to 00:30 UTC is 4h30m")
        expect(Int(fromEvening!.date.timeIntervalSince(utcDate(20, 0, dayOffset: 1))) < 0,
               "The transition lands after midnight, not on the same day")

        let atBoundary = window.nextTransition(after: utcDate(16, 30))
        expect(atBoundary?.becomesOffPeak == false, "At the off-peak start the next change returns to peak")
        expect(Int(atBoundary!.date.timeIntervalSince(utcDate(16, 30))) == 8 * 3600, "16:30 to 00:30 is 8 hours")

        // 3. Timeline segments cover a full day and 8 hours are discounted.
        let segments = window.segments()
        expect(segments.first?.startMinute == 0, "Segments start at 00:00")
        expect(segments.last?.endMinute == 1440, "Segments end at 24:00")
        expect(window.offPeakDurationMinutes() == 480, "Off-peak window is 8 hours per day")
        for (index, segment) in segments.enumerated() where index > 0 {
            expect(segments[index - 1].endMinute == segment.startMinute, "Segments must be contiguous")
        }

        // 4. Disabled or non-wrapping schedules.
        let disabled = PeakWindow(startMinuteUTC: 990, endMinuteUTC: 30, discountEnabled: false)
        expect(!disabled.isActive, "Disabled schedule is inactive")
        expect(!disabled.isOffPeak(at: utcDate(20, 0)), "Disabled schedule never reports off-peak")
        expect(disabled.nextTransition(after: utcDate(20, 0)) == nil, "Disabled schedule has no transition")
        expect(disabled.segments().count == 1, "Disabled schedule draws one band")
        expect(disabled.stateLabel(at: utcDate(20, 0)) == "STANDARD", "Disabled schedule reports standard pricing")

        let insideDay = PeakWindow(startMinuteUTC: 600, endMinuteUTC: 900, discountEnabled: true)
        expect(!insideDay.wrapsMidnight, "10:00-15:00 does not wrap")
        expect(!insideDay.isOffPeak(at: utcDate(9, 59)), "09:59 UTC outside a daytime window")
        expect(insideDay.isOffPeak(at: utcDate(10, 0)), "10:00 UTC inside a daytime window")
        expect(insideDay.isOffPeak(at: utcDate(14, 59)), "14:59 UTC inside a daytime window")
        expect(!insideDay.isOffPeak(at: utcDate(15, 0)), "15:00 UTC outside a daytime window")
        expect(insideDay.offPeakDurationMinutes() == 300, "Daytime window is 5 hours")
        let insideNext = insideDay.nextTransition(after: utcDate(12, 0))
        expect(insideNext?.becomesOffPeak == false, "Inside a daytime window the next change is peak")
        expect(Int(insideNext!.date.timeIntervalSince(utcDate(12, 0))) == 3 * 3600, "12:00 UTC to 15:00 UTC is 3 hours")

        // 5. Rate math follows the published discounts.
        let chat = RateSeeds.models[0]
        let reasoner = RateSeeds.models[1]
        expect(chat.id == "deepseek-chat" && reasoner.id == "deepseek-reasoner", "Both seeded models are present")
        expect(abs(chat.offPeak.cacheMiss - 0.135) < 0.0001, "Chat off-peak cache miss is 50% of standard")
        expect(abs(chat.offPeak.output - 0.55) < 0.0001, "Chat off-peak output is 50% of standard")
        expect(abs(reasoner.offPeak.cacheMiss - 0.1375) < 0.0001, "Reasoner off-peak cache miss is 25% of standard")
        expect(abs(reasoner.offPeak.output - 0.5475) < 0.0001, "Reasoner off-peak output is 25% of standard")
        expect(chat.rates(offPeakActive: false).output == chat.standard.output, "Peak uses standard rates")
        expect(abs(chat.rates(offPeakActive: true).output - 0.55) < 0.0001, "Off-peak uses discounted rates")
        var wild = chat
        wild.offPeakDiscountPercent = 140
        expect(wild.clampedDiscount == 100 && abs(wild.offPeak.output) < 0.0001, "Discount is clamped to 100%")
        wild.offPeakDiscountPercent = -20
        expect(wild.clampedDiscount == 0 && wild.offPeak.output == wild.standard.output, "Negative discount is clamped to 0%")

        // 6. Number formatting.
        expect(MoneyFormat.rate(1.1) == "1.10", "Whole-dollar rates keep two decimals")
        expect(MoneyFormat.rate(0.07) == "0.07", "Small rates are trimmed")
        expect(MoneyFormat.rate(0.1375) == "0.1375", "Four decimals survive for quarter rates")
        expect(MoneyFormat.rate(0.5) == "0.500", "Mid-size values keep three decimals")
        expect(MoneyFormat.symbol(for: "CNY") == "¥", "CNY symbol")
        expect(MoneyFormat.symbol(for: "usd") == "$", "Currency codes are case insensitive")
        expect(MoneyFormat.symbol(for: "EUR") == "EUR ", "Unknown currencies fall back to the code")
        expect(MoneyFormat.amount("110.00", currency: "CNY") == "¥110.00", "Amount formatting")
        expect(MoneyFormat.amount("", currency: "USD") == "—", "Empty amount is a dash")
        expect(MoneyFormat.decimal("1,234.50") == 1234.5, "Thousand separators are ignored")

        // 7. Countdown and locale conversion.
        expect(ClockFormat.countdown(seconds: 3661) == "1h 1m", "Hour counts shorten to minutes")
        expect(ClockFormat.countdown(seconds: 90) == "1m 30s", "Minute counts keep seconds")
        expect(ClockFormat.countdown(seconds: 5) == "5s", "Sub-minute countdown")
        expect(ClockFormat.countdown(seconds: -5) == "0s", "Negative countdown clamps to zero")
        expect(ClockFormat.minuteLabel(990) == "16:30", "Minute to UTC label")
        expect(ClockFormat.minuteLabel(30) == "00:30", "Midnight minute label")
        let reference = utc.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 12))!
        expect(ClockFormat.localLabel(minuteUTC: 930, on: reference, timeZone: TimeZone(secondsFromGMT: 0)!) == "15:30",
               "15:30 UTC stays 15:30 at UTC")
        expect(ClockFormat.localLabel(minuteUTC: 930, on: reference, timeZone: TimeZone(secondsFromGMT: 5 * 3600 + 1800)!) == "21:00",
               "15:30 UTC is 21:00 at +05:30")
        expect(ClockFormat.localLabel(minuteUTC: 990, on: reference, timeZone: TimeZone(secondsFromGMT: -5 * 3600)!) == "11:30",
               "16:30 UTC is 11:30 at -05:00")

        // 8. Balance parsing of the documented payload.
        let documented = """
        {"is_available": true, "balance_infos": [{"currency": "CNY", "total_balance": "110.00", "granted_balance": "10.00", "topped_up_balance": "100.00"}]}
        """.data(using: .utf8)!
        let parsed = BalanceParser.snapshot(from: documented, at: reference)
        expect(parsed != nil, "Documented balance payload parses")
        expect(parsed?.isAvailable == true, "Availability flag is kept")
        expect(parsed?.balanceInfos.count == 1, "One balance entry")
        expect(parsed?.primary?.currency == "CNY", "Currency is upper-cased")
        expect(parsed?.primary?.total == 110.0, "Total balance parses to a number")
        expect(parsed?.primary?.granted == 10.0, "Granted balance parses")
        expect(parsed?.primary?.toppedUp == 100.0, "Topped-up balance parses")
        expect(parsed?.fetchedAt == reference, "Fetch timestamp is attached")

        let numeric = "{\"is_available\": false, \"balance_infos\": [{\"currency\": \"usd\", \"total_balance\": 0, \"granted_balance\": 0, \"topped_up_balance\": 0}]}".data(using: .utf8)!
        let numericParsed = BalanceParser.snapshot(from: numeric)
        expect(numericParsed?.isAvailable == false, "Numeric availability parses")
        expect(numericParsed?.primary?.currency == "USD", "Lowercase currency is normalised")
        expect(numericParsed?.primary?.total == 0, "Numeric balances are accepted")

        let partial = "{\"balance_infos\": [{\"currency\": \"CNY\"}]}".data(using: .utf8)!
        let partialParsed = BalanceParser.snapshot(from: partial)
        expect(partialParsed != nil, "Missing fields still parse")
        expect(partialParsed?.isAvailable == false, "Missing availability defaults to false")
        expect(partialParsed?.primary?.totalBalance == "", "Missing amount stays empty")

        let twoCurrencies = "{\"is_available\": true, \"balance_infos\": [{\"currency\": \"CNY\", \"total_balance\": \"1.00\"}, {\"currency\": \"USD\", \"total_balance\": \"2.00\"}]}".data(using: .utf8)!
        expect(BalanceParser.snapshot(from: twoCurrencies)?.primary?.currency == "USD", "USD is preferred when both currencies are returned")

        expect(BalanceParser.snapshot(from: "not json".data(using: .utf8)!) == nil, "Invalid JSON is rejected")

        // 9. HTTP status mapping used by the client.
        expect(DeepSeekClient.error(forStatus: 200) == nil, "200 is success")
        expect(DeepSeekClient.error(forStatus: 401) == .unauthorized, "401 is an auth error")
        expect(DeepSeekClient.error(forStatus: 403) == .unauthorized, "403 is an auth error")
        expect(DeepSeekClient.error(forStatus: 429) == .rateLimited, "429 is rate limiting")
        expect(DeepSeekClient.error(forStatus: 500) == .http(500), "Other statuses surface the code")
        expect(DeepSeekClient.request(apiKey: "sk-test").value(forHTTPHeaderField: "Authorization") == "Bearer sk-test",
               "The bearer token header is built correctly")
        expect(DeepSeekClient.balanceURL.absoluteString == "https://api.deepseek.com/user/balance", "Balance endpoint is HTTPS")

        print("PASS: 56 schedule, rate, formatting, balance-parsing and request checks; not an app/UI/device suite")
    }
}
