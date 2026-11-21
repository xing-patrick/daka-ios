import Foundation

/// 与 Android 版 `util/Dates.kt` 一一对应。
///
/// 全项目统一约定：dayIndex 0 = 周一 ... 6 = 周日，对应 daysMask 的第 0..6 位。
/// epochDay 是「本地日期」的天序号（1970-01-01 = 0），不是时间戳除以 86400 ——
/// 后者在东八区会差一天，所以这里先取本地年月日，再按 UTC 算天数。
enum Dates {

    static let allDays = 0x7F      // 1111111
    static let weekdays = 0x1F     // 周一到周五
    static let weekend = 0x60      // 周六周日
    static let notScheduled = -1

    private static let cnDays = ["一", "二", "三", "四", "五", "六", "日"]
    private static let cnWeek = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 固定 UTC 的格里高利历，只用来做「日期 ↔ 天序号」换算，不受设备时区影响
    static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    // MARK: - 天序号换算

    static func epochDay(of date: Date) -> Int {
        let local = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let utc = utcCalendar.date(from: DateComponents(
            year: local.year, month: local.month, day: local.day
        )) else { return 0 }
        return Int((utc.timeIntervalSince1970 / 86_400).rounded())
    }

    static func todayEpochDay() -> Int { epochDay(of: Date()) }

    /// 天序号 → 那天本地零点
    static func date(epochDay: Int) -> Date {
        let utc = Date(timeIntervalSince1970: Double(epochDay) * 86_400)
        let c = utcCalendar.dateComponents([.year, .month, .day], from: utc)
        return Calendar.current.date(from: DateComponents(year: c.year, month: c.month, day: c.day)) ?? utc
    }

    /// 天序号 → (月, 日)
    static func monthDay(epochDay: Int) -> (month: Int, day: Int) {
        let c = utcCalendar.dateComponents([.month, .day], from: Date(timeIntervalSince1970: Double(epochDay) * 86_400))
        return (c.month ?? 1, c.day ?? 1)
    }

    // MARK: - 星期

    /// 0 = 周一 ... 6 = 周日
    static func dayIndexOf(epochDay: Int) -> Int {
        let utc = Date(timeIntervalSince1970: Double(epochDay) * 86_400)
        // Calendar 的 weekday：1 = 周日，2 = 周一 ... 7 = 周六
        let weekday = utcCalendar.component(.weekday, from: utc)
        return (weekday + 5) % 7
    }

    static func isActive(_ mask: Int, _ dayIndex: Int) -> Bool {
        (mask >> dayIndex) & 1 == 1
    }

    /// 当前本地时间的分钟数，用来判断「今天这一条到点没有」
    static func nowMinuteOfDay(at date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func timeText(_ minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }

    // MARK: - 人话

    /// bitmask → 「每天 / 工作日 / 周一三五」
    static func weekdayText(_ mask: Int) -> String {
        let m = mask & allDays
        if m == 0 { return "不重复" }
        if m == allDays { return "每天" }
        if m == weekdays { return "工作日" }
        if m == weekend { return "周末" }
        var s = "周"
        for i in 0...6 where isActive(m, i) { s += cnDays[i] }
        return s
    }

    /// 11月4日；未安排时返回「未安排」
    static func dateText(_ epochDay: Int) -> String {
        if epochDay == notScheduled { return "未安排" }
        let (m, d) = monthDay(epochDay: epochDay)
        return "\(m)月\(d)日"
    }

    /// 11月4日 周二
    static func dateHeader(_ epochDay: Int) -> String {
        let (m, d) = monthDay(epochDay: epochDay)
        return "\(m)月\(d)日 \(cnWeek[dayIndexOf(epochDay: epochDay)])"
    }

    /// 今天 / 明天 / 昨天 / 11月4日
    static func relativeLabel(_ epochDay: Int) -> String {
        switch epochDay - todayEpochDay() {
        case 0: return "今天"
        case 1: return "明天"
        case -1: return "昨天"
        case 2: return "后天"
        case -2: return "前天"
        default: return dateText(epochDay)
        }
    }
}
