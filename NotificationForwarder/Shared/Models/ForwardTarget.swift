import Foundation

/// 转发目标类型。每种类型对应一个 Forwarder 实现。
public enum ForwardTargetType: String, Codable, CaseIterable, Identifiable {
    case webhook          // 通用 HTTP Webhook
    case email            // 邮件（通过 SMTP/邮件 API）
    case sms              // 短信到另一个手机号（通过短信网关 API）
    case thirdPartyApp    // 第三方 App（Telegram / Slack / Discord 等）

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .webhook:        return "Webhook / API"
        case .email:          return "邮件"
        case .sms:            return "短信"
        case .thirdPartyApp:  return "第三方 App"
        }
    }

    /// 创建该类型目标时需要用户填写的字段提示。
    public var fieldHints: [String] {
        switch self {
        case .webhook:
            return ["Webhook URL", "自定义请求头（JSON，可选）", "认证 Token（可选）"]
        case .email:
            return ["SMTP 服务器", "端口", "发件邮箱", "发件密码 / 授权码", "收件邮箱"]
        case .sms:
            return ["网关 API Base URL（如 Twilio）", "Account SID / API Key", "Auth Token", "发件号码", "收件号码"]
        case .thirdPartyApp:
            return ["平台", "Bot Token / Webhook URL", "目标会话 ID / 频道"]
        }
    }
}

/// 单条转发目标配置。所有敏感字段以明文存储于 App Group 共享容器，
/// 实际生产建议结合 Keychain 共享访问存储 Token。
public struct ForwardTarget: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var type: ForwardTargetType
    public var enabled: Bool
    /// 类型相关参数。键名见 ForwardTargetKeys。
    public var params: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        type: ForwardTargetType,
        enabled: Bool = true,
        params: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.params = params
    }
}

/// 各类型目标在 params 字典里使用的键名。统一管理避免拼写错误。
public enum ForwardTargetKeys {
    // Webhook
    public static let webhookURL          = "webhookURL"
    public static let webhookHeaders      = "webhookHeaders"      // JSON 字符串
    public static let webhookAuthToken    = "webhookAuthToken"

    // Email
    public static let smtpHost            = "smtpHost"
    public static let smtpPort            = "smtpPort"
    public static let smtpUsername        = "smtpUsername"
    public static let smtpPassword        = "smtpPassword"
    public static let emailFrom           = "emailFrom"
    public static let emailTo             = "emailTo"

    // SMS
    public static let smsGatewayBaseURL   = "smsGatewayBaseURL"
    public static let smsAccountSID       = "smsAccountSID"
    public static let smsAuthToken        = "smsAuthToken"
    public static let smsFrom             = "smsFrom"
    public static let smsTo               = "smsTo"

    // Third-party App
    public static let appPlatform         = "appPlatform"      // telegram / slack / discord
    public static let appBotToken         = "appBotToken"
    public static let appChatID           = "appChatID"
}
