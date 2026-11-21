import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingHoliday = false
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("通知权限")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(statusColor)
                    }
                    switch model.notificationStatus {
                    case .notDetermined:
                        Button("开启通知") { model.requestNotificationPermission() }
                    case .denied:
                        Button("去系统设置里打开") { openSystemSettings() }
                    default:
                        Text("到点会弹横幅，横幅上可以直接打卡或推迟 10 分钟。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("iOS 只保留最近 60 条待发提醒，App 每次启动、回到前台都会自动往后补排；长时间不打开 App 可能排不满。")
                }

                Section("数据") {
                    Button {
                        showingHoliday = true
                    } label: {
                        HStack {
                            Text("节假日")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(model.holidayCount) 天")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        confirmingClear = true
                    } label: {
                        Text("清空任务数据")
                    }
                }

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(versionText)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("任务模板")
                        Spacer()
                        Text("\(model.templates.count) 条")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingHoliday) {
                HolidayView()
                    .environmentObject(model)
            }
            .confirmationDialog(
                "清空所有任务和模板？",
                isPresented: $confirmingClear,
                titleVisibility: .visible
            ) {
                Button("清空", role: .destructive) {
                    model.clearAllTasks()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这个操作不可撤销，会重新灌入三条示例任务。")
            }
            .task {
                model.refreshNotificationStatus()
            }
        }
    }

    private var statusText: String {
        switch model.notificationStatus {
        case .authorized: return "已开启"
        case .denied: return "已拒绝"
        case .provisional: return "静默推送"
        case .ephemeral: return "临时授权"
        case .notDetermined: return "未决定"
        @unknown default: return "未知"
        }
    }

    private var statusColor: Color {
        switch model.notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        default: return .secondary
        }
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
