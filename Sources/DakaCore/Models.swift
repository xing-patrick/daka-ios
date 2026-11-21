import Foundation

/// 模板类型：repeating 按规则自动展开；once 不指定日期，由用户主动添加
enum TemplateKind: String, Codable {
    case repeating = "REPEAT"
    case once = "ONCE"
}

/// 重复模板的排期规则，语义与 Android 版完全一致。
///
/// - everyday      每天
/// - weekday       周一至周五（纯星期，不看节假日）
/// - weekend       周六周日（纯星期，不看节假日）
/// - legalWorkday  法定上班日：周一至周五 − 法定节假日 + 调休补班日
/// - legalHoliday  休息日：周末 + 法定节假日 − 调休补班日（与 legalWorkday 严格互补）
/// - custom        自己勾星期，用 daysMask
enum ScheduleMode: String, Codable, CaseIterable {
    case everyday = "EVERYDAY"
    case weekday = "WEEKDAY"
    case weekend = "WEEKEND"
    case legalWorkday = "LEGAL_WORKDAY"
    case legalHoliday = "LEGAL_HOLIDAY"
    case custom = "CUSTOM"

    func label(daysMask: Int) -> String {
        switch self {
        case .everyday: return "每天"
        case .weekday: return "工作日"
        case .weekend: return "周末"
        case .legalWorkday: return "法定上班日"
        case .legalHoliday: return "休息日"
        case .custom: return Dates.weekdayText(daysMask)
        }
    }
}

/// 任务库里的模板。模板不隶属任何日期，也不带完成状态。
struct TaskTemplate: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var minuteOfDay: Int
    var kind: TemplateKind = .repeating
    var scheduleMode: ScheduleMode = .everyday
    /// custom 用：星期 bitmask
    var daysMask: Int = Dates.allDays
    var createdEpochDay: Int = Dates.todayEpochDay()
    /// 到点是否出声
    var sound: Bool = true
    /// 到点是否震动
    var vibrate: Bool = true

    var hour: Int { minuteOfDay / 60 }
    var minute: Int { minuteOfDay % 60 }
    var timeText: String { Dates.timeText(minuteOfDay) }

    var ruleText: String {
        kind == .repeating ? scheduleMode.label(daysMask: daysMask) : "单次任务"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, mode, days, created, sound = "s", vibrate = "v"
        case minuteOfDay = "min"
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        minuteOfDay: Int,
        kind: TemplateKind = .repeating,
        scheduleMode: ScheduleMode = .everyday,
        daysMask: Int = Dates.allDays,
        createdEpochDay: Int = Dates.todayEpochDay(),
        sound: Bool = true,
        vibrate: Bool = true
    ) {
        self.id = id
        self.name = name
        self.minuteOfDay = minuteOfDay
        self.kind = kind
        self.scheduleMode = scheduleMode
        self.daysMask = daysMask
        self.createdEpochDay = createdEpochDay
        self.sound = sound
        self.vibrate = vibrate
    }

    /// 兼容 Android 版存下来的 JSON：字段名一致，缺字段一律走默认值
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        id = rawId.isEmpty ? UUID().uuidString : rawId
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        minuteOfDay = try c.decodeIfPresent(Int.self, forKey: .minuteOfDay) ?? 480
        let rawKind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "REPEAT"
        kind = TemplateKind(rawValue: rawKind) ?? .repeating
        let mask = try c.decodeIfPresent(Int.self, forKey: .days) ?? Dates.allDays
        if let rawMode = try c.decodeIfPresent(String.self, forKey: .mode) {
            scheduleMode = ScheduleMode(rawValue: rawMode) ?? .everyday
        } else {
            // 没有 mode 字段的老数据：按 mask 反推一个等价规则
            scheduleMode = TaskTemplate.modeFromMask(mask)
        }
        daysMask = mask
        createdEpochDay = try c.decodeIfPresent(Int.self, forKey: .created) ?? Dates.todayEpochDay()
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        vibrate = try c.decodeIfPresent(Bool.self, forKey: .vibrate) ?? true
    }

    /// 字段名与 Android 版 `TaskTemplate.toJson()` 完全一致，方便两边互导数据
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(minuteOfDay, forKey: .minuteOfDay)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(scheduleMode.rawValue, forKey: .mode)
        try c.encode(daysMask, forKey: .days)
        try c.encode(createdEpochDay, forKey: .created)
        try c.encode(sound, forKey: .sound)
        try c.encode(vibrate, forKey: .vibrate)
    }

    static func modeFromMask(_ mask: Int) -> ScheduleMode {
        switch mask & Dates.allDays {
        case Dates.allDays: return .everyday
        case Dates.weekdays: return .weekday
        case Dates.weekend: return .weekend
        default: return .custom
        }
    }
}

/// 某一天里的一条任务实例。
///
/// - templateId 为空 = 用户直接在这天新建的临时任务
/// - removed     = 墓碑：用户把这条从这天移除了，不再被模板自动补回来
/// - customized  = 用户手动改过，之后改模板不再覆盖它
/// - auto        = 由重复模板自动展开出来的；规则变了才会被自动撤掉
/// - doneAt      = 实际打卡时刻（当天第几分钟），提前/延后都记真实时间
/// - snoozeCount = 已经点过几次「稍后 10 分钟」
/// - failed      = 延迟次数用尽仍未完成，判定打卡失败：不再提醒、列表置灰，仍可补卡
struct DayTask: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var templateId: String = ""
    var name: String
    var minuteOfDay: Int
    var done: Bool = false
    var removed: Bool = false
    var customized: Bool = false
    var auto: Bool = false
    var sound: Bool = true
    var vibrate: Bool = true
    var doneAt: Int = -1
    var snoozeCount: Int = 0
    var failed: Bool = false

    /// 显示用的时间：打过卡就显示实际打卡时间
    var displayMinute: Int { (done && doneAt >= 0) ? doneAt : minuteOfDay }
    var timeText: String { Dates.timeText(displayMinute) }
    /// 原定时间，用于「原定 08:00」
    var plannedTimeText: String { Dates.timeText(minuteOfDay) }
    /// 实际打卡时间和原定时间不一致（提前或延后）
    var timeShifted: Bool { done && doneAt >= 0 && doneAt != minuteOfDay }
    /// 已经结束（打卡成功或判失败），不再需要排提醒
    var settled: Bool { done || failed }

    enum CodingKeys: String, CodingKey {
        case id, name, done, removed, auto, failed
        case templateId = "tpl"
        case minuteOfDay = "min"
        case customized = "custom"
        case sound = "s"
        case vibrate = "v"
        case doneAt = "dat"
        case snoozeCount = "snz"
    }

    init(
        id: String = UUID().uuidString,
        templateId: String = "",
        name: String,
        minuteOfDay: Int,
        done: Bool = false,
        removed: Bool = false,
        customized: Bool = false,
        auto: Bool = false,
        sound: Bool = true,
        vibrate: Bool = true,
        doneAt: Int = -1,
        snoozeCount: Int = 0,
        failed: Bool = false
    ) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.minuteOfDay = minuteOfDay
        self.done = done
        self.removed = removed
        self.customized = customized
        self.auto = auto
        self.sound = sound
        self.vibrate = vibrate
        self.doneAt = doneAt
        self.snoozeCount = snoozeCount
        self.failed = failed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        id = rawId.isEmpty ? UUID().uuidString : rawId
        templateId = try c.decodeIfPresent(String.self, forKey: .templateId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        minuteOfDay = try c.decodeIfPresent(Int.self, forKey: .minuteOfDay) ?? 480
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        removed = try c.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        customized = try c.decodeIfPresent(Bool.self, forKey: .customized) ?? false
        auto = try c.decodeIfPresent(Bool.self, forKey: .auto) ?? false
        sound = try c.decodeIfPresent(Bool.self, forKey: .sound) ?? true
        vibrate = try c.decodeIfPresent(Bool.self, forKey: .vibrate) ?? true
        doneAt = try c.decodeIfPresent(Int.self, forKey: .doneAt) ?? -1
        snoozeCount = try c.decodeIfPresent(Int.self, forKey: .snoozeCount) ?? 0
        failed = try c.decodeIfPresent(Bool.self, forKey: .failed) ?? false
    }

    /// 用得上才写，跟 Android 版一样保持文件精简
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(templateId, forKey: .templateId)
        try c.encode(name, forKey: .name)
        try c.encode(minuteOfDay, forKey: .minuteOfDay)
        try c.encode(done, forKey: .done)
        try c.encode(removed, forKey: .removed)
        try c.encode(customized, forKey: .customized)
        try c.encode(auto, forKey: .auto)
        try c.encode(sound, forKey: .sound)
        try c.encode(vibrate, forKey: .vibrate)
        if doneAt >= 0 { try c.encode(doneAt, forKey: .doneAt) }
        if snoozeCount > 0 { try c.encode(snoozeCount, forKey: .snoozeCount) }
        if failed { try c.encode(true, forKey: .failed) }
    }
}
