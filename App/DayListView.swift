import SwiftUI

/// 主界面：某一天的清单。
/// 底部三个按钮对齐 Android 版：从库添加 / 新建 / 任务库。
struct DayListView: View {

    @EnvironmentObject private var model: AppModel
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable {
        case quickAdd
        case library
        case libraryPick
        case settings

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.tasks.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(Dates.dateHeader(model.day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.shift(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        if !model.isToday {
                            Button("今天") { model.backToToday() }
                        }
                        Button {
                            model.shift(1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        Button {
                            sheet = .settings
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .quickAdd:
                    QuickAddSheet { name, minute in
                        model.addQuick(name: name, minuteOfDay: minute)
                    }
                    .presentationDetents([.height(260)])
                case .library:
                    LibraryView(picking: false)
                        .environmentObject(model)
                case .libraryPick:
                    LibraryView(picking: true)
                        .environmentObject(model)
                case .settings:
                    SettingsView()
                        .environmentObject(model)
                }
            }
        }
    }

    private var subtitle: String {
        var parts = ["\(Dates.relativeLabel(model.day)) · 已完成 \(model.doneCount)/\(model.tasks.count)"]
        if model.isRestDay { parts.append("休息日") }
        return parts.joined(separator: " · ")
    }

    private var list: some View {
        List {
            ForEach(model.tasks) { task in
                DayTaskRow(task: task)
                    .contentShape(Rectangle())
                    .onTapGesture { model.toggle(task) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            model.remove(task)
                        } label: {
                            Label("移除", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            action("从库添加", "books.vertical") { sheet = .libraryPick }
            action("新建", "plus.circle") { sheet = .quickAdd }
            action("任务库", "list.bullet.rectangle") { sheet = .library }
        }
        .padding(.top, 6)
        .background(.bar)
    }

    private func action(_ title: String, _ icon: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("这天还没有任务")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("从任务库挑一条，或者直接新建")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 一行任务：左侧圆点 / 名称 / 元信息 / 右侧时间
struct DayTaskRow: View {

    let task: DayTask

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(task.done ? Color.accentColor : Color.clear)
                    .overlay(Circle().strokeBorder(circleBorder, lineWidth: 2))
                    .frame(width: 26, height: 26)
                if task.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                } else if task.failed {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name)
                    .font(.body)
                    .strikethrough(task.done, color: .secondary)
                    .foregroundStyle(nameColor)
                if let meta {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(task.timeText)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(task.settled ? Color.secondary : Color.primary)
        }
        .padding(.vertical, 6)
        .opacity(opacity)
    }

    private var circleBorder: Color {
        if task.done { return .accentColor }
        if task.failed { return Color.secondary.opacity(0.5) }
        return Color.secondary.opacity(0.35)
    }

    private var nameColor: Color {
        if task.failed { return .secondary }
        return .primary
    }

    private var opacity: Double {
        if task.failed { return 0.5 }
        if task.done { return 0.65 }
        return 1
    }

    /// 打过卡但时间对不上 → 「原定 07:00」；判失败 → 「已放弃」
    private var meta: String? {
        if task.timeShifted { return "原定 \(task.plannedTimeText)" }
        if task.failed { return "已放弃 · 可补卡" }
        return nil
    }
}

/// 临时加一条：只进当天，不进任务库
struct QuickAddSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var time = Date()

    let onSave: (String, Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("任务名称", text: $name)
                DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("新建一条")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(name, Dates.nowMinuteOfDay(at: time))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
