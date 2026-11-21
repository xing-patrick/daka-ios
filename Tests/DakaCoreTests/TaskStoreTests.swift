import XCTest

#if canImport(DakaCore)
@testable import DakaCore
#else
@testable import Daka
#endif

final class TaskStoreTests: XCTestCase {

    private let today = Dates.todayEpochDay()

    private func epoch(_ y: Int, _ m: Int, _ d: Int) -> Int {
        var comps = DateComponents(year: y, month: m, day: d)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        let date = Dates.utcCalendar.date(from: comps)!
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }

    private func makeStore() -> TaskStore { TaskStore.inMemory() }

    // MARK: - 展开

    func testRepeatTemplateMaterializes() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60,
                                          scheduleMode: .everyday, daysMask: Dates.allDays))
        let list = store.entriesFor(today)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].name, "早起")
        XCTAssertTrue(list[0].auto)
    }

    func testOnceTemplateIsNotAutoMaterialized() {
        let store = makeStore()
        let tpl = TaskTemplate(name: "买牛奶", minuteOfDay: 18 * 60, kind: .once)
        store.upsertTemplate(tpl)
        XCTAssertTrue(store.entriesFor(today).isEmpty)

        XCTAssertTrue(store.addFromTemplate(day: today, templateId: tpl.id))
        let list = store.entriesFor(today)
        XCTAssertEqual(list.count, 1)
        XCTAssertFalse(list[0].auto, "手动加进来的不该标成 auto")
    }

    func testTombstonePreventsReAdd() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let id = store.entriesFor(today)[0].id
        store.removeInstance(day: today, id: id)

        XCTAssertTrue(store.entriesFor(today).isEmpty)
        XCTAssertTrue(store.entriesFor(today).isEmpty, "第二次打开也不能被补回来")
    }

    func testEntriesAreSortedByTime() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "睡前阅读", minuteOfDay: 22 * 60))
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let names = store.entriesFor(today).map(\.name)
        XCTAssertEqual(names, ["早起", "睡前阅读"])
    }

    // MARK: - 打卡

    func testSetDoneRecordsActualTimeAndKeepsFirst() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let id = store.entriesFor(today)[0].id

        store.setDone(day: today, id: id, done: true, now: 7 * 60 + 20)
        var t = store.findInstance(day: today, id: id)!
        XCTAssertTrue(t.done)
        XCTAssertEqual(t.doneAt, 7 * 60 + 20)
        XCTAssertTrue(t.timeShifted, "打卡时间和原定不同，应该标「原定」")
        XCTAssertEqual(t.timeText, "07:20")
        XCTAssertEqual(t.plannedTimeText, "07:00")

        // 再来一次不能刷新首次记录的时间
        store.setDone(day: today, id: id, done: true, now: 9 * 60)
        t = store.findInstance(day: today, id: id)!
        XCTAssertEqual(t.doneAt, 7 * 60 + 20)
    }

    func testUncheckRestoresPlannedTime() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let id = store.entriesFor(today)[0].id

        store.setDone(day: today, id: id, done: true, now: 8 * 60)
        store.setDone(day: today, id: id, done: false)
        let t = store.findInstance(day: today, id: id)!
        XCTAssertFalse(t.done)
        XCTAssertEqual(t.doneAt, -1)
        XCTAssertEqual(t.timeText, "07:00")
        XCTAssertFalse(t.timeShifted)
    }

    func testSnoozeThenFail() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let id = store.entriesFor(today)[0].id

        XCTAssertEqual(store.bumpSnooze(day: today, id: id), 1)
        XCTAssertEqual(store.bumpSnooze(day: today, id: id), 2)
        XCTAssertTrue(store.markFailed(day: today, id: id))

        let t = store.findInstance(day: today, id: id)!
        XCTAssertTrue(t.failed)
        XCTAssertEqual(t.snoozeCount, TaskStore.maxSnooze)
        XCTAssertTrue(t.settled)
    }

    func testDoneAfterFailClearsFailed() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        let id = store.entriesFor(today)[0].id

        store.markFailed(day: today, id: id)
        store.setDone(day: today, id: id, done: true, now: 9 * 60)
        let t = store.findInstance(day: today, id: id)!
        XCTAssertTrue(t.done)
        XCTAssertFalse(t.failed)
        XCTAssertEqual(t.snoozeCount, 0)
    }

    // MARK: - 模板传导

    func testSyncTemplateOnlyTouchesFuture() {
        let store = makeStore()
        var tpl = TaskTemplate(name: "早起", minuteOfDay: 7 * 60, createdEpochDay: today - 5)
        store.upsertTemplate(tpl)

        _ = store.entriesFor(today - 1)
        _ = store.entriesFor(today + 1)

        tpl.name = "早起喝水"
        store.upsertTemplate(tpl)
        let changed = store.syncTemplate(tpl)

        XCTAssertEqual(changed, 1, "只该改未来那天")
        XCTAssertEqual(store.rawTasks(today - 1).first?.name, "早起", "过去不动")
        XCTAssertEqual(store.rawTasks(today + 1).first?.name, "早起喝水")
    }

    func testDeleteTemplateWithSyncRemovesFutureInstances() {
        let store = makeStore()
        let tpl = TaskTemplate(name: "早起", minuteOfDay: 7 * 60, createdEpochDay: today - 5)
        store.upsertTemplate(tpl)
        _ = store.entriesFor(today - 1)
        _ = store.entriesFor(today + 1)

        let removed = store.deleteTemplateWithSync(id: tpl.id)
        XCTAssertEqual(removed, 1)
        XCTAssertNil(store.findTemplate(tpl.id))
        XCTAssertEqual(store.rawTasks(today - 1).count, 1, "过去的实例保留")
        XCTAssertTrue(store.rawTasks(today + 1).isEmpty)
    }

    // MARK: - 节假日规则

    func testLegalWorkdayRespectsMakeUpWorkday() {
        let store = makeStore()
        let saturday = epoch(2026, 11, 21)
        XCTAssertEqual(Dates.dayIndexOf(epochDay: saturday), 5, "2026-11-21 应是周六")

        store.holidays.merge(holidays: [Int](), workdays: [saturday])
        store.upsertTemplate(TaskTemplate(name: "上班", minuteOfDay: 9 * 60,
                                          scheduleMode: .legalWorkday, createdEpochDay: saturday - 30))
        store.upsertTemplate(TaskTemplate(name: "周末休息", minuteOfDay: 10 * 60,
                                          scheduleMode: .weekend, createdEpochDay: saturday - 30))

        let names = Set(store.entriesFor(saturday).map(\.name))
        XCTAssertTrue(names.contains("上班"), "调休补班的周六应算上班日")
        XCTAssertTrue(names.contains("周末休息"), "纯星期规则不看节假日表")
    }

    func testRestDayCoversHoliday() {
        let store = makeStore()
        let wednesday = epoch(2026, 11, 18)
        store.holidays.merge(holidays: [wednesday], workdays: [Int]())
        store.upsertTemplate(TaskTemplate(name: "大扫除", minuteOfDay: 10 * 60,
                                          scheduleMode: .legalHoliday, createdEpochDay: wednesday - 30))
        XCTAssertEqual(store.entriesFor(wednesday).count, 1, "法定放假的周三算休息日")
    }

    func testProgress() {
        let store = makeStore()
        store.upsertTemplate(TaskTemplate(name: "早起", minuteOfDay: 7 * 60))
        store.upsertTemplate(TaskTemplate(name: "睡前阅读", minuteOfDay: 22 * 60))
        let first = store.entriesFor(today)[0]
        store.setDone(day: today, id: first.id, done: true, now: 7 * 60)

        let p = store.progress(today)
        XCTAssertEqual(p.done, 1)
        XCTAssertEqual(p.total, 2)
    }

    // MARK: - 初始化

    func testSeed() {
        let store = makeStore()
        store.seedIfNeeded()
        XCTAssertEqual(store.templates.count, 3)
        XCTAssertTrue(store.templates.contains { $0.kind == .once })
        // 重复调用不会重复灌
        store.seedIfNeeded()
        XCTAssertEqual(store.templates.count, 3)
    }
}
