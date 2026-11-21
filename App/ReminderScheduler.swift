import Foundation
import UserNotifications

/// iOS 侧的提醒执行层：把 `ReminderPlanner` 算出来的计划，变成系统里真实的待发通知。
///
/// 设计要点
///  - 一条任务一个固定 id（`daka.<day>.<taskId>`），重排时先删后加，天然幂等
///  - iOS 只允许 64 条待发通知，所以永远只排最近 60 条，靠「启动 / 回前台 / 每次改动」
///    重算把窗口往前滚；「稍后」产生的通知用 `daka.snooze.` 前缀单独存放，重排不会误删
///  - 通知上挂两个按钮（完成 / 稍后 10 分钟），点了直接在后台改数据，不用打开 App
///
/// 双轨说明：iOS 26 的 AlarmKit 能穿透静音和专注模式，但需要 Apple 审核的 entitlement
/// 和 iOS 26 SDK，这两样当前都拿不到，所以这一轨暂未接入。接入时只需要在这里加一个
/// `AlarmKitEngine` 并按 `#available` 分流，`ReminderPlanner` 和应用层都不用改。
///
/// 线程约定：和 `TaskStore` 一样，只在主线程调用。
final class ReminderScheduler: NSObject {

    enum ActionID {
        static let done = "DAKA_DONE"
        static let snooze = "DAKA_SNOOZE"
        static let category = "DAKA_TASK"
        /// 前缀区分普通提醒和「稍后」提醒，重排时只清前者
        static let plainPrefix = "daka."
        static let snoozePrefix = "daka.snooze."
    }

    private let center = UNUserNotificationCenter.current()
    private var store: TaskStore?
    /// 数据被外部改掉（点了通知按钮）之后，通知界面刷新用
    private var onChange: (() -> Void)?

    // MARK: - 生命周期

    func activate(store: TaskStore, onChange: @escaping () -> Void) {
        self.store = store
        self.onChange = onChange
        center.delegate = self
        registerCategories()
        Task {
            await requestAuthorization()
            reschedule(store: store)
        }
    }

    /// 首次启动时弹系统授权框；已经决定过就什么都不做
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func reschedule(store: TaskStore) {
        let plan = ReminderPlanner.plan(store: store)
        center.getPendingNotificationRequests { [weak self] pending in
            guard let self else { return }
            // 只清普通提醒；「稍后」那几条还没响，清了就等于把用户的延迟吞了
            let stale = pending
                .map(\.identifier)
                .filter { $0.hasPrefix(ActionID.plainPrefix) && !$0.hasPrefix(ActionID.snoozePrefix) }
            if !stale.isEmpty {
                self.center.removePendingNotificationRequests(withIdentifiers: stale)
            }
            for item in plan {
                self.center.add(self.request(for: item)) { _ in }
            }
        }
    }

    // MARK: - 组装通知

    private func registerCategories() {
        let done = UNNotificationAction(identifier: ActionID.done, title: "完成", options: [])
        let snooze = UNNotificationAction(identifier: ActionID.snooze, title: "稍后 10 分钟", options: [])
        let category = UNNotificationCategory(
            identifier: ActionID.category,
            actions: [done, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    private func request(for item: PlannedReminder) -> UNNotificationRequest {
        let content = content(
            title: "该打卡了：\(item.name)",
            body: "\(item.ruleText) · 点完成或稍后",
            category: ActionID.category,
            sound: item.sound,
            day: item.day,
            taskId: item.taskId,
            name: item.name
        )

        var comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: item.fireDate
        )
        comps.second = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        return UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger)
    }

    private func scheduleSnooze(day: Int, taskId: String, name: String, attempt: Int, sound: Bool) {
        let content = content(
            title: "还没打卡：\(name)",
            body: "已经推迟 \(attempt) 次 · 点完成或再推 10 分钟",
            category: ActionID.category,
            sound: sound,
            day: day,
            taskId: taskId,
            name: name
        )
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        let id = "\(ActionID.snoozePrefix)\(day).\(taskId).\(attempt)"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { _ in }
    }

    private func content(
        title: String,
        body: String,
        category: String,
        sound: Bool,
        day: Int,
        taskId: String,
        name: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        content.categoryIdentifier = category
        content.threadIdentifier = "daka.day.\(day)"
        content.userInfo = ["day": day, "taskId": taskId, "name": name]
        return content
    }
}

// MARK: - 用户点通知上的按钮

extension ReminderScheduler: UNUserNotificationCenterDelegate {

    /// App 在前台时也照常显示横幅：这一版没有悬浮卡片，横幅就是唯一的到点提示
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let store else { return }

        let info = response.notification.request.content.userInfo
        guard let day = info["day"] as? Int, let taskId = info["taskId"] as? String else { return }
        let name = info["name"] as? String ?? "任务"

        switch response.actionIdentifier {
        case ActionID.done:
            store.setDone(day: day, id: taskId, done: true)
            onChange?()
            reschedule(store: store)

        case ActionID.snooze:
            let count = store.bumpSnooze(day: day, id: taskId)
            if count > TaskStore.maxSnooze {
                // 推迟次数用尽：判失败，不再排任何提醒，列表里置灰但仍可补卡
                store.markFailed(day: day, id: taskId)
                onChange?()
                reschedule(store: store)
            } else {
                scheduleSnooze(day: day, taskId: taskId, name: name, attempt: count, sound: true)
                onChange?()
            }

        default:
            // 直接点通知体：打开 App 看清单，不改状态
            break
        }
    }
}
