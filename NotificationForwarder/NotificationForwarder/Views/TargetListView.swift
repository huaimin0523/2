import SwiftUI

struct TargetListView: View {
    @EnvironmentObject var configManager: ConfigManager
    @State private var showingEditor = false
    @State private var editingTarget: ForwardTarget?

    var body: some View {
        List {
            if configManager.config.targets.isEmpty {
                ContentUnavailableView(
                    "还没有转发目标",
                    systemImage: "paperplane",
                    description: Text("点击右上角添加一个目标，例如 Webhook、邮箱、Telegram 等。")
                )
            } else {
                ForEach(configManager.config.targets) { target in
                    Button {
                        editingTarget = target
                    } label: {
                        TargetRow(target: target)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            configManager.deleteTarget(target)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: move)
            }
        }
        .navigationTitle("转发目标")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingTarget = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            #if !os(macOS)
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            #endif
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                TargetEditView(target: nil) { newTarget in
                    configManager.upsertTarget(newTarget)
                }
            }
        }
        .sheet(item: $editingTarget) { target in
            NavigationStack {
                TargetEditView(target: target) { updated in
                    configManager.upsertTarget(updated)
                }
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        configManager.config.targets.move(fromOffsets: source, toOffset: destination)
        configManager.save()
    }
}

private struct TargetRow: View {
    let target: ForwardTarget

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(target.enabled ? .tint : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).font(.headline)
                Text(target.type.displayName).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !target.enabled {
                Text("已停用").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch target.type {
        case .webhook:        return "link"
        case .email:          return "envelope"
        case .sms:            return "message"
        case .thirdPartyApp:  return "bubble.left.and.bubble.right"
        }
    }
}
