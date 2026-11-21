import SwiftUI

/// 编辑模板时在视图之间传的草稿。
/// 用一份独立副本，取消时不会污染库里那条。
struct TemplateDraft: Identifiable {
    let id = UUID()
    var isNew: Bool
    var template: TaskTemplate

    static func new() -> TemplateDraft {
        TemplateDraft(
            isNew: true,
            template: TaskTemplate(name: "", minuteOfDay: 8 * 60, kind: .repeating)
        )
    }

    static func edit(_ template: TaskTemplate) -> TemplateDraft {
        TemplateDraft(isNew: false, template: template)
    }
}

/// 任务库：模板的增删改 + 批量导入入口。
/// `picking == true` 时是「从库添加」，点一条就加到当前这天并关闭。
struct LibraryView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let picking: Bool

    @State private var sheet: LibSheet?
    @State private var pendingDelete: TaskTemplate?
    @State private var toast: String?

    private enum LibSheet: Identifiable {
        case editor(TemplateDraft)
        case importer

        var id: String {
            switch self {
            case .editor(let draft): return "editor-\(draft.id)"
            case .importer: return "importer"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.templates.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(picking ? "从库添加" : "任务库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .editor(.new())
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        sheet = .importer
                    } label: {
                        Label("批量导入", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .editor(let draft):
                    TemplateEditorView(draft: draft)
                        .environmentObject(model)
                case .importer:
                    ImportView()
                        .environmentObject(model)
                }
            }
            .alert(
                "删除「\(pendingDelete?.name ?? "")」？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                )
            ) {
                Button("删除", role: .destructive) {
                    if let template = pendingDelete {
                        let removed = model.deleteTemplate(template)
                        toast = removed > 0 ? "已删除，同时移除了 \(removed) 条未发生的提醒" : "已删除"
                    }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("还没到点的实例会一起删掉，过去的打卡记录保留。")
            }
            .onChange(of: toast) { _, value in
                guard value != nil else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    toast = nil
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(model.templates) { template in
                Button {
                    handleTap(template)
                } label: {
                    row(template)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = template
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        sheet = .editor(.edit(template))
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }

    private func row(_ template: TaskTemplate) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(template.ruleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(template.timeText)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
            if picking {
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func handleTap(_ template: TaskTemplate) {
        if picking {
            if model.addFromLibrary(templateId: template.id) {
                dismiss()
            }
        } else {
            sheet = .editor(.edit(template))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text("任务库还是空的")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("点右上角 ＋ 建一条，或者用批量导入一次贴一批")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
