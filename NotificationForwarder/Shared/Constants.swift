import Foundation

/// 全局常量。
///
/// **共享存储策略**：
/// 主 App 与 Notification Service Extension 通过 **App Group** 共享配置文件。
/// App Group 是 iOS 唯一允许 Extension 与主 App 共享本地数据的官方机制
/// （UserDefaults.standard 和本地文件在 Extension 进程中都是隔离的）。
///
/// **TrollStore 安装说明**：
/// TrollStore 通过 CoreTrust bypass 安装，**支持任意 entitlements**（不需要在
/// Apple Developer 后台注册 App Group ID）。只要在 entitlements 文件里声明：
///
/// ```
/// <key>com.apple.security.application-groups</key>
/// <array>
///     <string>group.com.notificationforwarder.shared</string>
/// </array>
/// ```
///
/// 主 App 和 Extension 两个 Target 的 entitlements 都声明同一个 group，
/// iOS 就会为它们创建并暴露同一个共享容器目录。
///
/// 注意：免费 Apple ID + Xcode 自动签名不支持任意 App Group，必须付费账号或 TrollStore。
public enum AppConstants {

    /// App Group 标识符。主 App 与 Extension 共享此容器。
    /// **请勿修改**——entitlements 文件里必须与此完全一致。
    public static let appGroupID = "group.com.notificationforwarder.shared"

    /// 共享配置文件名（存放在 App Group 容器内）。
    public static let configFileName = "forward_config.json"

    /// 调试日志文件名（存放在 App Group 容器内）。
    public static let logFileName = "forward.log.jsonl"

    /// 附件临时目录名（存放在 App Group 容器内，两个进程都能读写）。
    public static let attachmentDirName = "NFAttachments"
}
