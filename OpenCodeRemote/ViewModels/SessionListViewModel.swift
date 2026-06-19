import Foundation
import Combine

@MainActor
class SessionListViewModel: ObservableObject {
    @Published var sessions: [OCSession] = []
    @Published var sessionStatuses: [String: String] = [:]
    @Published var isLoading = false
    @Published var error: String?
    @Published var isConnected = false
    
    private var api: OpenCodeAPI
    private var eventService: EventStreamService
    private var refreshTimer: Timer?
    
    init() {
        let config = ServerConfig.load()
        self.api = OpenCodeAPI(config: config)
        self.eventService = EventStreamService(config: config)
        setupEventHandlers()
    }
    
    func updateConfig(_ config: ServerConfig) {
        config.save()
        self.api = OpenCodeAPI(config: config)
        self.eventService.disconnect()
        self.eventService = EventStreamService(config: config)
        setupEventHandlers()
        connectAndLoad()
        // Watcher thông báo nền cũng phải trỏ sang server mới.
        NotificationManager.shared.updateConfig(config)
    }
    
    func connectAndLoad() {
        eventService.connect()
        Task { await loadSessions(showLoading: true) }
    }
    
    func disconnect() {
        eventService.disconnect()
        refreshTimer?.invalidate()
    }
    
    func loadSessions(showLoading: Bool = false) async {
        if showLoading { isLoading = true }
        error = nil
        do {
            // Tải danh sách mới nhất từ server (gộp mọi project), sắp xếp theo hoạt động gần nhất.
            // Đây là "đồng bộ": session bị xoá trên máy sẽ biến mất, tên mới được cập nhật.
            let fetched = try await api.listAllSessions()
            let newSessions = fetched.sorted { $0.lastActivity > $1.lastActivity }
            if newSessions != sessions {
                sessions = newSessions
            }
            let statuses = try await api.getSessionStatus()
            let newStatuses = statuses.compactMapValues { $0.status }
            if newStatuses != sessionStatuses {
                sessionStatuses = newStatuses
            }
            isLoading = false
        } catch {
            self.error = "Không thể tải danh sách phiên: \(error.localizedDescription)"
            isLoading = false
        }
    }

    /// Đồng bộ thủ công với server (pull-to-refresh / nút làm mới).
    func sync() async {
        await loadSessions(showLoading: true)
    }
    
    func createSession(title: String) async {
        do {
            let session = try await api.createSession(title: title.isEmpty ? nil : title)
            sessions.insert(session, at: 0)
        } catch {
            self.error = "Không thể tạo phiên mới: \(error.localizedDescription)"
        }
    }
    
    func deleteSession(_ session: OCSession) async {
        do {
            _ = try await api.deleteSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            self.error = "Không thể xóa phiên: \(error.localizedDescription)"
        }
    }
    
    func abortSession(_ session: OCSession) async {
        do {
            _ = try await api.abortSession(id: session.id)
            sessionStatuses[session.id] = "idle"
        } catch {
            self.error = "Không thể dừng phiên: \(error.localizedDescription)"
        }
    }
    
    func checkHealth() async -> Bool {
        do {
            let health = try await api.checkHealth()
            return health.healthy
        } catch {
            return false
        }
    }
    
    private func setupEventHandlers() {
        eventService.onConnected = { [weak self] in
            guard let self = self else { return }
            self.isConnected = true
            // Reconnect thành công -> xoá lỗi cũ + đồng bộ lại danh sách (bù phần lỡ khi mất stream).
            self.error = nil
            Task { await self.loadSessions() }
        }
        eventService.onDisconnected = { [weak self] in
            self?.isConnected = false
        }
        eventService.onEvent = { [weak self] type, data in
            guard let self = self else { return }
            if type.contains("session") {
                Task { await self.loadSessions() }
            }
        }
        eventService.onError = { [weak self] _ in
            // SSE rớt: service tự reconnect, không hiện lỗi đỏ gây hiểu nhầm.
            self?.isConnected = false
        }
    }
}
