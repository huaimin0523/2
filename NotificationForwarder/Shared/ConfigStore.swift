import Foundation

/// 主 App 与 Extension 共享的配置存储。
///
/// 通过 App Group 容器目录共享一份 JSON 配置文件：
/// - 主 App 写入用户在 UI 中配置的 targets / rules
/// - Extension 在推送到达时读取这份配置并执行转发
///
/// 文件读写均加了协调锁（NSFileCoordinator），防止并发损坏。
public final class ConfigStore {
    public static let shared = ConfigStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// App Group 共享容器 URL。若获取失败（未配置 App Group），返回 nil。
    public var sharedContainerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)
    }

    /// 共享配置文件 URL。
    public var configFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(AppConstants.configFileName)
    }

    /// 加载配置。读取失败时返回空配置（不抛错，保证 Extension 永不崩溃）。
    public func load() -> AppConfig {
        guard let url = configFileURL,
              fileManager.fileExists(atPath: url.path) else {
            return .empty
        }
        var coordinationError: NSError?
        var readError: Error?
        var data: Data?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { newURL in
            do { data = try Data(contentsOf: newURL) }
            catch { readError = error }
        }
        if let coordinationError { return .empty }
        if let readError { return .empty }
        guard let data, !data.isEmpty else { return .empty }
        do { return try decoder.decode(AppConfig.self, from: data) }
        catch { return .empty }
    }

    /// 保存配置（主 App 调用）。失败时抛出错误，让 UI 提示用户。
    public func save(_ config: AppConfig) throws {
        guard let url = configFileURL else {
            throw ConfigError.appGroupUnavailable
        }
        let data = try encoder.encode(config)
        var coordinationError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { newURL in
            do {
                try data.write(to: newURL, options: [.atomic])
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw ConfigError.coordinationFailed(coordinationError) }
        if let writeError { throw writeError }
    }

    public enum ConfigError: Error, LocalizedError {
        case appGroupUnavailable
        case coordinationFailed(NSError)

        public var errorDescription: String? {
            switch self {
            case .appGroupUnavailable:
                return "App Group 容器不可用。请确认：\n" +
                       "1. TrollStore 安装时，IPA 内主 App 与 Extension 的 entitlements 都声明了相同的 group ID\n" +
                       "2. 重启一次设备（首次安装 App Group 后偶尔需要重启才生效）\n" +
                       "3. App Group ID = \(AppConstants.appGroupID)"
            case .coordinationFailed(let err):
                return "文件协调失败：\(err.localizedDescription)"
            }
        }
    }
}
