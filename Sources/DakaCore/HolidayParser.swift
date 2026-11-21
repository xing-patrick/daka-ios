import Foundation

/// 手动粘贴导入节假日 / 调休，对应 Android 版 `data/HolidayParser.kt`。
///
/// 支持的写法（一行一条）：
///
///     10月1日 休
///     2026-10-01 放假
///     10/1-10/7 休          <- 区间，整段都标成放假
///     10月11日 班           <- 调休补班
///     10.1~10.7 放假
///
/// 不写「班 / 补班 / 上班」就默认按放假处理。
/// 不写年份时用今年；如果这个日子已经过去半年以上，自动算到明年。
enum HolidayParser {

    struct Result {
        var holidays: Set<Int> = []
        var workdays: Set<Int> = []
        var failed: [String] = []
    }

    /// (年)? 月 分隔符 日
    private static let reDate = try! NSRegularExpression(
        pattern: #"(?:(\d{4})\s*[-/.]\s*)?(\d{1,2})\s*(?:月|[-/.])\s*(\d{1,2})\s*日?"#
    )
    private static let reRangeHint = try! NSRegularExpression(pattern: #"[~～—－–至到]"#)

    static func parse(_ text: String, today: Int = Dates.todayEpochDay()) -> Result {
        var result = Result()
        let (todayYear, _) = yearMonth(ofEpochDay: today)

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") || line.hasPrefix("//") { continue }

            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)
            let matches = Self.reDate.matches(in: line, range: full)
            if matches.isEmpty {
                result.failed.append(line)
                continue
            }

            var days: [Int] = []
            for m in matches {
                let yearText = m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1))
                let monthText = ns.substring(with: m.range(at: 2))
                let dayText = ns.substring(with: m.range(at: 3))
                guard let month = Int(monthText), let day = Int(dayText),
                      (1...12).contains(month), (1...31).contains(day) else { continue }
                let year = Int(yearText) ?? pickYear(month: month, day: day, todayYear: todayYear, today: today)
                if let epoch = makeEpochDay(year: year, month: month, day: day) {
                    days.append(epoch)
                }
            }
            if days.isEmpty {
                result.failed.append(line)
                continue
            }

            let isWork = line.contains("班") || line.contains("补班")
                || line.contains("上班") || line.contains("调休上")

            let hasRangeHint = Self.reRangeHint.firstMatch(in: line, range: full) != nil
            if days.count >= 2 && (hasRangeHint || line.contains("-")) {
                let a = days.min()!, b = days.max()!
                // 最多铺 40 天，避免脏数据把整年填满
                if b - a <= 40 {
                    for d in a...b {
                        if isWork { result.workdays.insert(d) } else { result.holidays.insert(d) }
                    }
                } else {
                    result.failed.append(line)
                }
            } else {
                for d in days {
                    if isWork { result.workdays.insert(d) } else { result.holidays.insert(d) }
                }
            }
        }

        // 同一天既放假又补班时，补班优先
        result.holidays.subtract(result.workdays)
        return result
    }

    private static func pickYear(month: Int, day: Int, todayYear: Int, today: Int) -> Int {
        guard let thisYear = makeEpochDay(year: todayYear, month: month, day: day) else { return todayYear }
        return thisYear < today - 180 ? todayYear + 1 : todayYear
    }

    private static func makeEpochDay(year: Int, month: Int, day: Int) -> Int? {
        var comps = DateComponents(year: year, month: month, day: day)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        guard let date = Dates.utcCalendar.date(from: comps) else { return nil }
        // 校验没被自动进位（例如 2月30日）
        let c = Dates.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard c.year == year, c.month == month, c.day == day else { return nil }
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }

    private static func yearMonth(ofEpochDay day: Int) -> (year: Int, month: Int) {
        let utc = Date(timeIntervalSince1970: Double(day) * 86_400)
        let c = Dates.utcCalendar.dateComponents([.year, .month], from: utc)
        return (c.year ?? 1970, c.month ?? 1)
    }
}
