import Foundation

/// 法定节假日 / 调休补班日。与 Android 版 `data/HolidayStore.kt` 对应。
///
/// 优先级：调休补班 > 法定放假 > 按星期推。
/// 每一天最终只落在两类里：
///  - 上班日：周一至周五（含调休补班的周末），或表里没标放假的平日
///  - 休息日：其余全部（普通周末 + 法定放假 − 调休补班）
struct HolidayStore {

    enum DayType { case workday, holiday, weekendOff }

    private let store: StoreFile

    init(store: StoreFile) { self.store = store }

    var holidays: Set<Int> { Set(store.data.holidays) }
    var workdays: Set<Int> { Set(store.data.workdays) }

    func setHolidays(_ set: Set<Int>) {
        store.data.holidays = set.sorted()
        store.save()
    }

    func setWorkdays(_ set: Set<Int>) {
        store.data.workdays = set.sorted()
        store.save()
    }

    /// 合并一批数据进去。已有的保留，只补新的。返回新增条数。
    @discardableResult
    func merge(holidays newHolidays: some Sequence<Int>, workdays newWorkdays: some Sequence<Int>) -> Int {
        var h = holidays
        var w = workdays
        var added = 0
        for day in newHolidays {
            // 同一天不能既是放假又是补班，后写的补班优先
            if w.contains(day) { continue }
            if h.insert(day).inserted { added += 1 }
        }
        for day in newWorkdays {
            h.remove(day)
            if w.insert(day).inserted { added += 1 }
        }
        store.data.holidays = h.sorted()
        store.data.workdays = w.sorted()
        store.save()
        return added
    }

    func remove(day: Int) {
        var h = holidays
        var w = workdays
        h.remove(day)
        w.remove(day)
        store.data.holidays = h.sorted()
        store.data.workdays = w.sorted()
        store.save()
    }

    func clear() {
        store.data.holidays = []
        store.data.workdays = []
        store.save()
    }

    var count: Int { store.data.holidays.count + store.data.workdays.count }

    func dayType(_ day: Int) -> DayType {
        if workdays.contains(day) { return .workday }
        if holidays.contains(day) { return .holiday }
        return Dates.dayIndexOf(epochDay: day) < 5 ? .workday : .weekendOff
    }

    /// 是不是休息日：周末 + 法定放假 − 调休补班，与「上班日」严格互补
    func isRestDay(_ day: Int) -> Bool { dayType(day) != .workday }

    /// 模板的排期规则是否命中这一天
    func matches(_ mode: ScheduleMode, _ daysMask: Int, _ day: Int) -> Bool {
        switch mode {
        case .everyday: return true
        case .weekday: return Dates.dayIndexOf(epochDay: day) < 5
        case .weekend: return Dates.dayIndexOf(epochDay: day) >= 5
        case .legalWorkday: return dayType(day) == .workday
        case .legalHoliday: return isRestDay(day)
        case .custom: return Dates.isActive(daysMask, Dates.dayIndexOf(epochDay: day))
        }
    }
}
