import Foundation
import UserNotifications

/// 附件采集器：从 `UNNotificationContent.attachments` 和自定义字段中
/// 把附件整理成 `PushAttachment` 列表。
///
/// 两种来源：
/// 1. **系统标准附件**：payload 用 `attachment-url` 字段，iOS 已下载到本地。
///    `UNNotificationAttachment.url` 可直接读，但文件可能位于系统目录，
///    Extension 进程通常可访问。
/// 2. **自定义远程 URL**：在 userInfo 里塞了 `image` / `file-url` / `media-url`
///    等字段（任意 URL 字符串），Extension 主动下载到自己的临时目录。
public enum AttachmentCollector {

    /// 在 userInfo 中查找远程附件 URL 的字段名（不区分大小写）。
    public static let remoteURLKeys = [
        "image", "image-url", "imageUrl",
        "media", "media-url", "mediaUrl",
        "file", "file-url", "fileUrl",
        "attachment-url", "attachmentUrl"
    ]

    /// 收集所有附件（系统 + 远程）。同步阻塞，最长 waitSecs 秒。
    public static func collect(
        from content: UNNotificationContent,
        userInfoStrings: [String: String],
        downloadTimeoutPerFile: TimeInterval = 10,
        maxFiles: Int = 5
    ) -> [PushAttachment] {
        var result: [PushAttachment] = []

        // 1) 系统已下载的附件
        for att in content.attachments.prefix(maxFiles) {
            let url = att.url
            // typeIdentifier 是 UTI（如 public.jpeg），不是 MIME；统一用文件名推断 MIME 更可靠
            let mime = PushAttachment.inferMIME(from: url.lastPathComponent)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            result.append(PushAttachment(
                localURL: url,
                remoteURL: nil,
                mimeType: mime,
                filename: url.lastPathComponent,
                size: size
            ))
            if result.count >= maxFiles { return result }
        }

        // 2) 远程 URL 手动下载
        let remoteURLs = collectRemoteURLs(from: userInfoStrings)
        for remoteURL in remoteURLs {
            if result.count >= maxFiles { break }
            if let local = downloadSync(url: remoteURL, timeout: downloadTimeoutPerFile) {
                let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? Int64) ?? 0
                result.append(PushAttachment(
                    localURL: local,
                    remoteURL: remoteURL,
                    mimeType: PushAttachment.inferMIME(from: local.lastPathComponent),
                    filename: local.lastPathComponent,
                    size: size
                ))
            } else {
                // 下载失败也保留 remote URL，转发器可退化为链接
                result.append(PushAttachment(
                    localURL: nil,
                    remoteURL: remoteURL,
                    mimeType: PushAttachment.inferMIME(from: remoteURL.lastPathComponent),
                    filename: remoteURL.lastPathComponent,
                    size: 0
                ))
            }
        }

        return result
    }

    /// 从 userInfo 字典里提取所有远程 URL（去重）。
    private static func collectRemoteURLs(from userInfo: [String: String]) -> [URL] {
        var seen = Set<String>()
        var urls: [URL] = []
        for (key, value) in userInfo {
            let lowerKey = key.lowercased()
            guard remoteURLKeys.contains(lowerKey) else { continue }
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { continue }
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    /// 同步下载到 Extension 临时目录。返回本地 URL。
    private static func downloadSync(url: URL, timeout: TimeInterval) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("NFAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let filename = url.lastPathComponent.isEmpty
            ? "attachment_\(UUID().uuidString.prefix(8))"
            : url.lastPathComponent
        let dest = tempDir.appendingPathComponent(filename)

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
