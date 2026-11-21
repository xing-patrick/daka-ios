import SwiftUI

/// 批量导入：一行一条「名称 时间 规则」，边输入边预览解析结果。
struct ImportView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var summary: String?

    /// 实时解析：不用先点按钮才知道哪行写错了
    private var preview: ImportParser.Result { ImportParser.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 170)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("一行一条：名称 时间 规则")
                } footer: {
                    Text("早起 07:00 每天\n喝水 09:30 工作日\n游泳 15:00 周末\n阅读 21:00 一三五\n跑步 20:00 1-5\n收邮件 09:00 法定上班日\n大扫除 10:00 休息日\n买牛奶 18:00 单日\n冥想（不写时间默认 08:00、每天）")
                }

                if !preview.items.isEmpty {
                    Section("能识别的 \(preview.items.count) 条") {
                        ForEach(Array(preview.items.enumerated()), id: \.offset) { _, item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text(item.ruleText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.timeText)
                                    .font(.system(.body, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            }
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { runImport() }
                        .disabled(preview.items.isEmpty)
                }
            }
            .alert(
                "导入结果",
                isPresented: Binding(get: { summary != nil }, set: { if !$0 { summary = nil } })
            ) {
                Button("好") {
                    summary = nil
                    dismiss()
                }
            } message: {
                Text(summary ?? "")
            }
        }
    }

    private func runImport() {
        let result = model.importTemplates(text)
        var parts = ["成功导入 \(result.items.count) 条"]
        if !result.failed.isEmpty {
            parts.append("\(result.failed.count) 行看不懂，已跳过")
        }
        summary = parts.joined(separator: "，")
    }
}
