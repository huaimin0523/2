import Foundation

/// 整个 App 的可序列化配置根对象。
public struct AppConfig: Codable, Equatable {
    public var targets: [ForwardTarget]
    public var rules: [ForwardRule]
    /// 全局开关：关闭后 Extension 不再转发任何推送。
    public var masterEnabled: Bool
    /// 调试模式：把每次转发结果写入共享容器日志文件。
    public var debugLogging: Bool

    public init(
        targets: [ForwardTarget] = [],
        rules: [ForwardRule] = [],
        masterEnabled: Bool = true,
        debugLogging: Bool = false
    ) {
        self.targets = targets
        self.rules = rules
        self.masterEnabled = masterEnabled
        self.debugLogging = debugLogging
    }

    public static let empty = AppConfig()
}
