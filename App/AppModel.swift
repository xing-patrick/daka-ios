import Combine
import Foundation

/// 界面与数据层之间的一层薄封装。
///
/// 约定与 `TaskStore` 一致：**只在主线程使用**。
/// 所有写操作之后立刻 `reload()`，让 SwiftUI 看到新的数组。
final class AppModel: ObservableObject {

    let store: TaskStore

    /// 当前正在看的那一天（epochDay）
    @Published private(set) var day: Int
    @Published private(set) var tasks: [DayTask] = []
    @Published private(set) var doneCount = 0

    init(store: TaskStore = .standard()) {
        self.store = store
        self.day = Dates.todayEpochDay()
        store.seedIfNeeded()
        reload()
    }

    // MARK: - 读写

    func reload() {
        tasks = store.entriesFor(day)
        doneCount = tasks.filter(\.done).count
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
    }

    func remove(_ task: DayTask) {
        store.removeInstance(day: day, id: task.id)
        reload()
    }

    func addQuick(name: String, minuteOfDay: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = store.addStandalone(day: day, name: trimmed, minuteOfDay: minuteOfDay)
        reload()
    }
}
