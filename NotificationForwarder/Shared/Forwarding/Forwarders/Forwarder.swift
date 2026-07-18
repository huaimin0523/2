import Foundation

/// 转发器协议：把一条推送事件发送到具体目标。
///
/// 实现要点：
/// - 必须是同步阻塞的（在传入的 queue 上执行），由 Dispatcher 统一用并发队列调度。
/// - 任何异常必须捕获并写入 result.error，绝不能抛出到上层，避免 Extension 崩溃。
/// - 网络请求使用 URLSession + semaphore 等待，时间预算由 Dispatcher 控制。
public protocol Forwarder {
    /// 目标类型，用于工厂匹配。
    static var supportedType: ForwardTargetType { get }

    /// 执行转发。
    /// - Parameters:
    ///   - target: 目标配置
    ///   - event: 推送事件
    ///   - timeout: 网络请求超时秒数
    /// - Returns: 转发结果（成功 / 失败及原因）
    func forward(target: ForwardTarget, event: PushEventPayload, timeout: TimeInterval) -> ForwardResult
}

/// 转发结果。
public struct ForwardResult {
    public var success: Bool
    public var message: String
    public var statusCode: Int?

    public init(success: Bool, message: String, statusCode: Int? = nil) {
        self.success = success
        self.message = message
        self.statusCode = statusCode
    }

    public static func ok(_ message: String = "OK", statusCode: Int? = nil) -> ForwardResult {
        ForwardResult(success: true, message: message, statusCode: statusCode)
    }

    public static func fail(_ message: String, statusCode: Int? = nil) -> ForwardResult {
        ForwardResult(success: false, message: message, statusCode: statusCode)
    }
}

/// 转发器工厂：根据目标类型返回对应实现。
public enum ForwarderFactory {
    public static func make(for type: ForwardTargetType) -> Forwarder {
        switch type {
        case .webhook:        return WebhookForwarder()
        case .email:          return EmailForwarder()
        case .sms:            return SMSForwarder()
        case .thirdPartyApp:  return ThirdPartyAppForwarder()
        }
    }
}
