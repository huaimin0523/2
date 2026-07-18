import Foundation

/// 第三方 App 转发器：Telegram Bot / Slack Webhook / Discord Webhook。
///
/// iOS 无法替你向其他 App（微信 / Telegram 等）"自动发消息"——
/// 这些都是其他 App 的沙盒，跨进程通信被严格禁止。
/// 但这些平台都提供官方 Bot / Incoming Webhook，可通过 HTTP API 发送。
///
/// 附件支持：
/// - **Telegram**：原生 multipart 上传图片（sendPhoto）/ 文件（sendDocument）。
///   多个附件会逐个发送（Telegram 一次只接收一个文件）。
/// - **Slack / Discord**：Incoming Webhook 不支持二进制上传，
///   退化为把附件的 remoteURL 作为文本链接附在消息里。
///   若仅有本地文件，会在消息里提示 "[未上传本地附件: filename]"。
public struct ThirdPartyAppForwarder: Forwarder {
    public static let supportedType: ForwardTargetType = .thirdPartyApp

    public init() {}

    public func forward(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult {
        let platform = (target.params[ForwardTargetKeys.appPlatform] ?? "").lowercased()
        switch platform {
        case "telegram":
            return sendTelegram(target: target, event: event, timeout: timeout)
        case "slack":
            return sendSlack(target: target, event: event, timeout: timeout)
        case "discord":
            return sendDiscord(target: target, event: event, timeout: timeout)
        default:
            return .fail("未知第三方平台：\(platform)。支持 telegram / slack / discord")
        }
    }

    // MARK: - Telegram Bot API
    /// Telegram 策略：先发送一条文本消息（带标题+正文），再逐个发送附件。
    /// 图片走 sendPhoto，其他走 sendDocument。
    private func sendTelegram(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult {
        let token = target.params[ForwardTargetKeys.appBotToken] ?? ""
        let chatID = target.params[ForwardTargetKeys.appChatID] ?? ""
        guard !token.isEmpty, !chatID.isEmpty else {
            return .fail("Telegram Bot Token / Chat ID 未配置")
        }

        // 1) 发送文本
        let textURLStr = "https://api.telegram.org/bot\(token)/sendMessage"
        guard let textURL = URL(string: textURLStr) else {
            return .fail("Telegram URL 非法")
        }
        let text = """
        *\(escapeMarkdown(event.title.isEmpty ? "（无标题）" : event.title))*
        \(escapeMarkdown(event.body))

        _\(escapeMarkdown(event.sourceBundleID ?? "未知")) · \(ISO8601DateFormatter().string(from: event.receivedAt))_
        """
        let textBody: [String: Any] = [
            "chat_id": chatID,
            "text": text,
            "parse_mode": "MarkdownV2",
            "disable_web_page_preview": true
        ]
        guard let textData = try? JSONSerialization.data(withJSONObject: textBody) else {
            return .fail("Telegram 文本请求体序列化失败")
        }
        let textResp = SyncHTTP.request(
            url: textURL, method: .post,
            headers: ["Content-Type": "application/json"],
            body: textData, timeout: timeout
        )
        if !isSuccess(textResp) {
            return result(from: textResp, platform: "Telegram(text)")
        }

        // 2) 逐个发送附件
        var attachmentResults: [String] = []
        for att in event.attachments {
            let r = sendOneTelegramAttachment(
                token: token, chatID: chatID, attachment: att, timeout: timeout
            )
            attachmentResults.append(r.success ? "✓\(att.filename)" : "✗\(att.filename)")
        }

        let summary = attachmentResults.isEmpty ? "无附件" : attachmentResults.joined(separator: " ")
        if isSuccess(textResp) {
            return .ok("Telegram OK，附件：\(summary)", statusCode: textResp.statusCode)
        }
        return result(from: textResp, platform: "Telegram")
    }

    /// 发送单个 Telegram 附件。
    /// 优先用本地文件 multipart 上传；本地文件缺失时尝试用 remoteURL 的 sendPhoto?url 模式。
    private func sendOneTelegramAttachment(
        token: String, chatID: String, attachment: PushAttachment, timeout: TimeInterval
    ) -> ForwardResult {
        let apiName = attachment.isImage ? "sendPhoto" : "sendDocument"
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(apiName)") else {
            return .fail("Telegram URL 非法")
        }

        // 路径 A：本地文件 multipart 上传
        if let localURL = attachment.localURL {
            let mp = MultipartBuilder()
            mp.append(field: "chat_id", value: chatID)
            mp.appendFile(
                field: attachment.isImage ? "photo" : "document",
                fileURL: localURL,
                mimeType: attachment.mimeType,
                filename: attachment.filename
            )
            let bodyData = mp.build()
            let resp = SyncHTTP.request(
                url: url, method: .post,
                headers: ["Content-Type": mp.contentType],
                body: bodyData, timeout: timeout
            )
            return result(from: resp, platform: "Telegram(\(apiName))")
        }

        // 路径 B：仅远程 URL，使用 URL 模式（Telegram 服务端会去下载）
        if let remoteURL = attachment.remoteURL {
            let body: [String: Any] = [
                "chat_id": chatID,
                attachment.isImage ? "photo" : "document": remoteURL.absoluteString
            ]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                return .fail("请求体序列化失败")
            }
            let resp = SyncHTTP.request(
                url: url, method: .post,
                headers: ["Content-Type": "application/json"],
                body: bodyData, timeout: timeout
            )
            return result(from: resp, platform: "Telegram(\(apiName)-url)")
        }

        return .fail("附件无本地文件也无远程 URL")
    }

    // MARK: - Slack Incoming Webhook
    private func sendSlack(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult {
        guard let urlString = target.params[ForwardTargetKeys.appBotToken],
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return .fail("Slack Webhook URL 未配置（填入 appBotToken 字段）")
        }
        var fields: [[String: Any]] = []
        if !event.title.isEmpty {
            fields.append(["type": "mrkdwn", "text": "*\(event.title)*"])
        }
        fields.append(["type": "mrkdwn", "text": event.body])
        // 附件链接
        let attLines = event.attachments.compactMap { att -> String? in
            if let r = att.remoteURL?.absoluteString { return "<\(r)|\(att.filename)>" }
            return "_[未上传本地附件: \(att.filename)]_"
        }
        if !attLines.isEmpty {
            fields.append(["type": "mrkdwn", "text": "附件：\n" + attLines.joined(separator: "\n")])
        }
        let body: [String: Any] = [
            "text": "推送转发",
            "blocks": [["type": "section", "fields": fields]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .fail("Slack 请求体序列化失败")
        }
        let headers = ["Content-Type": "application/json"]
        let resp = SyncHTTP.request(url: url, method: .post, headers: headers, body: bodyData, timeout: timeout)
        return result(from: resp, platform: "Slack")
    }

    // MARK: - Discord Webhook
    private func sendDiscord(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult {
        guard let urlString = target.params[ForwardTargetKeys.appBotToken],
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return .fail("Discord Webhook URL 未配置（填入 appBotToken 字段）")
        }
        var description = event.body
        let attLines = event.attachments.compactMap { att -> String? in
            if let r = att.remoteURL?.absoluteString { return "[\(att.filename)](\(r))" }
            return "_[未上传本地附件: \(att.filename)]_"
        }
        if !attLines.isEmpty {
            description += "\n\n附件：\n" + attLines.joined(separator: "\n")
        }
        let body: [String: Any] = [
            "username": "推送转发",
            "embeds": [[
                "title": event.title.isEmpty ? "（无标题）" : event.title,
                "description": description,
                "footer": ["text": "来源：\(event.sourceBundleID ?? "未知")"],
                "timestamp": ISO8601DateFormatter().string(from: event.receivedAt)
            ]]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return .fail("Discord 请求体序列化失败")
        }
        let headers = ["Content-Type": "application/json"]
        let resp = SyncHTTP.request(url: url, method: .post, headers: headers, body: bodyData, timeout: timeout)
        return result(from: resp, platform: "Discord")
    }

    // MARK: - Helpers
    private func isSuccess(_ resp: SyncHTTP.Response) -> Bool {
        resp.error == nil && (resp.statusCode / 100) == 2
    }

    private func result(from resp: SyncHTTP.Response, platform: String) -> ForwardResult {
        if let error = resp.error {
            return .fail("\(platform) 网络错误：\(error.localizedDescription)")
        }
        if (resp.statusCode / 100) == 2 {
            return .ok("\(platform) HTTP \(resp.statusCode)", statusCode: resp.statusCode)
        }
        return .fail("\(platform) 返回 HTTP \(resp.statusCode)", statusCode: resp.statusCode)
    }

    /// MarkdownV2 转义。
    private func escapeMarkdown(_ s: String) -> String {
        let special: [Character] = ["_", "*", "[", "]", "(", ")", "~", "`", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!"]
        var out = ""
        for ch in s {
            if special.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
