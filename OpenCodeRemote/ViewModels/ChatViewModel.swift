import Foundation
import Combine
import UIKit

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [OCMessageWithParts] = []
    @Published var todos: [OCTodo] = []
    @Published var isLoading = false
    @Published var isSending = false
    @Published var error: String?
    @Published var sessionStatus: String = "idle"
    @Published var currentProvider: String?
    @Published var currentModel: String?
    @Published var pendingQuestion: OCQuestionRequest?
    @Published var pendingPermission: OCPermissionRequest?
    @Published var fileToShare: URL?
    @Published var isDownloading = false
    @Published var zoomedImage: UIImage?
    /// Tăng mỗi khi có delta stream để view cuộn xuống mượt.
    @Published var streamTick: Int = 0
    @Published var skills: [OCSkill] = []
    @Published var commands: [OCCommand] = []
    /// Chế độ agent: "build" (thực thi) hoặc "plan" (chỉ lập kế hoạch, không sửa file).
    @Published var agentMode: String = UserDefaults.standard.string(forKey: "agent_mode") ?? "build"
    
    let session: OCSession
    private let api: OpenCodeAPI
    private var eventService: EventStreamService
    private var pollTimer: Timer?

    /// Thư mục/project của session - bắt buộc gửi kèm mọi yêu cầu để server xử lý đúng.
    private var dir: String? { session.directory }
    
    init(session: OCSession) {
        self.session = session
        let config = ServerConfig.load()
        self.api = OpenCodeAPI(config: config)
        self.eventService = EventStreamService(config: config)
        self.currentProvider = UserDefaults.standard.string(forKey: "selected_provider")
        self.currentModel = UserDefaults.standard.string(forKey: "selected_model")
        setupEventHandlers()
    }
    
    func connect() {
        // Truyền directory để server chỉ đẩy event của project này (tránh nhận nhầm session khác).
        eventService.connect(directory: dir)
        Task {
            await loadMessages(showLoading: true)
            await loadTodos()
            await refreshPending()
            await loadSkillsAndCommands()

            // Nếu session đang chạy sẵn (vd mở lại lúc agent đang làm), bật poll để đẩy real-time.
            let statuses = try? await self.api.getSessionStatus(directory: self.dir)
            if let status = statuses?[self.session.id]?.status {
                self.sessionStatus = status
                if status == "busy" || status == "pending" {
                    self.startPolling()
                }
            }
        }
    }

    /// Tải danh sách skill + command để hiển thị và cho agent gọi.
    func loadSkillsAndCommands() async {
        if let s = try? await api.listSkills() {
            skills = s.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        if let c = try? await api.listCommands() {
            commands = c.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    
    func disconnect() {
        eventService.disconnect()
        pollTimer?.invalidate()
    }

    // MARK: - Question & Permission

    /// Lấy câu hỏi / yêu cầu quyền đang chờ cho session này (CHỈ của session này).
    func refreshPending() async {
        if let questions = try? await api.listQuestions(directory: dir) {
            let q = questions.first { $0.sessionID == session.id }
            if let q = q, pendingQuestion?.id != q.id {
                notifyQuestion(q)
            }
            pendingQuestion = q
        }
        if let perms = try? await api.listPermissions(directory: dir) {
            let p = perms.first { $0.sessionID == session.id }
            if let p = p, pendingPermission?.id != p.id {
                notifyPermission(p)
            }
            pendingPermission = p
        }
    }

    func answerQuestion(_ request: OCQuestionRequest, answers: [[String]]) async {
        pendingQuestion = nil
        do {
            try await api.replyQuestion(requestID: request.id, answers: answers, directory: dir)
            startPolling()
        } catch {
            self.error = "Không gửi được trả lời: \(error.localizedDescription)"
        }
    }

    func rejectQuestion(_ request: OCQuestionRequest) async {
        pendingQuestion = nil
        try? await api.rejectQuestion(requestID: request.id, directory: dir)
    }

    func replyPermission(_ request: OCPermissionRequest, reply: String) async {
        pendingPermission = nil
        do {
            try await api.replyPermission(requestID: request.id, reply: reply, directory: dir)
            startPolling()
        } catch {
            self.error = "Không gửi được phản hồi quyền: \(error.localizedDescription)"
        }
    }
    
    func loadMessages(showLoading: Bool = false) async {
        if showLoading { isLoading = true }
        do {
            let serverMessages = try await api.listMessages(sessionId: session.id, directory: dir)
            mergeServerMessages(serverMessages)
            streamTick &+= 1
            isLoading = false
        } catch {
            if showLoading { self.error = "Không thể tải tin nhắn: \(error.localizedDescription)" }
            isLoading = false
        }
    }

    /// Hợp nhất snapshot từ server vào mảng hiện tại THEO TỪNG PHẦN TỬ (không gán lại cả mảng),
    /// để SwiftUI chỉ cập nhật những bubble thay đổi -> không nhấp nháy khi đang stream.
    private func mergeServerMessages(_ serverMessages: [OCMessageWithParts]) {
        // Index hiện có theo message id.
        var localIndex: [String: Int] = [:]
        for (i, m) in messages.enumerated() {
            if let id = m.info.id { localIndex[id] = i }
        }

        // Text đang stream (SSE) theo part id - để không bị poll ghi đè bản ngắn hơn.
        var existingTextByPart: [String: String] = [:]
        for msg in messages {
            for part in msg.parts {
                if let id = part.id, let t = part.text, !t.isEmpty {
                    existingTextByPart[id] = t
                }
            }
        }

        // Cập nhật / thêm message từ server, giữ nguyên thứ tự server.
        var newOrder: [OCMessageWithParts] = []
        newOrder.reserveCapacity(serverMessages.count)

        for var srv in serverMessages {
            // Giữ phần text DÀI HƠN giữa SSE đang chảy và bản server (tránh mất chữ / nháy).
            for pIdx in srv.parts.indices {
                guard let pid = srv.parts[pIdx].id else { continue }
                let serverText = srv.parts[pIdx].text ?? ""
                if let local = existingTextByPart[pid], local.count > serverText.count {
                    srv.parts[pIdx].text = local
                }
            }

            if let mid = srv.info.id, let idx = localIndex[mid] {
                // Cập nhật tại chỗ: chỉ đổi info/parts nếu thực sự khác (tránh trigger render thừa).
                if !messages[idx].isContentEqual(to: srv) {
                    messages[idx].info = srv.info
                    messages[idx].parts = srv.parts
                }
                newOrder.append(messages[idx])
            } else {
                newOrder.append(srv)
            }
        }

        // Giữ lại tin optimistic (local_) CHƯA có bản tương ứng trên server, đặt ĐÚNG cuối
        // (chúng là tin user vừa gửi, luôn ở sau các tin đã có).
        let serverUserTexts = Set(serverMessages
            .filter { $0.info.role == "user" }
            .flatMap { $0.parts }
            .compactMap { $0.text })
        let pendingLocal = messages.filter { msg in
            (msg.info.id?.hasPrefix("local_") ?? false) &&
            !msg.parts.contains { part in
                if let t = part.text { return serverUserTexts.contains(t) }
                return false
            }
        }

        let merged = newOrder + pendingLocal
        // Chỉ gán lại khi danh sách id thực sự thay đổi (thêm/bớt/đổi thứ tự).
        // Nếu chỉ nội dung bên trong đổi, ta đã cập nhật tại chỗ ở trên rồi.
        let oldIDs = messages.map { $0.id }
        let newIDs = merged.map { $0.id }
        if oldIDs != newIDs {
            messages = merged
        }
    }
    
    func loadTodos() async {
        do {
            todos = try await api.getTodos(sessionId: session.id, directory: dir)
        } catch {
            // silent - todos optional
        }
    }
    
    func sendMessage(_ text: String, imageDataURLs: [String] = []) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !imageDataURLs.isEmpty else { return }

        // KIỂM TRA HỖ TRỢ ẢNH: nếu model hiện tại không nhận ảnh thì báo cho người dùng,
        // tránh gửi lên server rồi nhận lỗi 'this model does not support image input'.
        if !imageDataURLs.isEmpty {
            if let providers = try? await api.listProviders(),
               let model = providers
                    .first(where: { $0.id == currentProvider })?
                    .models.first(where: { $0.id == currentModel }),
               model.supportsImages == false {
                self.error = "Model \"\(model.displayName)\" không hỗ trợ gửi ảnh. Vui lòng chọn model khác (vd có hỗ trợ vision) hoặc bỏ ảnh đính kèm."
                return
            }
        }

        // Hiển thị ngay tin nhắn của người dùng (optimistic) - không chờ server.
        var optimisticParts: [OCPart] = []
        if !text.isEmpty {
            optimisticParts.append(OCPart(id: "local_\(UUID().uuidString)", type: "text", text: text, tool: nil, callID: nil, state: nil, mime: nil, filename: nil, url: nil))
        }
        for url in imageDataURLs {
            optimisticParts.append(OCPart(id: "local_\(UUID().uuidString)", type: "file", text: nil, tool: nil, callID: nil, state: nil, mime: "image/jpeg", filename: "image.jpg", url: url))
        }
        let localID = "local_msg_\(UUID().uuidString)"
        let optimisticMsg = OCMessageWithParts(
            info: OCMessage(id: localID, role: "user", sessionID: session.id, time: nil, providerID: nil, modelID: nil, agent: nil, error: nil),
            parts: optimisticParts
        )
        messages.append(optimisticMsg)

        isSending = true
        sessionStatus = "busy"

        do {
            try await api.sendMessageAsync(sessionId: session.id, text: text, provider: currentProvider, model: currentModel, imageDataURLs: imageDataURLs, agent: agentMode, directory: dir)
            // Tải lại ngay để lấy tin nhắn thật từ server, rồi poll tiếp.
            await loadMessages()
            startPolling()
        } catch {
            self.error = "Gửi thất bại: \(error.localizedDescription)"
            sessionStatus = "idle"
        }
        isSending = false
    }
    
    func updateModel(provider: String, model: String) {
        currentProvider = provider
        currentModel = model
        // Also update server config
        Task {
            try? await api.updateConfig(provider: provider, model: model)
        }
    }

    /// Đổi chế độ agent (build/plan) và nhớ lựa chọn.
    func setAgentMode(_ mode: String) {
        agentMode = mode
        UserDefaults.standard.set(mode, forKey: "agent_mode")
    }

    /// Tải file (do agent tạo/sửa) về máy: lưu vào thư mục tạm rồi mở share sheet.
    func downloadFile(path: String) async {
        isDownloading = true
        defer { isDownloading = false }
        do {
            let result = try await api.downloadFile(path: path, directory: session.directory)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(result.filename)
            try? FileManager.default.removeItem(at: tmpURL)
            try result.data.write(to: tmpURL)
            fileToShare = tmpURL
        } catch {
            self.error = "Không tải được file: \(error.localizedDescription)"
        }
    }

    /// Tải 1 ảnh (do agent tạo) từ server để render inline trong khung chat.
    func loadImage(path: String) async -> UIImage? {
        if let cached = Self.imageCache[path] { return cached }
        guard let result = try? await api.downloadFile(path: path, directory: session.directory),
              let img = UIImage(data: result.data) else { return nil }
        Self.imageCache[path] = img
        return img
    }

    private static var imageCache: [String: UIImage] = [:]
    
    func abort() async {
        do {
            _ = try await api.abortSession(id: session.id, directory: dir)
            sessionStatus = "idle"
            stopPolling()
            await loadMessages()
        } catch {
            self.error = "Không thể dừng: \(error.localizedDescription)"
        }
    }
    
    private func startPolling() {
        pollTimer?.invalidate()
        // SSE streaming lo cập nhật mượt theo thời gian thực. Poll chỉ là lưới an toàn
        // (bù khi vài event delta bị lỡ) nên 2s là đủ, đỡ tốn pin/mạng so với 1s.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.loadMessages()
                await self.loadTodos()
                await self.refreshPending()

                let statuses = try? await self.api.getSessionStatus(directory: self.dir)
                if let status = statuses?[self.session.id]?.status {
                    self.sessionStatus = status
                    // Vẫn tiếp tục poll nếu còn câu hỏi/quyền đang chờ trả lời.
                    if status != "busy" && status != "pending"
                        && self.pendingQuestion == nil && self.pendingPermission == nil {
                        self.stopPolling()
                        // Đồng bộ lần cuối để chốt nội dung đầy đủ.
                        await self.loadMessages()
                    }
                }
            }
        }
    }
    
    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Poll nhẹ định kỳ để luôn phát hiện câu hỏi/quyền (kể cả khi agent hỏi từ PC).
    func startPendingWatcher() {
        startPolling()
    }
    
    private func setupEventHandlers() {
        // SSE rớt/lỗi: không hiện lỗi đỏ ồn ào (đã có poll làm lưới an toàn + service tự reconnect).
        // Khi kết nối lại được thì đồng bộ ngay để không sót gì khi mất stream.
        eventService.onError = { _ in
            // im lặng: tự reconnect + polling vẫn chạy
        }
        eventService.onConnected = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in await self.loadMessages() }
        }

        eventService.onEvent = { [weak self] type, data in
            guard let self = self else { return }

            // Streaming incremental: cập nhật tại chỗ cho mượt (không reload toàn bộ).
            if type.contains("message.part.delta") {
                Task { @MainActor in self.applyPartDelta(data) }
                return
            }
            if type.contains("message.part.updated") || type.contains("message.part.removed") {
                Task { @MainActor in self.applyPartUpdate(data, removed: type.contains("removed")) }
                return
            }
            if type.contains("message.updated") || type.contains("message.removed") {
                Task { @MainActor in self.applyMessageUpdate(data, removed: type.contains("removed")) }
                return
            }
            if type.contains("session.status") {
                Task { @MainActor in
                    await self.loadTodos()
                    let statuses = try? await self.api.getSessionStatus(directory: self.dir)
                    if let status = statuses?[self.session.id]?.status {
                        self.sessionStatus = status
                    }
                }
            }
            // Agent hỏi / xin quyền -> parse thẳng từ event, fallback nạp lại danh sách.
            if type.contains("question") || type.contains("permission") {
                Task { @MainActor in
                    self.handlePendingEvent(type: type, data: data)
                    await self.refreshPending()
                }
            }
        }
    }

    // MARK: - Streaming incremental (mượt như Gemini)

    /// Gộp nhiều yêu cầu reload (do event tới sớm/sai thứ tự) thành 1 lần trong ~0.25s.
    private var reloadScheduled = false
    private func scheduleCoalescedReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.reloadScheduled = false
            await self.loadMessages()
        }
    }

    private func eventProps(_ data: String) -> [String: Any]? {
        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
        return obj["properties"] as? [String: Any]
    }

    /// Nối thêm delta text vào part đang stream (vd phần text/reasoning của assistant).
    private func applyPartDelta(_ data: String) {
        guard let props = eventProps(data),
              (props["sessionID"] as? String) == session.id,
              let messageID = props["messageID"] as? String,
              let partID = props["partID"] as? String,
              let field = props["field"] as? String,
              let delta = props["delta"] as? String else { return }
        guard field == "text" else { return }

        guard let mIdx = messages.firstIndex(where: { $0.info.id == messageID }) else {
            // Message chưa có -> reload gộp để đồng bộ, không bỏ rơi delta.
            scheduleCoalescedReload()
            return
        }
        if let pIdx = messages[mIdx].parts.firstIndex(where: { $0.id == partID }) {
            messages[mIdx].parts[pIdx].text = (messages[mIdx].parts[pIdx].text ?? "") + delta
        } else {
            // Part chưa được tạo (delta tới trước part.updated) -> tạo part text mới để không mất chữ.
            messages[mIdx].parts.append(
                OCPart(id: partID, type: "text", text: delta, tool: nil, callID: nil,
                       state: nil, mime: nil, filename: nil, url: nil)
            )
        }
        streamTick &+= 1
    }

    /// Thêm/cập nhật 1 part trong tin nhắn.
    private func applyPartUpdate(_ data: String, removed: Bool) {
        guard let props = eventProps(data),
              (props["sessionID"] as? String) == session.id else { return }
        guard let partObj = props["part"] as? [String: Any],
              let partData = try? JSONSerialization.data(withJSONObject: partObj),
              let part = try? JSONDecoder().decode(OCPart.self, from: partData),
              let partID = part.id else { return }

        // Tìm message chứa part (qua messageID trong part nếu có)
        let messageID = partObj["messageID"] as? String
        guard let mIdx = messages.firstIndex(where: { msg in
            if let mid = messageID { return msg.info.id == mid }
            return msg.parts.contains { $0.id == partID }
        }) else {
            // Chưa có message tương ứng (event tới sớm/sai thứ tự) -> reload gộp, tránh nhiều
            // reload song song khi server bắn 1 loạt event cho message mới.
            scheduleCoalescedReload()
            return
        }

        if removed {
            messages[mIdx].parts.removeAll { $0.id == partID }
        } else if let pIdx = messages[mIdx].parts.firstIndex(where: { $0.id == partID }) {
            messages[mIdx].parts[pIdx] = part
        } else {
            messages[mIdx].parts.append(part)
        }
    }

    /// Thêm/cập nhật message (vd assistant message mới khi bắt đầu trả lời).
    private func applyMessageUpdate(_ data: String, removed: Bool) {
        guard let props = eventProps(data),
              (props["sessionID"] as? String) == session.id else { return }
        guard let infoObj = props["info"] as? [String: Any],
              let infoData = try? JSONSerialization.data(withJSONObject: infoObj),
              let info = try? JSONDecoder().decode(OCMessage.self, from: infoData),
              let msgID = info.id else { return }

        if removed {
            messages.removeAll { $0.info.id == msgID }
            return
        }

        if let idx = messages.firstIndex(where: { $0.info.id == msgID }) {
            messages[idx].info = info
        } else {
            // Message mới (vd assistant bắt đầu trả lời). KHÔNG xoá tin optimistic local_ ở đây
            // để tránh làm biến mất tin user vừa gửi nếu nó chưa kịp lên server.
            // Việc dedup tin local_ đã có bản trên server do mergeServerMessages lo.
            messages.append(OCMessageWithParts(info: info, parts: []))
        }
    }

    /// Parse câu hỏi/quyền trực tiếp từ dữ liệu SSE event (tránh phụ thuộc directory).
    private func handlePendingEvent(type: String, data: String) {
        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let props = obj["properties"] as? [String: Any] else { return }

        // Câu hỏi mới - CHỈ của session này
        if type.contains("question.asked"),
           let propsData = try? JSONSerialization.data(withJSONObject: props),
           let q = try? JSONDecoder().decode(OCQuestionRequest.self, from: propsData) {
            if q.sessionID == session.id {
                if pendingQuestion?.id != q.id { notifyQuestion(q) }
                pendingQuestion = q
            }
        }
        // Câu hỏi đã trả lời/từ chối ở nơi khác -> xoá
        if type.contains("question.replied") || type.contains("question.rejected") {
            pendingQuestion = nil
        }
        // Quyền mới - CHỈ của session này
        if type.contains("permission.asked") || type.contains("permission.v2.asked"),
           let propsData = try? JSONSerialization.data(withJSONObject: props),
           let p = try? JSONDecoder().decode(OCPermissionRequest.self, from: propsData) {
            if p.sessionID == session.id {
                if pendingPermission?.id != p.id { notifyPermission(p) }
                pendingPermission = p
            }
        }
        if type.contains("permission.replied") {
            pendingPermission = nil
        }
    }

    // MARK: - Thông báo khi agent hỏi
    // Notif do NotificationManager (cấp app) lo để không trùng. Ở đây chỉ rung nhẹ báo hiệu
    // khi đang mở đúng session này.

    private func notifyQuestion(_ q: OCQuestionRequest) {
        Self.haptic()
    }

    private func notifyPermission(_ p: OCPermissionRequest) {
        Self.haptic()
    }

    /// Rung nhẹ báo agent đang hỏi (notif đẩy do NotificationManager xử lý).
    static func haptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
}
