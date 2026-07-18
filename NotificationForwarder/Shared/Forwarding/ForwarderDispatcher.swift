import Foundation

/// 推送事件分发器：根据配置 + 规则，并发地把事件转发到所有匹配的目标。
///
/// 设计要点：
/// 1. Extension 仅有约 30 秒预算，必须并发执行。
/// 2. 每个目标独立调度，互不影响；任意一个失败不影响其他。
/// 3. 单个目标设独立超时（默认 15s），避免拖垮整体。
/// 4. 全程使用同步 API + DispatchGroup 等待所有任务结束。
public final class ForwarderDispatcher {

    public init() {}

    /// 单个目标默认超时。
    public var perTargetTimeout: TimeInterval = 15

    /// 整体最大等待时长，留出余量回调 contentHandler。
    public var totalBudget: TimeInterval = 25

    public struct DispatchOutcome {
        public var results: [(target: ForwardTarget, result: ForwardResult)]
        public var matchedTargets: [ForwardTarget]
        public var skippedReason: String?
    }

    /// 执行一次完整转发流程。
    public func dispatch(event: PushEventPayload, config: AppConfig) -> DispatchOutcome {
        // 主开关
        guard config.masterEnabled else {
            return DispatchOutcome(results: [], matchedTargets: [], skippedReason: "全局开关已关闭")
        }

        // 选出匹配的目标
        let matched = matchedTargets(for: event, config: config)
        if matched.isEmpty {
            return DispatchOutcome(results: [], matchedTargets: [], skippedReason: "无规则匹配 / 无启用目标")
        }

        // 并发执行
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.nf.dispatch", attributes: .concurrent)
        let lock = NSLock()
        var results: [(ForwardTarget, ForwardResult)] = []

        for target in matched {
            group.enter()
            queue.async {
                let forwarder = ForwarderFactory.make(for: target.type)
                let result = forwarder.forward(target: target, event: event, timeout: self.perTargetTimeout)
                lock.lock()
                results.append((target, result))
                lock.unlock()
                group.leave()
            }
        }

        let deadline = DispatchTime.now() + totalBudget
        _ = group.wait(timeout: deadline)

        return DispatchOutcome(results: results, matchedTargets: matched, skippedReason: nil)
    }

    /// 选出本次需要转发的目标。
    /// 规则匹配顺序：若至少有一条规则匹配，则按规则中的 targetIDs 选择；
    /// 若没有规则匹配但存在启用目标，则转发给所有启用目标（"无规则即转发全部"策略）。
    private func matchedTargets(for event: PushEventPayload, config: AppConfig) -> [ForwardTarget] {
        let enabledTargets = config.targets.filter { $0.enabled }

        let matchedRules = config.rules.filter {
            $0.enabled && $0.matches(title: event.title, body: event.body, sourceBundleID: event.sourceBundleID)
        }

        if matchedRules.isEmpty {
            return enabledTargets
        }

        // 合并所有匹配规则指定的目标 ID；空 targetIDs 表示"全部启用目标"
        var specificIDs = Set<UUID>()
        var anyRuleMeansAll = false
        for rule in matchedRules {
            if rule.targetIDs.isEmpty {
                anyRuleMeansAll = true
                break
            }
            specificIDs.formUnion(rule.targetIDs)
        }
        if anyRuleMeansAll { return enabledTargets }
        return enabledTargets.filter { specificIDs.contains($0.id) }
    }
}
