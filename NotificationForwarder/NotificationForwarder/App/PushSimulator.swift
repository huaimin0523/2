import Foundation
import UserNotifications

/// 本地推送模拟器。
///
/// **iOS 限制**：本地通知默认**不会**触发 `UNNotificationServiceExtension`。
/// 只有远程 APNs 推送（带 `mutable-content: 1`）才会触发。
///
/// 因此本模拟器采用两条腿走路：
///
/// 1. **尝试触发系统本地通知**（让用户看到通知 UI，但不会走 Extension）：
///    设置 1 秒延迟的 `UNTimeIntervalNotificationTrigger`，
///    `userInfo` 中塞入 `mutable-content: true`——某些 iOS 版本确实会触发 Extension。
///
/// 2. **直接调用 Dispatcher 模拟转发链路**（最可靠，不依赖系统）：
///    主 App 直接构造 `PushEventPayload` 并调用 `ForwarderDispatcher.dispatch`，
///    与 Extension 走完全一样的代码路径。
///    如果有附件 URL，主 App 会主动下载到共享容器，与 Extension 行为一致。
///
/// 在 TrollStore 安装环境下，方法 1 大概率不触发 Extension，
/// 但方法 2 一定能跑通——这就是本类的核心价值。
public final class PushSimulator {

    public static let shared = PushSimulator()

    private init() {}

    public func sendSimulated(
        title: String,
        body: String,
        attachmentURL: URL?,
        completion: @escaping (String) -> Void
    ) {
        // 1) 立即同步触发一次完整转发（直接走 Dispatcher，不依赖 Extension）
        DispatchQueue.global(qos: .userInitiated).async {
            var attachments: [PushAttachment] = []
            if let url = attachmentURL {
                if let localURL = self.downloadSync(url: url, timeout: 15) {
                    let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
                    attachments.append(PushAttachment(
                        localURL: localURL,
                        remoteURL: url,
                        mimeType: PushAttachment.inferMIME(from: url.lastPathComponent),
                        filename: url.lastPathComponent,
                        size: size
                    ))
                } else {
                    // 下载失败也保留 remoteURL
                    attachments.append(PushAttachment(
                        localURL: nil,
                        remoteURL: url,
                        mimeType: PushAttachment.inferMIME(from: url.lastPathComponent),
                        filename: url.lastPathComponent,
                        size: 0
                    ))
                }
            }

            let event = PushEventPayload(
                title: title,
                body: body,
                subtitle: "本地模拟",
                userInfo: ["simulated": "true"],
                receivedAt: Date(),
                sourceBundleID: Bundle.main.bundleIdentifier,
                attachments: attachments
            )

            let config = ConfigStore.shared.load()
            let dispatcher = ForwarderDispatcher()
            let outcome = dispatcher.dispatch(event: event, config: config)

            // 同步也写一条日志
            SharedLogger.shared.log("【模拟】转发完成：\(outcome.results.count)/\(outcome.matchedTargets.count) 条结果；跳过：\(outcome.skippedReason ?? "无")")
            for (target, result) in outcome.results {
                SharedLogger.shared.log("【模拟】目标[\(target.name)] success=\(result.success) msg=\(result.message)")
            }

            // 2) 同时尝试触发系统本地通知（让用户看到通知 UI）
            self.scheduleLocalNotification(title: title, body: body, attachmentURL: attachmentURL)

            // 3) 回到主线程汇报结果
            let summary: String
            if let skipped = outcome.skippedReason {
                summary = "已跳过：\(skipped)"
            } else if outcome.results.isEmpty {
                summary = "未匹配到任何目标，请先在“目标”页配置并启用至少一个转发目标。"
            } else {
                let lines = outcome.results.map { "• \($0.target.name)：\($0.result.success ? "✓" : "✗") \($0.result.message)" }
                summary = "转发结果：\n" + lines.joined(separator: "\n")
            }
            DispatchQueue.main.async { completion(summary) }
        }
    }

    /// 触发一条本地通知（系统会展示，但不保证触发 Extension）。
    private func scheduleLocalNotification(title: String, body: String, attachmentURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["mutable-content": true, "simulated": true]
        content.sound = .default

        // 尝试添加附件（系统会下载到自己的位置）
        if let url = attachmentURL {
            // 下载到临时文件
            if let local = downloadSync(url: url, timeout: 10) {
                let dir = FileManager.default.temporaryDirectory
                let dest = dir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: local, to: dest)
                // 系统支持的附件类型有限，部分 MIME 会被拒绝
                if let attachment = try? UNNotificationAttachment(identifier: UUID().uuidString, url: dest, options: nil) {
                    content.attachments = [attachment]
                }
            }
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "simulated-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// 同步下载到共享容器附件目录。
    private func downloadSync(url: URL, timeout: TimeInterval) -> URL? {
        guard let containerURL = ConfigStore.shared.sharedContainerURL else { return nil }
        let dir = containerURL.appendingPathComponent(AppConstants.attachmentDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = url.lastPathComponent.isEmpty ? "att_\(UUID().uuidString.prefix(8))" : url.lastPathComponent
        let dest = dir.appendingPathComponent(filename)

        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        let task = session.downloadTask(with: url) { tempURL, _, _ in
            if let tempURL {
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: tempURL, to: dest)
                success = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 2)
        return success ? dest : nil
    }
}
