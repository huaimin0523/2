import Foundation

/// 短信转发器：通过 SMS 网关 HTTP API 发送到另一个手机号。
///
/// iOS 沙盒中：
/// - 不能用 MFMessageComposeViewController（UI 框架，且需用户点击发送）
/// - 不能直接读取/发送系统 SMS
/// 因此必须借助 Twilio / 阿里云短信 / 腾讯云短信 / 网易云信 等 HTTP 网关。
///
/// 默认实现 Twilio 兼容协议：
///   POST {baseURL}/Accounts/{SID}/Messages.json
///   Basic Auth: {SID}:{AuthToken}
///   form: From / To / Body / MediaUrl（可重复，Twilio 会下载并作为 MMS 发送）
///
/// 附件处理：
/// - 有 `remoteURL` 的附件 → 直接作为 MediaUrl 提交给 Twilio（Twilio 服务端会去下载）
/// - 仅有本地文件、无远程 URL → 退化为在正文末尾追加 "[附件 N: filename]"
///   （Twilio 无法接收客户端上传的二进制，需要先用其他接口把文件放到公网）
///
/// 配置：
///   smsGatewayBaseURL = https://api.twilio.com/2010-04-01
///   smsAccountSID     = ACxxxx
///   smsAuthToken      = <token>
///   smsFrom           = +1xxxxxxxxxx  或 messaging-service-sid
///   smsTo             = +861xxxxxxxxxx
public struct SMSForwarder: Forwarder {
    public static let supportedType: ForwardTargetType = .sms

    public init() {}

    public func forward(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult {
        let base = (target.params[ForwardTargetKeys.smsGatewayBaseURL] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let sid = target.params[ForwardTargetKeys.smsAccountSID] ?? ""
        guard !base.isEmpty, !sid.isEmpty else {
            return .fail("短信网关 BaseURL / SID 未配置")
        }
        let urlString = "\(base)/Accounts/\(sid)/Messages.json"
        guard let url = URL(string: urlString) else { return .fail("短信网关 URL 非法") }

        let from = target.params[ForwardTargetKeys.smsFrom] ?? ""
        let to = target.params[ForwardTargetKeys.smsTo] ?? ""
        guard !from.isEmpty, !to.isEmpty else { return .fail("发件/收件号码未配置") }

        let title = event.title.isEmpty ? "" : "【\(event.title)】"
        var bodyText = String("\(title)\(event.body)")

        // 远程附件 URL：作为 MediaUrl 提交（Twilio 会下载并以 MMS 发送）
        let mediaURLs = event.attachments.compactMap { $0.remoteURL?.absoluteString }

        // 仅本地的附件：在正文末尾标注
        let localOnlyFiles = event.attachments.filter { $0.localURL != nil && $0.remoteURL == nil }
        if !localOnlyFiles.isEmpty {
            bodyText += " [本地附件: \(localOnlyFiles.map { $0.filename }.joined(separator: ","))]"
        }
        let body = String(bodyText.prefix(1500)) // Twilio 单条 GSM 编码 1600 字符上限
        let token = target.params[ForwardTargetKeys.smsAuthToken] ?? ""

        let mp = MultipartBuilder()
        mp.append(field: "From", value: from)
        mp.append(field: "To", value: to)
        mp.append(field: "Body", value: body)
        for mediaURL in mediaURLs {
            mp.append(field: "MediaUrl", value: mediaURL)
        }
        let bodyData = mp.build()
        let headers = ["Content-Type": mp.contentType]

        let resp = SyncHTTP.request(
            url: url,
            method: .post,
            headers: headers,
            body: bodyData,
            timeout: timeout,
            basicAuthUser: sid,
            basicAuthPassword: token
        )
        if let error = resp.error {
            return .fail("网络错误：\(error.localizedDescription)")
        }
        if (resp.statusCode / 100) == 2 {
            return .ok("HTTP \(resp.statusCode) (MMS 媒体 \(mediaURLs.count))", statusCode: resp.statusCode)
        }
        return .fail("短信网关返回 HTTP \(resp.statusCode)", statusCode: resp.statusCode)
    }
}
