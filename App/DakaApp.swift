import SwiftUI

@main
struct DakaApp: App {

    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            DayListView()
                .environmentObject(model)
        }
    }
}
