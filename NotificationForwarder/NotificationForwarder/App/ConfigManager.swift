import Foundation
import SwiftUI
import Combine

/// 配置管理：主 App 中的 ObservableObject，封装 ConfigStore 的读写，
/// 暴露给 SwiftUI 视图响应式使用。
@MainActor
final class ConfigManager: ObservableObject {

    @Published private(set) var config: AppConfig

    private let store: ConfigStore

    init(store: ConfigStore = .shared) {
        self.store = store
        self.config = store.load()
    }

    /// 重新从磁盘加载（例如 Extension 写入了日志后）。
    func reload() {
        config = store.load()
    }

    /// 保存当前配置到共享容器。
    func save() {
        do {
            try store.save(config)
        } catch {
            print("保存配置失败：\(error)")
        }
    }

    // MARK: - Targets

    func upsertTarget(_ target: ForwardTarget) {
        if let idx = config.targets.firstIndex(where: { $0.id == target.id }) {
            config.targets[idx] = target
        } else {
            config.targets.append(target)
        }
        save()
    }

    func deleteTarget(_ target: ForwardTarget) {
        config.targets.removeAll { $0.id == target.id }
        // 同时从规则的 targetIDs 中移除
        for i in config.rules.indices {
            config.rules[i].targetIDs.removeAll { $0 == target.id }
        }
        save()
    }

    func toggleTarget(_ target: ForwardTarget) {
        guard let idx = config.targets.firstIndex(where: { $0.id == target.id }) else { return }
        config.targets[idx].enabled.toggle()
        save()
    }

    func moveTarget(from source: IndexSet, to destination: Int) {
        config.targets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: - Rules

    func upsertRule(_ rule: ForwardRule) {
        if let idx = config.rules.firstIndex(where: { $0.id == rule.id }) {
            config.rules[idx] = rule
        } else {
            config.rules.append(rule)
        }
        save()
    }

    func deleteRule(_ rule: ForwardRule) {
        config.rules.removeAll { $0.id == rule.id }
        save()
    }

    func toggleRule(_ rule: ForwardRule) {
        guard let idx = config.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        config.rules[idx].enabled.toggle()
        save()
    }

    // MARK: - Settings

    func setMasterEnabled(_ enabled: Bool) {
        config.masterEnabled = enabled
        save()
    }

    func setDebugLogging(_ enabled: Bool) {
        config.debugLogging = enabled
        save()
    }
}
