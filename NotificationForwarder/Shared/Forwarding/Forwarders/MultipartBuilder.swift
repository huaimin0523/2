import Foundation

/// 构造 multipart/form-data 请求体。
///
/// 用于上传附件到 Webhook / Mailgun / Telegram Bot API 等服务。
/// 一次性把所有字段和文件拼到内存 Data 中，适合附件不大的场景（< 20MB）。
/// 大文件应改用 streaming upload，但 Extension 内存和时间预算有限，
/// 大文件本身就不推荐在 Extension 中处理。
public final class MultipartBuilder {

    private let boundary: String
    private var body: Data

    public init() {
        // boundary 必须以 -- 开头（HTTP 规范），但实际请求头里写的是不带前缀的形式。
        self.boundary = "----NF" + UUID().uuidString
        self.body = Data()
    }

    /// 用于 Content-Type 头的 boundary 值。
    public var boundaryString: String { boundary }

    /// 添加普通文本字段。
    public func append(field name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    /// 添加 JSON 字段（某些 API 要求字段值是 JSON 字符串）。
    public func appendJSON(field name: String, json object: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        let str = String(data: data, encoding: .utf8) ?? "{}"
        append(field: name, value: str)
    }

    /// 添加文件字段。
    /// - Parameters:
    ///   - name: 表单字段名（如 "file" / "attachment"）
    ///   - filename: 上传后的文件名
    ///   - mimeType: MIME 类型
    ///   - data: 文件二进制内容
    public func appendFile(field name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
    }

    /// 从本地文件 URL 读取并追加。失败时跳过并返回 false。
    @discardableResult
    public func appendFile(field name: String, fileURL: URL, mimeType: String?, filename: String? = nil) -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        let fname = filename ?? fileURL.lastPathComponent
        let mime = mimeType ?? PushAttachment.inferMIME(from: fname)
        appendFile(field: name, filename: fname, mimeType: mime, data: data)
        return true
    }

    /// 结束表单，返回最终 body。
    public func build() -> Data {
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    /// 直接构造 Content-Type 头值。
    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }
}
