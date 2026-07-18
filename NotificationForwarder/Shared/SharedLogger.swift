import Foundation

/// 调试日志：写入 App Group 共享容器内的 log.jsonl（每行一条 JSON）。
/// Extension 进程无法用 Console.app 方便查看，落盘便于主 App 在设置页查看。
public final class SharedLogger {
    public static let shared = SharedLogger()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.notificationforwarder.logger")

    private var logFileURL: URL? {
        ConfigStore.shared.sharedContainerURL?.appendingPathComponent("forward.log.jsonl")
    }

    private init() {}

    public func log(_ message: String, level: LogLevel = .info, file: String = #file, line: Int = #line) {
        let config = ConfigStore.shared.load()
        guard config.debugLogging else { return }
        queue.async { [weak self] in
            self?.append(message: message, level: level, file: file, line: line)
        }
    }

    public func readAll() -> [LogEntry] {
        guard let url = logFileURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { line in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(LogEntry.self, from: lineData)
        }
    }

    public func clear() {
        queue.async { [weak self] in
            guard let url = self?.logFileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func append(message: String, level: LogLevel, file: String, line: Int) {
        guard let url = logFileURL else { return }
        let entry = LogEntry(timestamp: Date(), level: level, message: message, file: (file as NSString).lastPathComponent, line: line)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if !fileManager.fileExists(atPath: url.path) {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        } else {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                if let lineData = line.data(using: .utf8) {
                    try? handle.write(contentsOf: lineData)
                }
            }
        }
    }
}

public enum LogLevel: String, Codable {
    case info, warning, error
}

public struct LogEntry: Codable, Identifiable {
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(line)" }
    public var timestamp: Date
    public var level: LogLevel
    public var message: String
    public var file: String
    public var line: Int
}
