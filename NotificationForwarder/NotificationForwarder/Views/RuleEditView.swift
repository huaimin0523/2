import SwiftUI

struct RuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var configManager: ConfigManager

    @State private var rule: ForwardRule
    @State private var titleKeywordsText: String
    @State private var bodyKeywordsText: String
    @State private var sourceBundleIDsText: String

    private let isNew: Bool
    private let onSave: (ForwardRule) -> Void

    init(rule: ForwardRule?, onSave: @escaping (ForwardRule) -> Void) {
        let initial = rule ?? ForwardRule(name: "")
        _rule = State(initialValue: initial)
        _titleKeywordsText = State(initialValue: initial.titleKeywords.joined(separator: ","))
        _bodyKeywordsText = State(initialValue: initial.bodyKeywords.joined(separator: ","))
        _sourceBundleIDsText = State(initialValue: initial.sourceBundleIDs.joined(separator: ","))
        isNew = rule == nil
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("规则名称", text: $rule.name)
                Toggle("启用", isOn: $rule.enabled)
            }

            Section("匹配条件（留空表示不限）") {
                VStack(alignment: .leading) {
                    Text("标题关键字").font(.caption).foregroundStyle(.secondary)
                    TextField("用英文逗号分隔", text: $titleKeywordsText)
                }
                VStack(alignment: .leading) {
                    Text("正文字关键字").font(.caption).foregroundStyle(.secondary)
                    TextField("用英文逗号分隔", text: $bodyKeywordsText)
                }
                VStack(alignment: .leading) {
                    Text("来源 App Bundle ID").font(.caption).foregroundStyle(.secondary)
                    TextField("com.tencent.xin, com.apple.MobileSMS", text: $sourceBundleIDsText)
                }
                Toggle("大小写敏感", isOn: $rule.caseSensitive)
            }

            Section("转发目标") {
                if configManager.config.targets.isEmpty {
                    Text("暂无目标，将转发给所有启用目标").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("不选任何目标 = 转发给全部启用目标").font(.caption).foregroundStyle(.secondary)
                    ForEach(configManager.config.targets) { target in
                        let isSelected = rule.targetIDs.contains(target.id)
                        Button {
                            if isSelected {
                                rule.targetIDs.removeAll { $0 == target.id }
                            } else {
                                rule.targetIDs.append(target.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                Text(target.name)
                                Spacer()
                                Text(target.type.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button("保存") {
                    rule.titleKeywords = splitComma(titleKeywordsText)
                    rule.bodyKeywords = splitComma(bodyKeywordsText)
                    rule.sourceBundleIDs = splitComma(sourceBundleIDsText)
                    onSave(rule)
                    dismiss()
                }
                .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(isNew ? "新建规则" : "编辑规则")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
        }
    }

    private func splitComma(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
