import Combine
import Foundation
import UserNotifications

/// 界面与数据层之间的一层薄封装。
///
/// 约定与 `TaskStore` 一致：**只在主线程使用**。
/// 所有写操作之后立刻 `reload()`，让 SwiftUI 看到新的数组。
final class AppModel: ObservableObject {

    let store: TaskStore
    private let reminders = ReminderScheduler()

    /// 当前正在看的那一天（epochDay）
    @Published private(set) var day: Int
    @Published private(set) var tasks: [DayTask] = []
    @Published private(set) var doneCount = 0
    @Published private(set) var templates: [TaskTemplate] = []
    /// 通知权限状态，设置页要显示
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined

    init(store: TaskStore = .standard()) {
        self.store = store
        self.day = Dates.todayEpochDay()
        store.seedIfNeeded()
        reload()
        reloadTemplates()
        // 通知权限、分类按钮、首次排期都在这里完成
        reminders.activate(store: store) { [weak self] in
            self?.externalChanged()
        }
        refreshNotificationStatus()
    }

    // MARK: - 读写

    func reload() {
        tasks = store.entriesFor(day)
        doneCount = tasks.filter(\.done).count
    }

    func reloadTemplates() {
        templates = store.templates.sorted {
            $0.minuteOfDay == $1.minuteOfDay ? $0.name < $1.name : $0.minuteOfDay < $1.minuteOfDay
        }
    }

    /// 重算待发通知。每次改完数据都要调，否则通知和清单会对不上。
    func refreshReminders() {
        reminders.reschedule(store: store)
    }

    /// 通知按钮改了数据之后，把界面和排期都刷一遍
    private func externalChanged() {
        reload()
        refreshReminders()
    }

    func refreshNotificationStatus() {
        Task { @MainActor in
            let status = await reminders.authorizationStatus()
            notificationStatus = status
        }
    }

    func requestNotificationPermission() {
        Task { @MainActor in
            await reminders.requestAuthorization()
            notificationStatus = await reminders.authorizationStatus()
            refreshReminders()
        }
    }

    func go(to newDay: Int) {
        day = newDay
        reload()
    }

    func shift(_ delta: Int) {
        go(to: day + delta)
    }

    func backToToday() {
        go(to: Dates.todayEpochDay())
    }

    var isToday: Bool { day == Dates.todayEpochDay() }

    /// 「今天 · 已完成 1/3」，副标题不跟大标题重复日期
    var subtitle: String {
        "\(Dates.relativeLabel(day)) · 已完成 \(doneCount)/\(tasks.count)"
    }

    /// 这一天是不是休息日（周末 / 法定假 / 调休补班的判断都在这里）
    var isRestDay: Bool { store.holidays.isRestDay(day) }

    // MARK: - 当天清单的操作

    func toggle(_ task: DayTask) {
        store.toggleDone(day: day, id: task.id)
        reload()
        refreshReminders()
    }

    func remove(_ task: DayTask) {
        store.removeInstance(day: day, id: task.id)
        reload()
        refreshReminders()
    }

    func addQuick(name: String, minuteOfDay: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = store.addStandalone(day: day, name: trimmed, minuteOfDay: minuteOfDay)
        reload()
        refreshReminders()
    }

    /// 从任务库挑一个模板加到当前这天
    @discardableResult
    func addFromLibrary(templateId: String) -> Bool {
        let ok = store.addFromTemplate(day: day, templateId: templateId)
        reload()
        refreshReminders()
        return ok
    }

    // MARK: - 任务库

    func template(_ id: String) -> TaskTemplate? {
        store.findTemplate(id)
    }

    /// 新建或修改模板。改已有模板时把变化传导到未来实例，返回被更新的条数。
    @discardableResult
    func saveTemplate(_ template: TaskTemplate, isNew: Bool) -> Int {
        store.upsertTemplate(template)
        reloadTemplates()
        let synced = isNew ? 0 : store.syncTemplate(template)
        reload()
        refreshReminders()
        return synced
    }

    /// 删模板，并把还没发生的实例一起删掉，返回被删的实例条数
    @discardableResult
    func deleteTemplate(_ template: TaskTemplate) -> Int {
        let removed = store.deleteTemplateWithSync(id: template.id)
        reloadTemplates()
        reload()
        refreshReminders()
        return removed
    }

    /// 批量导入文本，返回解析结果（已经写进库，返回的是原文案和失败行）
    func importTemplates(_ text: String) -> ImportParser.Result {
        let result = ImportParser.parse(text)
        guard !result.items.isEmpty else { return result }
        var list = store.templates
        list.append(contentsOf: result.items)
        store.saveTemplates(list)
        reloadTemplates()
        refreshReminders()
        return result
    }

    // MARK: - 节假日

    var holidayCount: Int { store.holidays.count }

    /// 导入节假日 / 调休，返回解析结果（已经合并进库）
    func importHolidays(_ text: String) -> HolidayParser.Result {
        let result = HolidayParser.parse(text)
        if !result.holidays.isEmpty || !result.workdays.isEmpty {
            _ = store.holidays.merge(holidays: result.holidays, workdays: result.workdays)
            // 规则变了，未来几天的实例要重算
            reload()
            refreshReminders()
        }
        return result
    }

    func clearHolidays() {
        store.holidays.clear()
        reload()
        refreshReminders()
    }

    // MARK: - 设置

    func clearAllTasks() {
        store.clearAll()
        store.seedIfNeeded()
        reloadTemplates()
        reload()
        refreshReminders()
    }
}
