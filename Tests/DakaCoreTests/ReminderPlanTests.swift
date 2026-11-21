import XCTest

#if canImport(DakaCore)
@testable import DakaCore
#else
@testable import Daka
#endif

final class ReminderPlanTests: XCTestCase {

    private let today = Dates.todayEpochDay()

    private func makeStore() -> TaskStore { TaskStore.inMemory() }

    /// 今天某个时刻，作为「现在」喂给 planner
    private func todayAt(_ hour: Int, _ minute: Int) -> Date {
        ReminderPlanner.fireDate(day: today, minuteOfDay: hour * 60 + minute)!
    }

    // MARK: - 基本展开

    func testFireDateUsesThatDayAndTime() {
        let fire = ReminderPlanner.fireDate(day: today, minuteOfDay: 7 * 60 + 5)!
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: fire)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 5)
        XCTAssertEqual(comps.second, 0)
    }

    func testPlansAcrossTheWholeWindow() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        // 现在 06:00，今天 07:00 还没到
        let list = ReminderPlanner.plan(store: store, today: today, now: todayAt(6, 0), limit: 999)
        // 每天一条 × (今天 + 往后 8 天)
        XCTAssertEqual(list.count, ReminderPlanner.daysAhead + 1)
        XCTAssertEqual(list.first?.day, today)
        XCTAssertTrue(list.allSatisfy { $0.name == "早起" })
    }

    func testSkipsTodaysPastReminder() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        // 现在 08:00，今天这条已经过点
        let list = ReminderPlanner.plan(store: store, today: today, now: todayAt(8, 0), limit: 999)
        XCTAssertEqual(list.count, ReminderPlanner.daysAhead, "今天那条不该再排")
        XCTAssertFalse(list.contains { $0.day == today })
    }

    func testSortedByFireTime() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "睡前阅读", minuteOfDay: 22 * 60 + 30))
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let list = ReminderPlanner.plan(store: store, today: today, now: todayAt(6, 0), limit: 999)
        XCTAssertEqual(list.first?.name, "早起")
        for i in 1..<list.count {
            XCTAssertLessThanOrEqual(list[i - 1].fireDate, list[i].fireDate)
        }
    }

    // MARK: - 过滤

    func testSkipsDoneAndFailed() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let task = store.entriesFor(today)[0]
        store.setDone(day: today, id: task.id, done: true, now: 6 * 60)

        let list = ReminderPlanner.plan(store: store, today: today, now: todayAt(5, 0), limit: 999)
        XCTAssertFalse(list.contains { $0.day == today }, "打过卡的今天不该再提醒")
        XCTAssertEqual(list.count, ReminderPlanner.daysAhead)
    }

    func testSkipsFailed() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let task = store.entriesFor(today)[0]
        store.markFailed(day: today, id: task.id)

        let list = ReminderPlanner.plan(store: store, today: today, now: todayAt(5, 0), limit: 999)
        XCTAssertFalse(list.contains { $0.day == today })
    }

    // MARK: - 截断

    func testRespectsLimitAndKeepsEarliest() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        store.upsertTemplate(TaskTemplate(name: "午休", minuteOfDay: 13 * 60))
        store.upsertTemplate(TaskTemplate(name: "睡前", minuteOfDay: 22 * 60))

        let all = ReminderPlanner.plan(store: store, today: today, now: todayAt(6, 0), limit: 999)
        let capped = ReminderPlanner.plan(store: store, today: today, now: todayAt(6, 0), limit: 5)

        XCTAssertEqual(capped.count, 5)
        XCTAssertEqual(capped.map(\.identifier), Array(all.prefix(5)).map(\.identifier))
    }

    func testDefaultLimitLeavesRoomForSnooze() {
        // iOS 待发通知上限 64，留 4 条余量
        XCTAssertEqual(ReminderPlanner.maxPending, 60)
        XCTAssertLessThan(ReminderPlanner.maxPending, 64)
    }

    // MARK: - 标识

    func testIdentifierIsStablePerDayAndTask() {
        let a = ReminderPlanner.identifier(day: 20000, taskId: "abc")
        XCTAssertEqual(a, "daka.20000.abc")
        XCTAssertEqual(a, ReminderPlanner.identifier(day: 20000, taskId: "abc"))
        XCTAssertNotEqual(a, ReminderPlanner.identifier(day: 20001, taskId: "abc"))
        XCTAssertTrue(a.hasPrefix("daka."))
        XCTAssertFalse(a.hasPrefix("daka.snooze."), " snooze 前缀要留给稍后提醒，不能混")
    }

    // MARK: - 与单个模板的联动

    func testOnlyScheduledDaysArePlanned() {
        let store = makeStore()
        // 只在周一提醒
        store.upsertTemplate(TaskTemplate(name: "周会", minuteOfDay: 10 * 60,
                                          scheduleMode: .custom, daysMask: 0b0000001))
        let list = ReminderPlanner.plan(store: store, today: today, now: todayAt(0, 0), limit: 999)
        for item in list {
            XCTAssertEqual(Dates.dayIndexOf(epochDay: item.day), 0, "只该排周一")
        }
    }

    func testOnceTemplateIsNotAutoPlanned() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "买牛奶", minuteOfDay: 18 * 60, kind: .once))
        let list = ReminderPlanner.plan(store: store, today: today, now: todayAt(0, 0), limit: 999)
        XCTAssertTrue(list.isEmpty, "单日模板不自动展开，也就不该自动排提醒")
    }
}
