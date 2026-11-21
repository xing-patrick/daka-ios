import SwiftUI

/// 节假日 / 调休补班的手动导入。
/// 「法定上班日」「休息日」这两类规则全靠这张表，没导入的话只能按星期推。
struct HolidayView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var summary: String?
    @State private var confirmingClear = false

    private var preview: HolidayParser.Result { HolidayParser.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("已收录")
                        Spacer()
                        Text("\(model.holidayCount) 天")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 150)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("一行一条")
                } footer: {
                    Text("10月1日 休\n2026-10-01 放假\n10/1-10/7 休（区间，整段都标放假）\n10月11日 班（调休补班）\n\n不写「班」就按放假处理；不写年份用今年，已经过去半年以上自动算到明年。")
                }

                if !preview.holidays.isEmpty || !preview.workdays.isEmpty {
                    Section("能识别的") {
                        row("放假", preview.holidays.count)
                        row("补班", preview.workdays.count)
                    }
                }

                if !preview.failed.isEmpty {
                    Section("看不懂的 \(preview.failed.count) 行") {
                        ForEach(Array(preview.failed.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Button("清空全部节假日") { confirmingClear = true }
                        .foregroundStyle(.red)
                } footer: {
                    Text("清空后「法定上班日 / 休息日」规则退回按星期推算。")
                }
            }
            .navigationTitle("节假日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { runImport() }
                        .disabled(preview.holidays.isEmpty && preview.workdays.isEmpty)
                }
            }
            .alert(
                "导入结果",
                isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })
            ) {
                Button("好") { summary = nil }
            } message: {
                Text(summary ?? "")
            }
            .confirmationDialog("确定清空全部节假日？", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    model.clearHolidays()
                    summary = "已清空"
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func row(_ title: String, _ count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count) 天")
                .foregroundStyle(.secondary)
        }
    }

    private func runImport() {
        let result = model.importHolidays(text)
        var parts = ["放假 \(result.holidays.count) 天", "补班 \(result.workdays.count) 天"]
        if !result.failed.isEmpty {
            parts.append("\(result.failed.count) 行看不懂")
        }
        summary = parts.joined(separator: "，")
        text = ""
    }
}
