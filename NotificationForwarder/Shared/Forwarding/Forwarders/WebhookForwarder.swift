import Foundation

/// 通用 Webhook 转发器：把推送事件以 JSON POST 发送到任意 URL。
/// 兼容企业微信 / 飞书 / 钉钉 / 自建服务等大多数 webhook 形态。
///
/// 当推送包含附件时：
/// - 若所有附件都有本地文件 → 用 `multipart/form-data` 上传：
///   - 字段 `event`：JSON 字符串（与无附件时的 body 一致）
///   - 字段 `files[]`：每个附件一份
/// - 若仅知道远程 URL（下载失败） → 退化为 JSON 模式，把 remoteURL 放进 event.attachments
public struct WebhookForwarder: Forwarder {
    public static let supportedType: ForwardTargetType = .webhook

    public init() {}

    public func forward(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult {
        guard let urlString = target.params[ForwardTargetKeys.webhookURL],
              !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return .fail("Webhook URL 未配置或非法")
        }

        // 构造事件 JSON
        let body: [String: Any] = [
            "event": "push_notification",
            "title": event.title,
            "body": event.body,
            "subtitle": event.subtitle,
            "receivedAt": ISO8601DateFormatter().string(from: event.receivedAt),
            "source": event.sourceBundleID ?? NSNull(),
            "userInfo": event.userInfo,
            "attachments": event.attachments.map { att in
                [
                    "filename": att.filename,
                    "mimeType": att.mimeType,
                    "size": att.size,
                    "remoteURL": att.remoteURL?.absoluteString ?? NSNull()
                ] as [String: Any]
            }
        ]

        // 默认请求头
        var headers: [String: String] = [
            "User-Agent": "NotificationForwarder/1.0 iOS"
        ]
        // 用户自定义请求头
        if let customHeadersJSON = target.params[ForwardTargetKeys.webhookHeaders],
           !customHeadersJSON.isEmpty,
           let data = customHeadersJSON.data(using: .utf8),
           let custom = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            for (k, v) in custom { headers[k] = v }
        }
        // 认证 Token
        if let token = target.params[ForwardTargetKeys.webhookAuthToken], !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }

        // 区分有附件 / 无附件两种上传方式
        let localAttachments = event.attachments.filter { $0.localURL != nil }

        if localAttachments.isEmpty {
            // 纯 JSON
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                return .fail("请求体序列化失败")
            }
            headers["Content-Type"] = "application/json"
            let resp = SyncHTTP.request(url: url, method: .post, headers: headers, body: bodyData, timeout: timeout)
            return toResult(resp, label: "Webhook")
        } else {
            // multipart 上传
            let mp = MultipartBuilder()
            mp.appendJSON(field: "event", json: body)
            for att in localAttachments {
                guard let localURL = att.localURL else { continue }
                mp.appendFile(
                    field: "files[]",
                    fileURL: localURL,
                    mimeType: att.mimeType,
                    filename: att.filename
                )
            }
            let bodyData = mp.build()
            headers["Content-Type"] = mp.contentType
            let resp = SyncHTTP.request(url: url, method: .post, headers: headers, body: bodyData, timeout: timeout)
            return toResult(resp, label: "Webhook(附件)")
        }
    }

    private func toResult(_ resp: SyncHTTP.Response, label: String) -> ForwardResult {
        if let error = resp.error {
            return .fail("\(label) 网络错误：\(error.localizedDescription)")
        }
        if (resp.statusCode / 100) == 2 {
            return .ok("\(label) HTTP \(resp.statusCode)", statusCode: resp.statusCode)
        }
        return .fail("\(label) 返回 HTTP \(resp.statusCode)", statusCode: resp.statusCode)
    }
}
