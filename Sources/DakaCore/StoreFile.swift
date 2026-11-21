import Foundation

/// 全部状态存一个 JSON 文件。
///
/// Android 版把模板 / 每日实例 / 节假日塞在同一个 SharedPreferences 里，
/// 这里换成单个文件，结构对得上，可以直接读写 Android 导出的同结构 JSON。
///
/// `url == nil` 时是纯内存模式，单测用。
final class StoreFile {

    struct Snapshot: Codable {
        var templates: [TaskTemplate] = []
        /// key 是 epochDay 的字符串形式，与 Android 的 JSONObject 键一致
        var days: [String: [DayTask]] = [:]
        var holidays: [Int] = []
        var workdays: [Int] = []
        var seeded: Bool = false
        var version: Int = 3
    }

    /// 内部可变：TaskStore / HolidayStore 直接改字段再 save()。
    /// 只在主线程使用，不加锁。
    var data: Snapshot
    private let url: URL?

    init(url: URL?) {
        self.url = url
        if let url, let raw = try? Data(contentsOf: url) {
            data = (try? JSONDecoder().decode(Snapshot.self, from: raw)) ?? Snapshot()
        } else {
            data = Snapshot()
        }
    }

    static func memory() -> StoreFile { StoreFile(url: nil) }

    /// 默认位置：Application Support/Daka/store.json
    static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = base.appendingPathComponent("Daka", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }

    static func standard() -> StoreFile { StoreFile(url: defaultURL()) }

    /// 写盘是原子的，避免中途被杀留下半个 JSON
    func save() {
        guard let url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let raw = try encoder.encode(data)
            try raw.write(to: url, options: .atomic)
        } catch {
            assertionFailure("保存失败：\(error)")
        }
    }
}
