import Foundation

/// 推送附件统一表示。
///
/// 附件有两种来源：
/// 1. **系统已下载**：payload 使用标准 `attachment-url` 字段，iOS 自动下载到
///    `UNNotificationAttachment.url`，`localURL` 非空、`remoteURL` 为 nil。
/// 2. **远程 URL**：用户在 payload 自定义字段里塞了图片/文件 URL（如 `image`、`file-url`），
///    Extension 在 `didReceive` 里手动下载到临时目录，`localURL` 指向临时文件，
///    `remoteURL` 保留原始链接（便于目标方直接拉取）。
public struct PushAttachment: Codable, Equatable {
    /// 本地文件 URL（沙盒可访问）。转发时从这里读取数据上传。
    /// 可能为 nil（下载失败 / 仅知道远程 URL 时），此时转发器只能用 remoteURL。
    public var localURL: URL?
    /// 远程原始 URL。某些目标（如 SMS）可以直接把链接塞进正文。
    public var remoteURL: URL?
    /// MIME 类型，例如 image/jpeg。无法识别时为 application/octet-stream。
    public var mimeType: String
    /// 文件名（含扩展名）。
    public var filename: String
    /// 字节大小，可读但可能为 0（流式下载未确定）。
    public var size: Int64

    public init(localURL: URL?, remoteURL: URL?, mimeType: String, filename: String, size: Int64 = 0) {
        self.localURL = localURL
        self.remoteURL = remoteURL
        self.mimeType = mimeType
        self.filename = filename
        self.size = size
    }

    /// 是否为图片（用于决定 Telegram 走 sendPhoto 还是 sendDocument）。
    public var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    /// 是否为视频。
    public var isVideo: Bool {
        mimeType.hasPrefix("video/")
    }

    /// 是否为音频。
    public var isAudio: Bool {
        mimeType.hasPrefix("audio/")
    }

    /// 简单从 URL/文件名推断 MIME。
    public static func inferMIME(from filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "heic":        return "image/heic"
        case "mp4", "m4v":  return "video/mp4"
        case "mov":         return "video/quicktime"
        case "mp3":         return "audio/mpeg"
        case "m4a":         return "audio/mp4"
        case "aac":         return "audio/aac"
        case "pdf":         return "application/pdf"
        case "zip":         return "application/zip"
        case "txt":         return "text/plain"
        case "json":        return "application/json"
        default:            return "application/octet-stream"
        }
    }
}
