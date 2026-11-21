import SwiftUI

@main
struct DakaApp: App {

    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            DayListView()
                .environmentObject(model)
        }
        // iOS 只保留 64 条待发通知，靠这两个时机把窗口往前滚：
        // 回前台可能已经跨天，重新算一遍；进后台前把接下来的排满。
        .onChange(of: phase) { _, newPhase in
            switch newPhase {
            case .active:
                model.reload()
                model.refreshReminders()
            case .background:
                model.refreshReminders()
            default:
                break
            }
        }
    }
}
