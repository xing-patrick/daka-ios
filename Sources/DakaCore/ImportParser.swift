import Foundation

/// 批量导入解析器，逐条对应 Android 版 `data/ImportParser.kt`。
///
/// 一行一条，格式「名称 时间 规则」。规则用关键词明确指定，不靠猜星期：
///
///     早起 07:00 每天           -> 重复 · 每天
///     喝水 09:30 工作日         -> 重复 · 工作日
///     游泳 15:00 周末           -> 重复 · 周末
///     阅读 21:00 一三五         -> 重复 · 自定义星期
///     跑步 20:00 1-5            -> 重复 · 周一到周五
///     收邮件 09:00 法定上班日    -> 重复 · 跳过法定节假日，调休补班也提醒
///     大扫除 10:00 休息日        -> 重复 · 周末 + 法定假都提醒，调休补班不提醒
///     买牛奶 18:00 单日          -> 单日模板（不指定日期）
///     牙医 10:00 11月8日         -> 单日模板（日期只用于判定，不绑定）
///     早睡 23:00                -> 不写规则默认每天
///     冥想                      -> 不写时间默认 08:00、每天
///
/// 规则看不懂的行会列为「无法识别」，不会悄悄变成每天。
/// 以 # 或 // 开头的行视为注释跳过。
enum ImportParser {

    struct Result {
        var items: [TaskTemplate] = []
        var failed: [String] = []
    }

    struct Rule {
        var kind: TemplateKind
        var mode: ScheduleMode
        var mask: Int
    }

    // MARK: - 正则

    private static let reTimeColon = try! NSRegularExpression(pattern: #"(\d{1,2})\s*[:：]\s*(\d{1,2})"#)
    private static let reTimeCN = try! NSRegularExpression(pattern: #"(\d{1,2})\s*[点时]\s*(?:(\d{1,2})\s*分?)?"#)

    private static let reDateCN = try! NSRegularExpression(pattern: #"(\d{1,2})\s*月\s*(\d{1,2})\s*日?"#)
    private static let reDateSlash = try! NSRegularExpression(pattern: #"(\d{1,2})\s*/\s*(\d{1,2})"#)

    private static let reEvery = try! NSRegularExpression(
        pattern: #"每天|每日|天天|每一天|日日|every\s*day|daily"#,
        options: [.caseInsensitive]
    )
    private static let reRange = try! NSRegularExpression(
        pattern: #"[周星期礼拜]{0,2}\s*([一二三四五六日天])\s*(?:至|到|-|~|—|－)\s*[周星期礼拜]{0,2}\s*([一二三四五六日天])"#
    )
    private static let reRangeNum = try! NSRegularExpression(
        pattern: #"([1-7])\s*(?:至|到|-|~|—)\s*([1-7])"#
    )
    private static let rePrefixed = try! NSRegularExpression(pattern: #"(?:周|星期|礼拜)\s*([一二三四五六日天])"#)
    private static let reNumber = try! NSRegularExpression(pattern: #"(?<![\d:：])([1-7])(?![\d:：])"#)

    private static let separators: Set<Character> = [
        "，", ",", "、", "-", "–", ":", "：", "|", "/", "\\", "\t", "。", ";", "；"
    ]

    private static let cnHeads: [Character: Int] = [
        "一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6
    ]

    /// 明确写「只做一次」的词，优先于任何星期判定
    private static let kOnce = ["单日", "单次", "仅一次", "只做一次", "不重复", "单天", "单次日"]
    /// 休息日（周末 + 法定假 − 调休补班）
    private static let kLegalHoliday = [
        "休息日", "休息", "法定节假日", "法定假日", "法定假期", "法定节假", "法定假",
        "节假日", "休假日", "假期", "放假"
    ]
    /// 法定上班日（含调休补班）
    private static let kLegalWorkday = [
        "法定工作日", "法定上班日", "法定上班", "法定班", "调休", "补班", "按法定"
    ]
    private static let kWeekday = ["工作日", "平日", "上班日"]
    private static let kWeekend = ["周末", "双休"]

    // MARK: - 入口

    static func parse(_ text: String) -> Result {
        var result = Result()
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") || line.hasPrefix("//") { continue }
            if let item = parseLine(line) {
                result.items.append(item)
            } else {
                result.failed.append(line)
            }
        }
        return result
    }

    static func parseLine(_ line: String) -> TaskTemplate? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        let colon = Self.reTimeColon.firstMatch(in: line, range: full)
        let cn = Self.reTimeCN.firstMatch(in: line, range: full)

        let match: NSTextCheckingResult?
        if let c = colon, let n = cn {
            match = c.range.location <= n.range.location ? c : n
        } else {
            match = colon ?? cn
        }

        var name: String
        var ruleText: String
        var minuteOfDay: Int

        if let match {
            let hourText = ns.substring(with: match.range(at: 1))
            guard let hour = Int(hourText) else { return nil }
            var minute = 0
            if match.numberOfRanges > 2 {
                let minuteRange = match.range(at: 2)
                if minuteRange.location != NSNotFound {
                    let minuteText = ns.substring(with: minuteRange)
                    if !minuteText.isEmpty {
                        guard let m = Int(minuteText) else { return nil }
                        minute = m
                    }
                }
            }
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

            name = ns.substring(to: match.range.location)
            ruleText = ns.substring(from: match.range.location + match.range.length)
            minuteOfDay = hour * 60 + minute
        } else {
            name = line
            ruleText = ""
            minuteOfDay = 8 * 60
        }

        name = trimSeparators(name)
        if name.isEmpty { return nil }
        if name.count > 40 { name = String(name.prefix(40)) }

        guard let rule = parseRule(ruleText) else { return nil }

        return TaskTemplate(
            name: name,
            minuteOfDay: minuteOfDay,
            kind: rule.kind,
            scheduleMode: rule.mode,
            daysMask: rule.mask
        )
    }

    /// 关键词优先、明确匹配。返回 nil 表示规则看不懂，交给上层标「无法识别」。
    static func parseRule(_ raw: String) -> Rule? {
        var t = raw.trimmingCharacters(in: .whitespaces)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: ",，、|"))
        t = t.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            return Rule(kind: .repeating, mode: .everyday, mask: Dates.allDays)
        }

        // 1) 单日 / 单次
        if Self.kOnce.contains(where: { t.contains($0) }) {
            return Rule(kind: .once, mode: .everyday, mask: Dates.allDays)
        }
        // 2) 法定节假日（放在「工作日」之前，避免「法定工作日」被截胡）
        if Self.kLegalHoliday.contains(where: { t.contains($0) }) {
            return Rule(kind: .repeating, mode: .legalHoliday, mask: 0)
        }
        // 3) 法定上班日 / 调休补班
        if Self.kLegalWorkday.contains(where: { t.contains($0) }) {
            return Rule(kind: .repeating, mode: .legalWorkday, mask: Dates.weekdays)
        }
        // 4) 写了具体日期也当单日模板
        if hasDateToken(t) {
            return Rule(kind: .once, mode: .everyday, mask: Dates.allDays)
        }
        // 5) 每天
        if Self.reEvery.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil {
            return Rule(kind: .repeating, mode: .everyday, mask: Dates.allDays)
        }
        // 6) 工作日 / 周末
        if Self.kWeekday.contains(where: { t.contains($0) }) {
            return Rule(kind: .repeating, mode: .weekday, mask: Dates.weekdays)
        }
        if Self.kWeekend.contains(where: { t.contains($0) }) {
            return Rule(kind: .repeating, mode: .weekend, mask: Dates.weekend)
        }
        // 7) 自定义星期
        let mask = parseDays(t)
        if mask != 0 {
            return Rule(kind: .repeating, mode: .custom, mask: mask)
        }
        // 8) 看不懂：宁可标失败，也不悄悄变成每天
        return nil
    }

    static func hasDateToken(_ t: String) -> Bool {
        let ns = t as NSString
        let full = NSRange(location: 0, length: ns.length)
        return Self.reDateCN.firstMatch(in: t, range: full) != nil
            || Self.reDateSlash.firstMatch(in: t, range: full) != nil
    }

    /// 只用来判断某条是不是「单日模板」：识别「11月8日」/「12/20」，返回天序号
    static func parseDate(_ raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let ns = t as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = Self.reDateCN.firstMatch(in: t, range: full)
            ?? Self.reDateSlash.firstMatch(in: t, range: full) else { return nil }
        guard let month = Int(ns.substring(with: m.range(at: 1))),
              let day = Int(ns.substring(with: m.range(at: 2))),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        let today = Dates.todayEpochDay()
        let (ty, _) = yearMonth(ofEpochDay: today)
        var date = Calendar.current.date(from: DateComponents(year: ty, month: month, day: day))
        if date == nil {
            date = Dates.utcCalendar.date(from: DateComponents(year: ty, month: month, day: day))
        }
        guard let date else { return nil }
        var epoch = Dates.epochDay(of: date)
        if epoch < today {
            if let next = Calendar.current.date(from: DateComponents(year: ty + 1, month: month, day: day)) {
                epoch = Dates.epochDay(of: next)
            }
        }
        return epoch
    }

    private static func yearMonth(ofEpochDay day: Int) -> (year: Int, month: Int) {
        let utc = Date(timeIntervalSince1970: Double(day) * 86_400)
        let c = Dates.utcCalendar.dateComponents([.year, .month], from: utc)
        return (c.year ?? 1970, c.month ?? 1)
    }

    /// 解析出星期 bitmask；识别不了返回 0
    static func parseDays(_ raw: String) -> Int {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return Dates.allDays }
        let ns = t as NSString
        let full = NSRange(location: 0, length: ns.length)

        if Self.reEvery.firstMatch(in: t, range: full) != nil { return Dates.allDays }
        if Self.kWeekday.contains(where: { t.contains($0) }) { return Dates.weekdays }
        if Self.kWeekend.contains(where: { t.contains($0) }) { return Dates.weekend }

        var mask = 0

        for m in Self.reRange.matches(in: t, range: full) {
            guard let a = Self.cnHeads[Character(ns.substring(with: m.range(at: 1)))],
                  let b = Self.cnHeads[Character(ns.substring(with: m.range(at: 2)))] else { continue }
            if a <= b {
                for i in a...b { mask |= (1 << i) }
            } else {
                mask |= (1 << a) | (1 << b)
            }
        }

        for m in Self.reRangeNum.matches(in: t, range: full) {
            guard let a1 = Int(ns.substring(with: m.range(at: 1))),
                  let b1 = Int(ns.substring(with: m.range(at: 2))) else { continue }
            let a = a1 - 1, b = b1 - 1
            guard (0...6).contains(a), (0...6).contains(b) else { continue }
            if a <= b {
                for i in a...b { mask |= (1 << i) }
            } else {
                mask |= (1 << a) | (1 << b)
            }
        }

        for m in Self.rePrefixed.matches(in: t, range: full) {
            if let idx = Self.cnHeads[Character(ns.substring(with: m.range(at: 1)))] {
                mask |= (1 << idx)
            }
        }

        for m in Self.reNumber.matches(in: t, range: full) {
            guard let n = Int(ns.substring(with: m.range(at: 1))) else { continue }
            let idx = n - 1
            if (0...6).contains(idx) { mask |= (1 << idx) }
        }

        // 裸汉字连写：一三五 / 二四六。必须整串都是星期汉字才认，
        // 否则「单日」「节假日」里的「日」会被误当成周日。
        var compact = t.replacingOccurrences(of: #"(周|星期|礼拜)"#, with: "", options: .regularExpression)
        compact = compact.filter { !$0.isWhitespace && !Self.separators.contains($0) }
        if !compact.isEmpty && compact.allSatisfy({ Self.cnHeads[$0] != nil }) {
            for ch in compact {
                if let idx = Self.cnHeads[ch] { mask |= (1 << idx) }
            }
        }

        return mask & Dates.allDays
    }

    private static func trimSeparators(_ s: String) -> String {
        var chars = Array(s)
        while let f = chars.first, separators.contains(f) || f.isWhitespace { chars.removeFirst() }
        while let l = chars.last, separators.contains(l) || l.isWhitespace { chars.removeLast() }
        return String(chars)
    }
}
