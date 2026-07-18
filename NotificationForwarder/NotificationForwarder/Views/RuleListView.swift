import SwiftUI

struct RuleListView: View {
    @EnvironmentObject var configManager: ConfigManager
    @State private var showingEditor = false
    @State private var editingRule: ForwardRule?

    var body: some View {
        List {
            if configManager.config.rules.isEmpty {
                ContentUnavailableView(
                    "还没有规则",
                    systemImage: "list.bullet.indent",
                    description: Text("不创建规则时，所有推送会转发给所有启用的目标。\n创建规则后，可按关键字 / 来源 App 选择性转发。")
                )
            } else {
                ForEach(configManager.config.rules) { rule in
                    Button {
                        editingRule = rule
                    } label: {
                        RuleRow(rule: rule)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            configManager.deleteRule(rule)
                        } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("转发规则")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingEditor = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                RuleEditView(rule: nil) { newRule in
                    configManager.upsertRule(newRule)
                }
            }
        }
        .sheet(item: $editingRule) { rule in
            NavigationStack {
                RuleEditView(rule: rule) { updated in
                    configManager.upsertRule(updated)
                }
            }
        }
    }
}

private struct RuleRow: View {
    let rule: ForwardRule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.name).font(.headline)
                Spacer()
                if !rule.enabled {
                    Text("已停用").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !rule.titleKeywords.isEmpty {
                keywordLine("标题", keywords: rule.titleKeywords)
            }
            if !rule.bodyKeywords.isEmpty {
                keywordLine("正文", keywords: rule.bodyKeywords)
            }
            if !rule.sourceBundleIDs.isEmpty {
                keywordLine("来源", keywords: rule.sourceBundleIDs)
            }
        }
        .padding(.vertical, 4)
    }

    private func keywordLine(_ label: String, keywords: [String]) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
            Text(keywords.joined(separator: " · "))
                .font(.caption)
                .lineLimit(2)
        }
    }
}
