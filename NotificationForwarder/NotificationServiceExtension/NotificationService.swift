import UserNotifications
import Foundation

/// Notification Service Extension 入口。
///
/// 当推送 payload 包含 `"mutable-content": 1` 时，iOS 会在展示通知前
/// 实例化本类并调用 `didReceive(_:withContentHandler:)`，给你最多约 30 秒
/// 处理时间。我们在此处：
///   1. 从 payload 构造 PushEventPayload
///   2. 从 App Group 加载配置
///   3. 并发转发到所有匹配目标
///   4. 调用 contentHandler 回传（原样或附加调试信息）
///
/// 注意：
/// - 必须 always 在 deadline 前回调 contentHandler，否则系统会丢弃通知。
/// - contentHandler 只能调用一次。
class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        // 兜底定时器：到 25 秒强制回调，避免超时被系统丢弃。
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.finish()
        }

        // 1) 解析事件
        let content = request.content
        let userInfoStrings = content.userInfo.compactMapValues { value -> String? in
            if let s = value as? String { return s }
            if let data = try? JSONSerialization.data(withJSONObject: value),
               let s = String(data: data, encoding: .utf8) { return s }
            return nil
        }

        // 1.5) 采集附件：系统已下载的 + 自定义字段里的远程 URL 手动下载
        let attachments = AttachmentCollector.collect(
            from: content,
            userInfoStrings: userInfoStrings
        )
        if !attachments.isEmpty {
            SharedLogger.shared.log("采集到 \(attachments.count) 个附件：\(attachments.map { "\($0.filename)(\($0.mimeType), \($0.localURL != nil ? "本地" : "仅远程"))" }.joined(separator: ", "))")
        }

        let event = PushEventPayload(
            title: content.title,
            body: content.body,
            subtitle: content.subtitle,
            badge: content.badge?.intValue,
            sound: content.sound as? String,
            userInfo: userInfoStrings,
            receivedAt: Date(),
            sourceBundleID: request.content.threadIdentifier.isEmpty ? nil : request.content.threadIdentifier,
            attachments: attachments
        )

        // 2) 加载配置
        let config = ConfigStore.shared.load()

        // 3) 分发
        let dispatcher = ForwarderDispatcher()
        let outcome = dispatcher.dispatch(event: event, config: config)

        // 4) 日志（仅 debug）
        SharedLogger.shared.log("推送转发完成：\(outcome.results.count)/\(outcome.matchedTargets.count) 条结果；跳过原因：\(outcome.skippedReason ?? "无")")
        for (target, result) in outcome.results {
            SharedLogger.shared.log("目标[\(target.name)] success=\(result.success) msg=\(result.message)")
        }

        // 5) 调试模式：把转发摘要附到通知副标题
        if config.debugLogging, let best = bestAttemptContent {
            let summary = outcome.results.map { "\($0.target.name): \($0.result.success ? "✓" : "✗")" }.joined(separator: "  ")
            if !summary.isEmpty {
                best.subtitle = summary
            }
        }

        finish()
    }

    /// 系统即将卸载扩展（罕见），尽快回调。
    override func serviceExtensionTimeWillExpire() {
        finish()
    }

    /// 幂等回调。只调用一次 contentHandler。
    private func finish() {
        guard let handler = contentHandler else { return }
        self.contentHandler = nil
        handler(bestAttemptContent ?? UNNotificationContent())
    }
}
