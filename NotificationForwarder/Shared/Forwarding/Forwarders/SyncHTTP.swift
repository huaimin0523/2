import Foundation

/// 同步 HTTP 工具：在 Extension 中使用 URLSession + 信号量等待。
/// 之所以用同步而非 async/await，是因为 Extension 进程的运行时间极短，
/// 同步等待更可控，避免 RunLoop 提前结束。
public enum SyncHTTP {

    public enum Method: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    public struct Response {
        public var statusCode: Int
        public var body: Data?
        public var error: Error?
    }

    /// 发送请求并阻塞等待结果。
    public static func request(
        url: URL,
        method: Method = .post,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 15,
        basicAuthUser: String? = nil,
        basicAuthPassword: String? = nil
    ) -> Response {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let body { request.httpBody = body }
        if let user = basicAuthUser, let pwd = basicAuthPassword {
            let token = "\(user):\(pwd)".data(using: .utf8)?.base64EncodedString() ?? ""
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        var response: URLResponse?
        var responseError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { _, resp, err in
            response = resp
            responseError = err
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 2)

        if let error = responseError {
            return Response(statusCode: 0, body: nil, error: error)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Response(statusCode: code, body: nil, error: nil)
    }
}
