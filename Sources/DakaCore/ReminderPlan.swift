import Foundation

/// 一条「将来要响一次的提醒」。
///
/// iOS 侧一条待发通知就是一条 `PlannedReminder`，标识固定为
/// `daka.<epochDay>.<taskId>`，重排时靠这个 id 覆盖，不会越滚越多。
struct PlannedReminder: Equatable {
    var identifier: String
    var day: Int
    var taskId: String
    var name: String
    var minuteOfDay: Int
    /// 这一条该怎么显示成一句话，与 Android 版的 `ruleText` 对齐
    var ruleText: String
    var fireDate: Date
    var sound: Bool
    var vibrate: Bool
}

/// 排期计算：只做「该在什么时候响什么」，不碰任何系统 API。
///
/// Android 版是给每条任务挂一个精确闹钟，没有数量上限；iOS 的
/// `UNUserNotificationCenter` 最多只保留 64 条待发通知，所以这里必须
/// 按时间排序后截断，并靠「每次进前台重排」把窗口往前滚。
enum ReminderPlanner {

    /// 往后排几天。Android 版是 8 天，这里保持一致。
    static let daysAhead = 8

    /// iOS 待发通知硬上限 64 条，留 4 条余量给「稍后」和临时通知。
    static let maxPending = 60

    static func identifier(day: Int, taskId: String) -> String {
        "daka.\(day).\(taskId)"
    }

    /// 按天展开、过滤、排序、截断。
    ///
    /// - 只排「还没到点、也没结束」的：打过卡、判定失败的都不排
    /// - 过去时刻一律跳过（重排发生在 App 启动和回前台时，可能已经过点了）
    /// - 结果按触发时间升序，截到 `limit` 条
    static func plan(
        store: TaskStore,
        today: Int = Dates.todayEpochDay(),
        now: Date = Date(),
        limit: Int = ReminderPlanner.maxPending,
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        var out: [PlannedReminder] = []

        for offset in 0...daysAhead {
            let day = today + offset
            // entriesFor 会顺带把重复模板展开成这一天的实例
            for task in store.entriesFor(day) {
                if task.settled { continue }
                guard let fire = fireDate(day: day, minuteOfDay: task.minuteOfDay, calendar: calendar) else {
                    continue
                }
                if fire <= now { continue }
                out.append(
                    PlannedReminder(
                        identifier: identifier(day: day, taskId: task.id),
                        day: day,
                        taskId: task.id,
                        name: task.name,
                        minuteOfDay: task.minuteOfDay,
                        ruleText: Dates.timeText(task.minuteOfDay),
                        fireDate: fire,
                        sound: task.sound,
                        vibrate: task.vibrate
                    )
                )
            }
        }

        out.sort { $0.fireDate < $1.fireDate }
        return Array(out.prefix(max(0, limit)))
    }

    /// 某天第几分钟对应的绝对时刻
    static func fireDate(day: Int, minuteOfDay: Int, calendar: Calendar = .current) -> Date? {
        let midnight = Dates.date(epochDay: day)
        var comps = DateComponents()
        comps.hour = minuteOfDay / 60
        comps.minute = minuteOfDay % 60
        comps.second = 0
        return calendar.date(byAdding: comps, to: midnight)
    }
}
