import Foundation

/// 与 Android 版 `data/TaskStore.kt` 对应的存储 + 展开逻辑。
///
/// 存储分两块：
///  - templates：任务库模板，不隶属任何日期
///  - days：按日期存的任务实例，每天一份独立列表
///
/// 关键规则（与 Android 完全一致）：
///  1. 打开某天时，重复模板按规则「展开」成那天的实例（只补一次）
///  2. 实例从模板复制出来后完全独立，改它不碰模板、不碰其他日期
///  3. 移除实例用墓碑标记，防止下次打开又被模板补回来
///  4. 单日模板不指定日期，只能由用户在某天主动挑选添加
///
/// 约定：只在主线程使用，内部不做加锁。
final class TaskStore {

    /// 一条任务最多能「稍后」几次。每次 10 分钟，3 次 = 往后推半小时。
    static let maxSnooze = 3

    private let store: StoreFile
    let holidays: HolidayStore

    init(store: StoreFile) {
        self.store = store
        self.holidays = HolidayStore(store: store)
    }

    static func inMemory() -> TaskStore { TaskStore(store: .memory()) }
    static func standard() -> TaskStore { TaskStore(store: .standard()) }

    // MARK: - 任务库模板

    var templates: [TaskTemplate] { store.data.templates }

    func saveTemplates(_ list: [TaskTemplate]) {
        store.data.templates = list
        store.save()
    }

    func findTemplate(_ id: String) -> TaskTemplate? {
        store.data.templates.first { $0.id == id }
    }

    func upsertTemplate(_ template: TaskTemplate) {
        var list = store.data.templates
        if let idx = list.firstIndex(where: { $0.id == template.id }) {
            list[idx] = template
        } else {
            list.append(template)
        }
        saveTemplates(list)
    }

    /// 只删模板，所有日期的实例都保留
    func deleteTemplate(id: String) {
        saveTemplates(store.data.templates.filter { $0.id != id })
    }

    /// 删除模板，并把变化传导到「还没发生」的实例，返回一起删掉的实例条数。
    ///
    /// 跟着删的条件与 `syncTemplate` 完全一致：日期 >= 今天、今天这条还没到点、
    /// templateId 命中、没被手动改过、没打卡、没判失败、没被移除。
    @discardableResult
    func deleteTemplateWithSync(id: String) -> Int {
        guard findTemplate(id) != nil else { return 0 }
        let today = Dates.todayEpochDay()
        let now = Dates.nowMinuteOfDay()
        var removed = 0

        for (key, tasks) in store.data.days {
            guard let day = Int(key), day >= today else { continue }
            let kept = tasks.filter { t in
                let notHappened = day > today || (day == today && t.minuteOfDay > now)
                let drop = t.templateId == id && !t.removed && !t.done && !t.failed
                    && !t.customized && notHappened
                return !drop
            }
            let delta = tasks.count - kept.count
            if delta > 0 {
                store.data.days[key] = kept
                removed += delta
            }
        }
        if removed > 0 { store.save() }
        deleteTemplate(id: id)
        return removed
    }

    // MARK: - 按日期存的实例

    /// 原始实例列表（含墓碑），不触发自动展开
    func rawTasks(_ day: Int) -> [DayTask] {
        store.data.days[String(day)] ?? []
    }

    private func saveTasks(_ day: Int, _ list: [DayTask]) {
        store.data.days[String(day)] = list
        store.save()
    }

    var allInstanceIds: [String] {
        store.data.days.values.flatMap { $0.map(\.id) }
    }

    func findInstance(day: Int, id: String) -> DayTask? {
        rawTasks(day).first { $0.id == id && !$0.removed }
    }

    /// 取某天的清单：先把命中的重复模板补成实例，再过滤墓碑。
    func entriesFor(_ day: Int) -> [DayTask] {
        var tasks = rawTasks(day)
        let allTemplates = store.data.templates
        let tplByID = Dictionary(allTemplates.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false

        // 规则或节假日表变了之后，把「自动展开、还没发生、也没被手动改过」、
        // 但现在不再命中规则的实例撤掉。过去日期一律不动。
        if day >= Dates.todayEpochDay() {
            let kept = tasks.filter { t in
                if !t.auto || t.removed || t.templateId.isEmpty
                    || t.done || t.failed || t.customized { return true }
                guard let tpl = tplByID[t.templateId] else { return true }
                if tpl.kind != .repeating { return true }
                return holidays.matches(tpl.scheduleMode, tpl.daysMask, day)
            }
            if kept.count != tasks.count {
                tasks = kept
                changed = true
            }
        }

        var seen = Set(tasks.map(\.templateId))
        for t in allTemplates where t.kind == .repeating {
            if day < t.createdEpochDay { continue }
            if !holidays.matches(t.scheduleMode, t.daysMask, day) { continue }
            if seen.contains(t.id) { continue }
            tasks.append(DayTask(
                templateId: t.id,
                name: t.name,
                minuteOfDay: t.minuteOfDay,
                auto: true,
                sound: t.sound,
                vibrate: t.vibrate
            ))
            seen.insert(t.id)
            changed = true
        }

        if changed { saveTasks(day, tasks) }
        return tasks.filter { !$0.removed }.sorted { $0.minuteOfDay < $1.minuteOfDay }
    }

    /// 排期前调用，确保这一天的实例已经生成
    func ensureDay(_ day: Int) { _ = entriesFor(day) }

    func progress(_ day: Int) -> (done: Int, total: Int) {
        let list = entriesFor(day)
        return (list.filter(\.done).count, list.count)
    }

    // MARK: - 实例操作（全部只作用于这一天）

    /// 从任务库挑一个模板，添加到指定日期
    @discardableResult
    func addFromTemplate(day: Int, templateId: String) -> Bool {
        guard let t = findTemplate(templateId) else { return false }
        var tasks = rawTasks(day)
        tasks.append(DayTask(
            templateId: t.id,
            name: t.name,
            minuteOfDay: t.minuteOfDay,
            sound: t.sound,
            vibrate: t.vibrate
        ))
        saveTasks(day, tasks)
        return true
    }

    /// 直接在这天新建一个临时任务，不进任务库
    @discardableResult
    func addStandalone(
        day: Int,
        name: String,
        minuteOfDay: Int,
        sound: Bool = true,
        vibrate: Bool = true
    ) -> DayTask {
        let task = DayTask(name: name, minuteOfDay: minuteOfDay, sound: sound, vibrate: vibrate)
        var tasks = rawTasks(day)
        tasks.append(task)
        saveTasks(day, tasks)
        return task
    }

    /// 编辑实例：只改这一条，并打上「已定制」，之后模板再改也跳过它
    func updateInstance(
        day: Int,
        id: String,
        name: String,
        minuteOfDay: Int,
        sound: Bool = true,
        vibrate: Bool = true
    ) {
        var tasks = rawTasks(day)
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].name = name
        tasks[idx].minuteOfDay = minuteOfDay
        tasks[idx].sound = sound
        tasks[idx].vibrate = vibrate
        tasks[idx].customized = true
        saveTasks(day, tasks)
    }

    /// 改了任务库模板之后调用：把新名称/时间传导到还没发生的实例，返回被更新的条数。
    @discardableResult
    func syncTemplate(_ tpl: TaskTemplate) -> Int {
        let today = Dates.todayEpochDay()
        let now = Dates.nowMinuteOfDay()
        var count = 0

        for (key, tasks) in store.data.days {
            guard let day = Int(key), day >= today else { continue }
            var list = tasks
            var touched = false
            for i in list.indices {
                let t = list[i]
                if t.templateId != tpl.id || t.removed || t.done || t.failed || t.customized { continue }
                let notHappened = day > today || (day == today && t.minuteOfDay > now)
                if !notHappened { continue }
                list[i].name = tpl.name
                list[i].minuteOfDay = tpl.minuteOfDay
                list[i].sound = tpl.sound
                list[i].vibrate = tpl.vibrate
                touched = true
                count += 1
            }
            if touched { store.data.days[key] = list }
        }
        if count > 0 { store.save() }
        return count
    }

    @discardableResult
    func toggleDone(day: Int, id: String) -> Bool {
        guard let instance = findInstance(day: day, id: id) else { return false }
        let next = !instance.done
        setDone(day: day, id: id, done: next)
        return next
    }

    /// 打卡 / 取消打卡。
    ///
    /// 打卡成功把**实际时刻**记进 doneAt；对已经打过卡的那条再点一次不会改变已记录的时间
    /// （双击、重复通知都可能把同一动作送进来第二次，刷新就丢了第一次的真实时间）。
    func setDone(day: Int, id: String, done: Bool, now: Int? = nil) {
        var tasks = rawTasks(day)
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let old = tasks[idx]
        if !done {
            tasks[idx].done = false
            tasks[idx].doneAt = -1
            tasks[idx].snoozeCount = 0
        } else if old.done {
            // 已经完成过：原样保留，不刷新时间
        } else {
            tasks[idx].done = true
            tasks[idx].doneAt = now ?? Dates.nowMinuteOfDay()
            tasks[idx].snoozeCount = 0
            tasks[idx].failed = false
        }
        saveTasks(day, tasks)
    }

    /// 「稍后」次数 +1，返回累计次数
    @discardableResult
    func bumpSnooze(day: Int, id: String) -> Int {
        var tasks = rawTasks(day)
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return 0 }
        tasks[idx].snoozeCount += 1
        let next = tasks[idx].snoozeCount
        saveTasks(day, tasks)
        return next
    }

    /// 延迟次数用尽仍未完成 → 判定打卡失败：不再提醒、列表置灰，仍可手动补卡
    @discardableResult
    func markFailed(day: Int, id: String) -> Bool {
        var tasks = rawTasks(day)
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return false }
        if tasks[idx].done { return false }
        tasks[idx].failed = true
        tasks[idx].snoozeCount = TaskStore.maxSnooze
        saveTasks(day, tasks)
        return true
    }

    /// 从这天移除，留墓碑防止重复模板自动补回来
    func removeInstance(day: Int, id: String) {
        var tasks = rawTasks(day)
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].removed = true
        tasks[idx].done = false
        tasks[idx].doneAt = -1
        tasks[idx].snoozeCount = 0
        tasks[idx].failed = false
        saveTasks(day, tasks)
    }

    // MARK: - 初始化

    /// 首次启动灌三条示例模板（与 Android 版一致）
    func seedIfNeeded() {
        guard !store.data.seeded else { return }
        if store.data.templates.isEmpty {
            let today = Dates.todayEpochDay()
            saveTemplates([
                TaskTemplate(name: "早起", minuteOfDay: 7 * 60, kind: .repeating,
                             scheduleMode: .weekday, daysMask: Dates.weekdays, createdEpochDay: today),
                TaskTemplate(name: "睡前阅读", minuteOfDay: 22 * 60 + 30, kind: .repeating,
                             scheduleMode: .everyday, daysMask: Dates.allDays, createdEpochDay: today),
                TaskTemplate(name: "买牛奶", minuteOfDay: 18 * 60, kind: .once,
                             createdEpochDay: today)
            ])
        }
        store.data.seeded = true
        store.save()
    }

    func clearAll() {
        store.data.templates = []
        store.data.days = [:]
        store.save()
    }
}
