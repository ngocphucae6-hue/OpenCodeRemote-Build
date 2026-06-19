import Foundation
import UIKit
import UserNotifications

/// Theo dõi câu hỏi / yêu cầu quyền của TẤT CẢ session ở cấp app (kể cả khi không mở ChatView),
/// và bắn thông báo cục bộ + rung. Nhờ vậy agent hỏi từ PC lúc app ở nền vẫn báo được.
@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private var api: OpenCodeAPI
    private var eventService: EventStreamService
    private var pollTimer: Timer?

    /// ID các câu hỏi / quyền đã thông báo rồi - tránh báo trùng.
    private var notifiedQuestionIDs = Set<String>()
    private var notifiedPermissionIDs = Set<String>()

    private override init() {
        let config = ServerConfig.load()
        self.api = OpenCodeAPI(config: config)
        self.eventService = EventStreamService(config: config)
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Gọi 1 lần lúc khởi động: xin quyền notif + bật watcher.
    func start() {
        requestAuthorizationOnce()
        connect()
    }

    /// Cập nhật cấu hình khi user đổi server trong Cài đặt.
    func updateConfig(_ config: ServerConfig) {
        eventService.disconnect()
        api = OpenCodeAPI(config: config)
        eventService = EventStreamService(config: config)
        notifiedQuestionIDs.removeAll()
        notifiedPermissionIDs.removeAll()
        connect()
    }

    private func connect() {
        // Huỷ stream cũ trước khi mở lại để tránh rò task khi gọi nhiều lần (start/resume).
        eventService.disconnect()
        eventService.onEvent = { [weak self] type, data in
            guard let self = self else { return }
            if type.contains("question") || type.contains("permission") {
                Task { @MainActor in
                    self.handleEvent(type: type, data: data)
                    await self.refreshPending()
                }
            }
        }
        eventService.connect()
        startPolling()
        Task { await refreshPending() }
    }

    func stop() {
        eventService.disconnect()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Khi app trở lại foreground: nối lại SSE + poll (idempotent, gọi nhiều lần an toàn).
    func resume() {
        connect()
    }

    // MARK: - Quyền thông báo (xin 1 lần)

    private var didRequestAuth = false
    private func requestAuthorizationOnce() {
        guard !didRequestAuth else { return }
        didRequestAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Watcher

    /// Poll nhẹ 5s làm lưới an toàn cho SSE (bắt câu hỏi/quyền kể cả khi stream lỡ event).
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in await self.refreshPending() }
        }
    }

    private func refreshPending() async {
        if let questions = try? await api.listQuestions() {
            for q in questions where !notifiedQuestionIDs.contains(q.id) {
                notifiedQuestionIDs.insert(q.id)
                notifyQuestion(q)
            }
        }
        if let perms = try? await api.listPermissions() {
            for p in perms where !notifiedPermissionIDs.contains(p.id) {
                notifiedPermissionIDs.insert(p.id)
                notifyPermission(p)
            }
        }
    }

    private func handleEvent(type: String, data: String) {
        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let props = obj["properties"] as? [String: Any] else { return }

        if type.contains("question.asked"),
           let propsData = try? JSONSerialization.data(withJSONObject: props),
           let q = try? JSONDecoder().decode(OCQuestionRequest.self, from: propsData),
           !notifiedQuestionIDs.contains(q.id) {
            notifiedQuestionIDs.insert(q.id)
            notifyQuestion(q)
        }
        if (type.contains("permission.asked") || type.contains("permission.v2.asked")),
           let propsData = try? JSONSerialization.data(withJSONObject: props),
           let p = try? JSONDecoder().decode(OCPermissionRequest.self, from: propsData),
           !notifiedPermissionIDs.contains(p.id) {
            notifiedPermissionIDs.insert(p.id)
            notifyPermission(p)
        }
    }

    // MARK: - Bắn thông báo

    private func notifyQuestion(_ q: OCQuestionRequest) {
        let title = q.questions.first?.header ?? "Agent đang hỏi"
        let body = q.questions.first?.question ?? "Có câu hỏi cần bạn trả lời"
        post(title: "❓ \(title)", body: body)
    }

    private func notifyPermission(_ p: OCPermissionRequest) {
        post(title: "🔒 Yêu cầu quyền", body: p.displayText)
    }

    private func post(title: String, body: String) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Hiện thông báo cả khi app đang mở (foreground).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
