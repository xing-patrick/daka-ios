import XCTest

#if canImport(DakaCore)
@testable import DakaCore
#else
@testable import Daka
#endif

final class ImportParserTests: XCTestCase {

    private func single(_ line: String) -> TaskTemplate? {
        let r = ImportParser.parse(line)
        XCTAssertTrue(r.failed.isEmpty, "不该被判失败：\(r.failed)")
        return r.items.first
    }

    func testDailyWithColonTime() {
        let t = single("早起 07:00 每天")
        XCTAssertEqual(t?.name, "早起")
        XCTAssertEqual(t?.minuteOfDay, 7 * 60)
        XCTAssertEqual(t?.kind, .repeating)
        XCTAssertEqual(t?.scheduleMode, .everyday)
    }

    func testWorkdayAndWeekend() {
        XCTAssertEqual(single("喝水 09:30 工作日")?.scheduleMode, .weekday)
        XCTAssertEqual(single("游泳 15:00 周末")?.scheduleMode, .weekend)
        XCTAssertEqual(single("游泳 15:00 周末")?.daysMask, 0x60)
    }

    func testCustomWeekdays() {
        // 一三五 -> bit0 + bit2 + bit4
        XCTAssertEqual(single("阅读 21:00 一三五")?.daysMask, 0b0010101)
        XCTAssertEqual(single("阅读 21:00 一三五")?.scheduleMode, .custom)
        // 1-5 -> 周一到周五
        XCTAssertEqual(single("跑步 20:00 1-5")?.daysMask, Dates.weekdays)
        // 周一,周三
        XCTAssertEqual(single("拉伸 07:30 周一,周三")?.daysMask, 0b0000101)
    }

    func testLegalDays() {
        XCTAssertEqual(single("收邮件 09:00 法定上班日")?.scheduleMode, .legalWorkday)
        XCTAssertEqual(single("大扫除 10:00 休息日")?.scheduleMode, .legalHoliday)
        // 旧写法「节假日」继续认，语义已统一为休息日
        XCTAssertEqual(single("买菜 17:00 法定节假日")?.scheduleMode, .legalHoliday)
    }

    func testOneshot() {
        XCTAssertEqual(single("买牛奶 18:00 单日")?.kind, .once)
        // 写了具体日期也是单日模板，日期本身不绑定
        XCTAssertEqual(single("牙医 10:00 11月8日")?.kind, .once)
    }

    func testDefaults() {
        let t = single("早睡 23:00")
        XCTAssertEqual(t?.minuteOfDay, 23 * 60)
        XCTAssertEqual(t?.scheduleMode, .everyday)

        let m = single("冥想")
        XCTAssertEqual(m?.name, "冥想")
        XCTAssertEqual(m?.minuteOfDay, 8 * 60)
        XCTAssertEqual(m?.scheduleMode, .everyday)
    }

    /// 文档里写明的坑：规则必须和时间写在一起，否则整行都算名称
    func testRuleWithoutTimeBecomesName() {
        let t = single("喝水 每天")
        XCTAssertEqual(t?.name, "喝水 每天")
        XCTAssertEqual(t?.minuteOfDay, 8 * 60)
        XCTAssertEqual(t?.scheduleMode, .everyday)
    }

    func testCommentsAndFailures() {
        let r = ImportParser.parse("""
        # 这是注释
        // 也是注释
        乱写 08:00 说不清
        早起 07:00 每天
        """)
        XCTAssertEqual(r.items.count, 1)
        XCTAssertEqual(r.failed, ["乱写 08:00 说不清"])
    }

    /// 没有时间的那行会整行当名称、默认 08:00 每天，不算失败
    func testLineWithoutTimeIsStillAccepted() {
        let r = ImportParser.parse("乱写的东西")
        XCTAssertTrue(r.failed.isEmpty)
        XCTAssertEqual(r.items.first?.name, "乱写的东西")
        XCTAssertEqual(r.items.first?.minuteOfDay, 8 * 60)
    }

    func testChineseTimeFormat() {
        XCTAssertEqual(single("起床 7点30")?.minuteOfDay, 7 * 60 + 30)
        XCTAssertEqual(single("起床 7点")?.minuteOfDay, 7 * 60)
    }

    func testInvalidTimeRejected() {
        let r = ImportParser.parse("乱写 25:00 每天")
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertEqual(r.failed.count, 1)
    }

    func testNameTooLongIsTruncated() {
        let long = String(repeating: "长", count: 60)
        let t = single("\(long) 07:00 每天")
        XCTAssertEqual(t?.name.count, 40)
    }
}
