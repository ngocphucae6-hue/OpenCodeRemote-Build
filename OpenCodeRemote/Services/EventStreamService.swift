import Foundation

class EventStreamService: NSObject, URLSessionDataDelegate {
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var buffer = ""

    var onEvent: ((String, String) -> Void)?
    var onError: ((Error) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: (() -> Void)?

    private let config: ServerConfig
    /// Thư mục/project để server scope event đúng session (tránh nhận event của project khác).
    private var directory: String?

    // Tự kết nối lại khi rớt (network đổi, server restart...).
    private var shouldReconnect = false
    private var reconnectAttempts = 0
    private var isConnected = false

    init(config: ServerConfig) {
        self.config = config
        super.init()
    }

    func connect(directory: String? = nil) {
        self.directory = directory
        shouldReconnect = true
        reconnectAttempts = 0
        openStream()
    }

    private func openStream() {
        var path = "/event"
        if let dir = directory, !dir.isEmpty {
            let encoded = dir.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? dir
            path += "?directory=\(encoded)"
        }
        guard let url = URL(string: "\(config.baseURL)\(path)") else { return }

        let urlConfig = URLSessionConfiguration.default
        // Không dùng INT_MAX: SSE giữ kết nối lâu nhưng vẫn cần ngưỡng để phát hiện treo
        // rồi reconnect. 10 phút không có byte nào -> coi như chết, mở lại.
        urlConfig.timeoutIntervalForRequest = 600
        urlConfig.timeoutIntervalForResource = TimeInterval(7 * 24 * 60 * 60)
        urlConfig.requestCachePolicy = .reloadIgnoringLocalCacheData

        session = URLSession(configuration: urlConfig, delegate: self, delegateQueue: .main)

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // Tránh proxy/CDN buffer làm chậm dữ liệu incremental.
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        if let auth = config.authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }

        buffer = ""
        task = session?.dataTask(with: request)
        task?.resume()
    }

    func disconnect() {
        shouldReconnect = false
        isConnected = false
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        onDisconnected?()
    }

    /// Lên lịch reconnect với backoff lũy thừa (1s, 2s, 4s... tối đa 30s).
    private func scheduleReconnect() {
        guard shouldReconnect else { return }
        session?.invalidateAndCancel()
        session = nil
        task = nil

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(min(reconnectAttempts, 5))), 30.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.shouldReconnect else { return }
            self.openStream()
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        isConnected = true
        reconnectAttempts = 0
        onConnected?()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        let events = buffer.components(separatedBy: "\n\n")
        buffer = events.last ?? ""

        for event in events.dropLast() {
            parseEvent(event)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        isConnected = false
        if let error = error {
            // Bỏ qua lỗi do chính ta huỷ (disconnect chủ động).
            let nsErr = error as NSError
            let cancelled = nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled
            if !cancelled {
                onError?(error)
            }
        }
        if shouldReconnect {
            scheduleReconnect()
        } else {
            onDisconnected?()
        }
    }

    private func parseEvent(_ raw: String) {
        var eventType = "message"
        var dataLines: [String] = []

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("event:") {
                eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                // SSE cho phép nhiều dòng data: trong 1 event -> nối lại bằng \n.
                dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            }
        }

        let eventData = dataLines.joined(separator: "\n")
        guard !eventData.isEmpty || eventType != "message" else { return }

        // OpenCode gửi type bên trong JSON (không có dòng "event:"),
        // ví dụ: data: {"type":"session.updated", ...}
        if eventType == "message", !eventData.isEmpty,
           let jsonData = eventData.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let t = obj["type"] as? String {
            eventType = t
        }

        onEvent?(eventType, eventData)
    }
}
