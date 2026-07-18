import Foundation

/// 邮件转发器：通过 HTTP 邮件 API 发送。
///
/// iOS Extension 无法使用 MessageUI（那是 UI 框架且需用户交互），
/// 也无法直接建立 SMTP 长连接（沙盒限制 outbound socket）。
/// 因此采用 Mailgun 兼容的 REST API：用户在 params 里配置 API 端点 + API Key。
///
/// 也支持任何兼容 Mailgun `domain/messages` 表单接口的服务（如自建 postal / mailcow）。
///
/// 配置示例（Mailgun）：
///   smtpHost     = https://api.mailgun.net/v3/sandboxxxx.mailgun.org
///   smtpUsername = api
///   smtpPassword = <API Key>
///   emailFrom    = forwarder@sandboxxxx.mailgun.org
///   emailTo      = you@example.com
///
/// 附件：Mailgun `messages` 接口支持 multipart 表单的 `attachment` 字段（可重复），
/// 我们把所有本地附件都附上。仅远程 URL 的附件会在正文末尾列出链接。
public struct EmailForwarder: Forwarder {
    public static let supportedType: ForwardTargetType = .email

    public init() {}

    public func forward(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult {
        let baseURLString = target.params[ForwardTargetKeys.smtpHost] ?? ""
        guard !baseURLString.isEmpty else {
            return .fail("邮件 API 端点未配置")
        }
        let url = URL(string: baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                       + "/messages")
        guard let url else { return .fail("邮件 API URL 非法") }

        let from = target.params[ForwardTargetKeys.emailFrom] ?? ""
        let to = target.params[ForwardTargetKeys.emailTo] ?? ""
        guard !from.isEmpty, !to.isEmpty else { return .fail("发件/收件邮箱未配置") }

        let subject = "[推送转发] \(event.title.isEmpty ? String(event.body.prefix(40)) : event.title)"

        // 正文：基础信息 + 仅远程 URL 的附件链接
        var text = """
        收到一条推送通知：

        标题：\(event.title)
        副标题：\(event.subtitle)
        正文：\(event.body)
        时间：\(ISO8601DateFormatter().string(from: event.receivedAt))
        来源 App：\(event.sourceBundleID ?? "未知")

        原始 userInfo：
        \(event.userInfo)
        """
        let remoteOnlyURLs = event.attachments
            .filter { $0.localURL == nil }
            .compactMap { $0.remoteURL?.absoluteString }
        if !remoteOnlyURLs.isEmpty {
            text += "\n\n仅远程的附件链接：\n" + remoteOnlyURLs.joined(separator: "\n")
        }

        let mp = MultipartBuilder()
        mp.append(field: "from", value: from)
        mp.append(field: "to", value: to)
        mp.append(field: "subject", value: String(subject))
        mp.append(field: "text", value: text)

        // 添加本地附件（Mailgun 使用 attachment 字段，可多次出现）
        var attachedCount = 0
        for att in event.attachments where att.localURL != nil {
            if mp.appendFile(field: "attachment", fileURL: att.localURL!, mimeType: att.mimeType, filename: att.filename) {
                attachedCount += 1
            }
        }

        let bodyData = mp.build()
        let headers = ["Content-Type": mp.contentType]
        let user = target.params[ForwardTargetKeys.smtpUsername] ?? "api"
        let pwd = target.params[ForwardTargetKeys.smtpPassword] ?? ""

        let resp = SyncHTTP.request(
            url: url,
            method: .post,
            headers: headers,
            body: bodyData,
            timeout: timeout,
            basicAuthUser: user,
            basicAuthPassword: pwd
        )
        if let error = resp.error {
            return .fail("网络错误：\(error.localizedDescription)")
        }
        if (resp.statusCode / 100) == 2 {
            return .ok("HTTP \(resp.statusCode) (附件 \(attachedCount))", statusCode: resp.statusCode)
        }
        return .fail("邮件服务返回 HTTP \(resp.statusCode)", statusCode: resp.statusCode)
    }
}
