import Combine
import Foundation

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

    init(store: TaskStore = .standard()) {
        self.store = store
        self.day = Dates.todayEpochDay()
        store.seedIfNeeded()
        reload()
        // 通知权限、分类按钮、首次排期都在这里完成
        reminders.activate(store: store) { [weak self] in
            self?.externalChanged()
        }
    }

    // MARK: - 读写

    func reload() {
        tasks = store.entriesFor(day)
        doneCount = tasks.filter(\.done).count
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

    // MARK: - 操作

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
}
