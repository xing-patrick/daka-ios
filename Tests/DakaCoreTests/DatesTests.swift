import XCTest

#if canImport(DakaCore)
@testable import DakaCore
#else
@testable import Daka
#endif

final class DatesTests: XCTestCase {

    private func epoch(_ y: Int, _ m: Int, _ d: Int) -> Int {
        var comps = DateComponents(year: y, month: m, day: d)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        let date = Dates.utcCalendar.date(from: comps)!
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }

    func testEpochDayRoundTrip() {
        let e = epoch(2026, 11, 21)
        XCTAssertEqual(Dates.epochDay(of: Dates.date(epochDay: e)), e)
        let (m, d) = Dates.monthDay(epochDay: e)
        XCTAssertEqual(m, 11)
        XCTAssertEqual(d, 21)
    }

    func testDayIndexMondayIsZero() {
        // 2026-11-16 是周一
        XCTAssertEqual(Dates.dayIndexOf(epochDay: epoch(2026, 11, 16)), 0)
        // 2026-11-21 是周六
        XCTAssertEqual(Dates.dayIndexOf(epochDay: epoch(2026, 11, 21)), 5)
        // 2026-11-22 是周日
        XCTAssertEqual(Dates.dayIndexOf(epochDay: epoch(2026, 11, 22)), 6)
    }

    func testWeekdayText() {
        XCTAssertEqual(Dates.weekdayText(Dates.allDays), "每天")
        XCTAssertEqual(Dates.weekdayText(Dates.weekdays), "工作日")
        XCTAssertEqual(Dates.weekdayText(Dates.weekend), "周末")
        XCTAssertEqual(Dates.weekdayText(0b0010101), "周一三五")
        XCTAssertEqual(Dates.weekdayText(0), "不重复")
    }

    func testDateText() {
        XCTAssertEqual(Dates.dateText(epoch(2026, 11, 4)), "11月4日")
        XCTAssertEqual(Dates.dateHeader(epoch(2026, 11, 4)), "11月4日 周三")
        XCTAssertEqual(Dates.dateText(Dates.notScheduled), "未安排")
    }

    func testRelativeLabel() {
        let today = Dates.todayEpochDay()
        XCTAssertEqual(Dates.relativeLabel(today), "今天")
        XCTAssertEqual(Dates.relativeLabel(today + 1), "明天")
        XCTAssertEqual(Dates.relativeLabel(today - 1), "昨天")
    }

    func testTimeText() {
        XCTAssertEqual(Dates.timeText(7 * 60 + 5), "07:05")
        XCTAssertEqual(Dates.timeText(23 * 60 + 59), "23:59")
    }
}

final class HolidayParserTests: XCTestCase {

    private func epoch(_ y: Int, _ m: Int, _ d: Int) -> Int {
        var comps = DateComponents(year: y, month: m, day: d)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        let date = Dates.utcCalendar.date(from: comps)!
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }

    func testSingleHoliday() {
        let r = HolidayParser.parse("2026-10-01 休")
        XCTAssertTrue(r.holidays.contains(epoch(2026, 10, 1)))
        XCTAssertTrue(r.failed.isEmpty)
    }

    func testRangeFillsAllDays() {
        let r = HolidayParser.parse("2026-10-01 - 2026-10-07 休")
        for d in 1...7 {
            XCTAssertTrue(r.holidays.contains(epoch(2026, 10, d)), "10月\(d)日缺失")
        }
    }

    func testWorkdayMarker() {
        let r = HolidayParser.parse("2026-10-11 班")
        XCTAssertTrue(r.workdays.contains(epoch(2026, 10, 11)))
        XCTAssertFalse(r.holidays.contains(epoch(2026, 10, 11)))
    }

    func testWorkdayWinsOnConflict() {
        let r = HolidayParser.parse("""
        2026-10-01 休
        2026-10-01 班
        """)
        XCTAssertTrue(r.workdays.contains(epoch(2026, 10, 1)))
        XCTAssertFalse(r.holidays.contains(epoch(2026, 10, 1)))
    }

    func testGarbageFails() {
        let r = HolidayParser.parse("随便写点啥")
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertTrue(r.holidays.isEmpty)
    }

    func testCommentsSkipped() {
        let r = HolidayParser.parse("# 国庆\n2026-10-01 休")
        XCTAssertEqual(r.failed.count, 0)
        XCTAssertEqual(r.holidays.count, 1)
    }
}
