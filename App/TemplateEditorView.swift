import SwiftUI

/// 新建 / 编辑一条任务库模板。
struct TemplateEditorView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let draft: TemplateDraft

    @State private var name: String
    @State private var time: Date
    @State private var kind: TemplateKind
    @State private var mode: ScheduleMode
    @State private var mask: Int
    @State private var sound: Bool

    init(draft: TemplateDraft) {
        self.draft = draft
        _name = State(initialValue: draft.template.name)
        let today = Dates.todayEpochDay()
        _time = State(initialValue: ReminderPlanner.fireDate(day: today, minuteOfDay: draft.template.minuteOfDay) ?? Date())
        _kind = State(initialValue: draft.template.kind)
        _mode = State(initialValue: draft.template.scheduleMode)
        _mask = State(initialValue: draft.template.daysMask)
        _sound = State(initialValue: draft.template.sound)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("任务名称", text: $name)
                    DatePicker("提醒时间", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }

                Section {
                    Picker("类型", selection: $kind) {
                        Text("重复").tag(TemplateKind.repeating)
                        Text("单次").tag(TemplateKind.once)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(kind == .repeating
                         ? "到点自动出现在符合规则的每一天"
                         : "单次模板不绑定日期，需要你在某一天点「从库添加」才会出现")
                }

                if kind == .repeating {
                    Section("排期规则") {
                        Picker("规则", selection: $mode) {
                            ForEach(ScheduleMode.allCases, id: \.self) { item in
                                Text(item.label(daysMask: mask)).tag(item)
                            }
                        }
                        if mode == .custom {
                            weekdayPicker
                        }
                    }
                }

                Section {
                    Toggle("到点出声", isOn: $sound)
                } footer: {
                    Text("iOS 不支持单独开关震动，声音关掉后仍然会亮屏提示")
                }

                if !draft.isNew {
                    Section {
                        Text("改完只影响还没到点的提醒，已经打过卡的不动。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(draft.isNew ? "新建任务" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var weekdayPicker: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                Button {
                    mask ^= (1 << index)
                } label: {
                    Text(Dates.weekdayText(1 << index).replacingOccurrences(of: "周", with: ""))
                        .font(.footnote)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(
                            (mask >> index) & 1 == 1 ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle((mask >> index) & 1 == 1 ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        var template = draft.template
        template.name = String(trimmed.prefix(40))
        template.minuteOfDay = Dates.nowMinuteOfDay(at: time)
        template.kind = kind
        template.scheduleMode = mode
        template.daysMask = maskFor(mode)
        template.sound = sound

        _ = model.saveTemplate(template, isNew: draft.isNew)
        dismiss()
    }

    /// 规则和 bitmask 要一起对齐，否则换规则后旧 mask 会留下矛盾数据
    private func maskFor(_ mode: ScheduleMode) -> Int {
        switch mode {
        case .everyday: return Dates.allDays
        case .weekday, .legalWorkday: return Dates.weekdays
        case .weekend, .legalHoliday: return Dates.weekend
        case .custom: return mask == 0 ? Dates.allDays : mask
        }
    }
}
