import SwiftUI
import PhotosUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @StateObject private var modelPicker = ModelPickerViewModel()
    @State private var inputText = ""
    @State private var showModelPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachedImages: [UIImage] = []
    @State private var showSkills = false
    @FocusState private var inputFocused: Bool

    init(session: OCSession) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(session: session))
    }

    // Bọc UIImage thành Identifiable cho fullScreenCover(item:)
    private struct ZoomItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }
    private var zoomedImageItem: Binding<ZoomItem?> {
        Binding(
            get: { viewModel.zoomedImage.map { ZoomItem(image: $0) } },
            set: { if $0 == nil { viewModel.zoomedImage = nil } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            if !viewModel.todos.isEmpty { todosSection }
            messagesList
            if let perm = viewModel.pendingPermission {
                PermissionCard(request: perm) { reply in
                    Task { await viewModel.replyPermission(perm, reply: reply) }
                }
            }
            if let question = viewModel.pendingQuestion {
                QuestionCard(request: question,
                             onAnswer: { answers in
                                 Task { await viewModel.answerQuestion(question, answers: answers) }
                             },
                             onReject: {
                                 Task { await viewModel.rejectQuestion(question) }
                             })
            }
            modeBar
            inputArea
        }
        .spaceBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(viewModel.session.displayTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 8) {
                    Button { showModelPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 11))
                            Text(modelPicker.selectedModel?.components(separatedBy: "/").last ?? "Mô hình")
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(SpaceTheme.accentStart.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(SpaceTheme.accentStart.opacity(0.08))
                        .overlay(Capsule().stroke(SpaceTheme.accentStart.opacity(0.15), lineWidth: 0.5))
                        .clipShape(Capsule())
                    }

                    Button {
                        Task {
                            await modelPicker.loadProviders()
                            modelPicker.hideUnusedModels = false
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(SpaceTheme.tertiary)
                            .rotationEffect(Angle(degrees: modelPicker.isLoading ? 360 : 0))
                    }
                    .disabled(modelPicker.isLoading)

                    if viewModel.sessionStatus == "busy" {
                        Button {
                            Task { await viewModel.abort() }
                        } label: {
                            Text("Dừng")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(SpaceTheme.error.opacity(0.8))
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(viewModel: modelPicker) { provider, model in
                modelPicker.select(provider: provider.id, model: model.id)
                viewModel.updateModel(provider: provider.id, model: model.id)
            }
        }
        .sheet(item: $viewModel.fileToShare) { url in
            ShareSheet(items: [url])
        }
        .sheet(isPresented: $showSkills) {
            SkillPickerView(skills: viewModel.skills, commands: viewModel.commands) { insertText in
                if !inputText.isEmpty && !inputText.hasSuffix(" ") { inputText += " " }
                inputText += insertText
                showSkills = false
                inputFocused = true
            }
        }
        .fullScreenCover(item: zoomedImageItem) { item in
            ImageZoomView(image: item.image) {
                viewModel.zoomedImage = nil
            }
        }
        .onAppear { viewModel.connect() }
        .onDisappear { viewModel.disconnect() }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            switch viewModel.sessionStatus {
            case "busy":
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(SpaceTheme.busy)
                Text("Đang xử lý...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SpaceTheme.busy)
            case "idle":
                Circle()
                    .fill(SpaceTheme.connected)
                    .frame(width: 7, height: 7)
                    .shadow(color: SpaceTheme.connectedGlow, radius: 4)
                Text("Sẵn sàng")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(SpaceTheme.connected)
            default:
                Text(viewModel.sessionStatus)
                    .font(.system(size: 13))
                    .foregroundColor(SpaceTheme.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassBar()
    }

    private var todosSection: some View {
        DisclosureGroup {
            ForEach(viewModel.todos, id: \.identifier) { todo in
                HStack(spacing: 8) {
                    Image(systemName: todoIcon(todo.status))
                        .font(.system(size: 12))
                        .foregroundColor(todoColor(todo.status))
                    Text(todo.content ?? "")
                        .font(.system(size: 14))
                        .foregroundColor(SpaceTheme.secondary)
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12))
                Text("Danh sách công việc (\(viewModel.todos.count))")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(SpaceTheme.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(SpaceTheme.subtle)
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(SpaceTheme.cardBorder), alignment: .bottom)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(viewModel.messages) { msg in
                        MessageBubble(
                            message: msg,
                            onDownload: { filePath in
                                Task { await viewModel.downloadFile(path: filePath) }
                            },
                            onLoadImage: { path in
                                await viewModel.loadImage(path: path)
                            },
                            onZoom: { img in
                                viewModel.zoomedImage = img
                            }
                        )
                        .id(msg.id)
                    }
                    if viewModel.isSending {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8).tint(.white.opacity(0.4))
                            Text("Đang gửi...")
                                .font(.caption)
                                .foregroundColor(SpaceTheme.tertiary)
                        }
                        .padding(.horizontal, 4)
                        .id("sending_indicator")
                    }
                    Color.clear.frame(height: 1).id("bottom_anchor")
                }
                .padding(14)
            }
            .onChange(of: viewModel.messages.count) { _ in
                proxy.scrollTo("bottom_anchor", anchor: .bottom)
            }
            // Cuộn theo nội dung đang stream của tin nhắn cuối (mượt, không nhảy).
            .onChange(of: viewModel.streamTick) { _ in
                proxy.scrollTo("bottom_anchor", anchor: .bottom)
            }
        }
    }

    // Thanh chọn chế độ: Plan (chỉ lập kế hoạch) / Build (thực thi)
    private var modeBar: some View {
        HStack(spacing: 8) {
            ForEach(["plan", "build"], id: \.self) { mode in
                Button {
                    viewModel.setAgentMode(mode)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == "plan" ? "list.bullet.clipboard" : "hammer.fill")
                            .font(.system(size: 13))
                        Text(mode == "plan" ? "Lập kế hoạch" : "Thực thi")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(viewModel.agentMode == mode ? .white : SpaceTheme.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        viewModel.agentMode == mode
                            ? AnyView(SpaceTheme.accentGradient)
                            : AnyView(Color.white.opacity(0.05))
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            // Nút mở danh sách Skill / Command để agent biết và gọi
            Button {
                showSkills = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                    Text("Skill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(SpaceTheme.violet)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(SpaceTheme.violet.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            // Xem trước ảnh đã đính kèm
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(attachedImages.enumerated()), id: \.offset) { idx, img in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Button {
                                    attachedImages.remove(at: idx)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.5)))
                                }
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 70)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(SpaceTheme.secondary)
                        .frame(width: 40, height: 40)
                }

                TextField("Nhập tác vụ hoặc câu hỏi…", text: $inputText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.95))
                    .tint(SpaceTheme.blue)
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }
                    .padding(.vertical, 10)

                Button(action: sendMessage) {
                    Image(systemName: viewModel.isSending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(canSend ? .white : SpaceTheme.quaternary)
                        .frame(width: 40, height: 40)
                        .background(
                            Group {
                                if canSend { SpaceTheme.accentGradient }
                                else { SpaceTheme.surface3 }
                            }
                        )
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SpaceTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(inputFocused ? SpaceTheme.blue.opacity(0.4) : SpaceTheme.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SpaceTheme.inputBar)
        .onChange(of: photoItems) { _ in loadPickedPhotos() }
    }

    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty)
            && !viewModel.isSending
    }

    private func loadPickedPhotos() {
        let items = photoItems
        photoItems = []
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { attachedImages.append(img) }
                }
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = attachedImages
        guard !text.isEmpty || !images.isEmpty else { return }
        inputText = ""
        attachedImages = []
        // Chuyển ảnh -> data URL base64 (JPEG)
        let dataURLs: [String] = images.compactMap { img in
            guard let data = img.jpegData(compressionQuality: 0.7) else { return nil }
            return "data:image/jpeg;base64,\(data.base64EncodedString())"
        }
        Task { await viewModel.sendMessage(text, imageDataURLs: dataURLs) }
    }

    private func todoIcon(_ status: String?) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "arrow.triangle.2.circlepath"
        case "cancelled": return "xmark.circle"
        default: return "circle"
        }
    }

    private func todoColor(_ status: String?) -> Color {
        switch status {
        case "completed": return SpaceTheme.connected
        case "in_progress": return SpaceTheme.accentStart
        case "cancelled": return SpaceTheme.error
        default: return SpaceTheme.quaternary
        }
    }
}

struct MessageBubble: View {
    let message: OCMessageWithParts
    let isUser: Bool
    var onDownload: ((String) -> Void)? = nil
    var onLoadImage: ((String) async -> UIImage?)? = nil
    var onZoom: ((UIImage) -> Void)? = nil

    /// Các tool đang được bung output (theo id của part).
    @State private var expandedTools: Set<String> = []

    init(message: OCMessageWithParts,
         onDownload: ((String) -> Void)? = nil,
         onLoadImage: ((String) async -> UIImage?)? = nil,
         onZoom: ((UIImage) -> Void)? = nil) {
        self.message = message
        self.isUser = message.info.role == "user"
        self.onDownload = onDownload
        self.onLoadImage = onLoadImage
        self.onZoom = onZoom
    }

    // Chỉ hiển thị các part có nội dung thật (bỏ step-start/step-finish rỗng)
    private var visibleParts: [OCPart] {
        message.parts.filter { part in
            switch part.type {
            case "text", "reasoning":
                return !(part.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case "tool":
                return true
            case "file":
                return (part.url ?? "").isEmpty == false
            default:
                return !(part.text ?? "").isEmpty
            }
        }
    }

    var body: some View {
        // User message rỗng thì ẩn hẳn.
        if visibleParts.isEmpty && message.info.error == nil && isUser {
            EmptyView()
        } else if isUser {
            // Tin nhắn người dùng: bubble surface bo tròn, lệch phải (style Gemini).
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(visibleParts.enumerated()), id: \.offset) { _, part in
                        partView(part)
                    }
                    if let err = message.info.error { errorView(err) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(SpaceTheme.surface2)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 20,
                    bottomLeadingRadius: 20,
                    bottomTrailingRadius: 6,
                    topTrailingRadius: 20,
                    style: .continuous
                ))
            }
        } else {
            // Tin nhắn assistant: full-width, có avatar sao Gemini, KHÔNG bong bóng.
            HStack(alignment: .top, spacing: 12) {
                GeminiAvatar()
                    .frame(width: 28, height: 28)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    if visibleParts.isEmpty && message.info.error == nil {
                        TypingIndicator()
                    }
                    ForEach(Array(visibleParts.enumerated()), id: \.offset) { _, part in
                        partView(part)
                    }
                    if let err = message.info.error {
                        errorView(err)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func partView(_ part: OCPart) -> some View {
        switch part.type {
        case "text":
            Text(part.text ?? "")
                .font(.system(size: 16))
                .foregroundColor(isUser ? .white.opacity(0.95) : SpaceTheme.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

        case "file":
            filePartView(part)

        case "reasoning":
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 11))
                    Text("Suy luận")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                }
                .foregroundColor(SpaceTheme.violet.opacity(0.8))
                Text(part.text ?? "")
                    .font(.system(size: 17))
                    .italic()
                    .foregroundColor(SpaceTheme.secondary.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SpaceTheme.violet.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(SpaceTheme.violet.opacity(0.12), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case "tool":
            toolView(part)

        default:
            if let text = part.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(SpaceTheme.tertiary)
            }
        }
    }

    // Hiển thị ảnh đính kèm (data URL hoặc http)
    @ViewBuilder
    private func filePartView(_ part: OCPart) -> some View {
        if let urlStr = part.url, let img = Self.decodeImage(urlStr) {
            Image(uiImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 260, maxHeight: 260)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { onZoom?(img) }
        } else if let urlStr = part.url, urlStr.hasPrefix("http"), let remote = URL(string: urlStr) {
            AsyncImage(url: remote) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Color.white.opacity(0.05)
                }
            }
            .frame(maxWidth: 260, maxHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "paperclip")
                    .font(.system(size: 12))
                Text(part.filename ?? "Tệp đính kèm")
                    .font(.system(size: 13))
            }
            .foregroundColor(SpaceTheme.tertiary)
        }
    }

    static func decodeImage(_ urlStr: String) -> UIImage? {
        if urlStr.hasPrefix("data:"),
           let comma = urlStr.firstIndex(of: ","),
           let data = Data(base64Encoded: String(urlStr[urlStr.index(after: comma)...])) {
            return UIImage(data: data)
        }
        return nil
    }

    @ViewBuilder
    private func toolView(_ part: OCPart) -> some View {
        let status = part.state?.status ?? "running"
        let filePath = toolFilePath(part)
        let isImage = filePath.map { Self.isImagePath($0) } ?? false
        let canDownload = filePath.map { Self.isDownloadableProduct($0) } ?? false
        // Tối giản: chỉ tên công cụ + trạng thái + tiêu đề ngắn. Không đổ output dài.
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: toolIcon(status))
                    .font(.system(size: 14))
                    .foregroundColor(stateColor(status))
                Text(part.tool ?? "công cụ")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(SpaceTheme.busy)
                if let title = part.state?.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundColor(SpaceTheme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                // Nút bung/thu output của tool (vd kết quả lệnh bash, đọc file...).
                if let output = part.state?.output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        let id = part.stableID
                        if expandedTools.contains(id) { expandedTools.remove(id) }
                        else { expandedTools.insert(id) }
                    } label: {
                        Image(systemName: expandedTools.contains(part.stableID) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SpaceTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                // Nút tải CHỈ hiện cho file sản phẩm (ipa, ảnh, zip, pdf...), không phải file code
                if let fp = filePath, status == "completed", canDownload {
                    Button {
                        onDownload?(fp)
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(SpaceTheme.accentStart)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Output tool (chỉ hiện khi người dùng bung) - vd log lệnh, nội dung file đọc.
            if expandedTools.contains(part.stableID),
               let output = part.state?.output,
               !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(output)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                }
                .frame(maxHeight: 320)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            // Nếu file là ảnh -> render ảnh thật để review + phóng to
            if isImage, let fp = filePath, status == "completed",
               let loader = onLoadImage {
                InlineServerImage(path: fp, loader: loader) { img in
                    onZoom?(img)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpaceTheme.busyBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SpaceTheme.busy.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Lấy đường dẫn file nếu tool là write/edit/apply_patch
    private func toolFilePath(_ part: OCPart) -> String? {
        guard let tool = part.tool,
              ["write", "edit", "apply_patch"].contains(tool) else { return nil }
        if let fp = part.state?.metadata?.filepath, !fp.isEmpty { return fp }
        if case .object(let dict)? = part.state?.input,
           case .string(let fp)? = dict["filePath"], !fp.isEmpty { return fp }
        return nil
    }

    static func isImagePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"].contains(ext)
    }

    // Chỉ cho tải file SẢN PHẨM (ipa, ảnh, nén, tài liệu, media...), không phải file code/text nguồn.
    static func isDownloadableProduct(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        let products: Set<String> = [
            "ipa", "apk", "zip", "rar", "7z", "tar", "gz", "tgz",
            "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "svg",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "mp4", "mov", "mp3", "wav", "m4a",
            "dmg", "pkg", "app", "exe", "bin", "deb",
            "csv", "epub", "psd", "sketch", "fig"
        ]
        return products.contains(ext)
    }

    private func toolIcon(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "error", "failed": return "xmark.circle.fill"
        default: return "circle.dotted"
        }
    }

    @ViewBuilder
    private func errorView(_ err: OCMessageError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
            Text(err.data?.message ?? err.name ?? "Lỗi")
                .font(.system(size: 15, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(SpaceTheme.error)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpaceTheme.error.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(SpaceTheme.error.opacity(0.25), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "completed": return SpaceTheme.connected
        case "error", "failed": return SpaceTheme.error
        default: return SpaceTheme.busy
        }
    }
}

// MARK: - Thẻ câu hỏi (agent hỏi -> chọn đáp án trên iPad)

struct QuestionCard: View {
    let request: OCQuestionRequest
    var onAnswer: ([[String]]) -> Void
    var onReject: () -> Void

    // Lựa chọn cho từng câu hỏi (mảng nhãn đã chọn).
    @State private var selections: [Int: Set<String>] = [:]
    @State private var customText: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 15))
                Text("Agent đang hỏi")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(action: onReject) {
                    Text("Bỏ qua")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(SpaceTheme.tertiary)
                }
            }
            .foregroundColor(SpaceTheme.accentStart)

            ForEach(Array(request.questions.enumerated()), id: \.offset) { qIdx, q in
                VStack(alignment: .leading, spacing: 8) {
                    Text(q.question)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(q.options) { opt in
                        optionButton(qIdx: qIdx, q: q, opt: opt)
                    }

                    if q.custom == true {
                        TextField("Tự nhập câu trả lời...", text: bindingCustom(qIdx))
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            Button(action: submit) {
                Text("Gửi trả lời")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(canSubmit ? AnyView(SpaceTheme.accentGradient) : AnyView(Color.white.opacity(0.12)))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!canSubmit)
        }
        .padding(16)
        .background(SpaceTheme.accentStart.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SpaceTheme.accentStart.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func optionButton(qIdx: Int, q: OCQuestionInfo, opt: OCQuestionOption) -> some View {
        let isSelected = selections[qIdx]?.contains(opt.label) == true
        return Button {
            toggle(qIdx: qIdx, label: opt.label, multiple: q.multiple == true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? (q.multiple == true ? "checkmark.square.fill" : "largecircle.fill.circle") : (q.multiple == true ? "square" : "circle"))
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? SpaceTheme.accentStart : SpaceTheme.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(opt.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                    if let desc = opt.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundColor(SpaceTheme.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? SpaceTheme.accentStart.opacity(0.12) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? SpaceTheme.accentStart.opacity(0.4) : SpaceTheme.cardBorder, lineWidth: 0.7)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func bindingCustom(_ qIdx: Int) -> Binding<String> {
        Binding(
            get: { customText[qIdx] ?? "" },
            set: { customText[qIdx] = $0 }
        )
    }

    private func toggle(qIdx: Int, label: String, multiple: Bool) {
        var set = selections[qIdx] ?? []
        if multiple {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = [label]
        }
        selections[qIdx] = set
    }

    private var canSubmit: Bool {
        request.questions.indices.allSatisfy { idx in
            !(selections[idx]?.isEmpty ?? true) || !(customText[idx]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        }
    }

    private func submit() {
        var answers: [[String]] = []
        for idx in request.questions.indices {
            var picked = Array(selections[idx] ?? [])
            if let custom = customText[idx]?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
                picked.append(custom)
            }
            answers.append(picked)
        }
        onAnswer(answers)
    }
}

// MARK: - Thẻ xin quyền (cho phép / từ chối chạy tool)

struct PermissionCard: View {
    let request: OCPermissionRequest
    var onReply: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 15))
                Text("Yêu cầu quyền")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
            }
            .foregroundColor(SpaceTheme.busy)

            Text(request.displayText)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button { onReply("reject") } label: {
                    Text("Từ chối")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SpaceTheme.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(SpaceTheme.error.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button { onReply("once") } label: {
                    Text("Cho phép")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(SpaceTheme.accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Button { onReply("always") } label: {
                    Text("Luôn cho")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SpaceTheme.connected)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(SpaceTheme.connected.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(SpaceTheme.busyBg)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SpaceTheme.busy.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Share sheet (lưu file về Files / bộ nhớ máy)

extension URL: Identifiable {
    public var id: String { absoluteString }
}
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Ảnh tải từ server, render inline + nhấn để phóng to

struct InlineServerImage: View {
    let path: String
    let loader: (String) async -> UIImage?
    let onZoom: (UIImage) -> Void

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(SpaceTheme.cardBorder, lineWidth: 0.5)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                            .padding(8)
                    }
                    .onTapGesture { onZoom(img) }
            } else if failed {
                HStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 13))
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13))
                }
                .foregroundColor(SpaceTheme.tertiary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8).tint(.white.opacity(0.4))
                    Text("Đang tải ảnh...")
                        .font(.system(size: 13))
                        .foregroundColor(SpaceTheme.tertiary)
                }
                .frame(height: 60)
                .task {
                    if let img = await loader(path) {
                        image = img
                    } else {
                        failed = true
                    }
                }
            }
        }
    }
}

// MARK: - Trình xem ảnh phóng to (pinch + double tap)

struct ImageZoomView: View {
    let image: UIImage
    var onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, lastScale * value)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                        else { scale = 2.5; lastScale = 2.5 }
                    }
                }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .padding(16)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Bộ chọn Skill / Command (để agent tự biết và gọi)

struct SkillPickerView: View {
    let skills: [OCSkill]
    let commands: [OCCommand]
    var onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var tab = 0   // 0 = skill, 1 = command

    private var filteredSkills: [OCSkill] {
        query.isEmpty ? skills : skills.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }
    private var filteredCommands: [OCCommand] {
        query.isEmpty ? commands : commands.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Skill (\(skills.count))").tag(0)
                    Text("Lệnh (\(commands.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                List {
                    if tab == 0 {
                        ForEach(filteredSkills) { skill in
                            Button {
                                // Chèn chỉ dẫn để agent dùng skill này.
                                onPick("Hãy dùng skill \"\(skill.name)\" để ")
                            } label: {
                                rowLabel(name: skill.name, desc: skill.description, icon: "sparkles", color: SpaceTheme.violet)
                            }
                            .listRowBackground(Color.white.opacity(0.03))
                        }
                    } else {
                        ForEach(filteredCommands) { cmd in
                            Button {
                                onPick("/\(cmd.name) ")
                            } label: {
                                rowLabel(name: "/\(cmd.name)", desc: cmd.description, icon: "terminal", color: SpaceTheme.accentStart)
                            }
                            .listRowBackground(Color.white.opacity(0.03))
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Tìm skill hoặc lệnh...")
            }
            .navigationTitle("Skill & Lệnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private func rowLabel(name: String, desc: String?, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                if let desc = desc, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .foregroundColor(SpaceTheme.tertiary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Avatar sao Gemini (gradient)

struct GeminiAvatar: View {
    var body: some View {
        Circle()
            .fill(SpaceTheme.accentGradient)
            .overlay(
                Image(systemName: "sparkle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            )
    }
}

// MARK: - Bong bóng tin nhắn người dùng (bo tròn, góc dưới phải nhỏ lại)

// MARK: - Typing indicator (3 chấm nhấp nháy khi assistant đang soạn)

struct TypingIndicator: View {
    var body: some View {
        // TimelineView tự dừng khi view biến mất -> không leak timer.
        TimelineView(.periodic(from: .now, by: 0.4)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(SpaceTheme.blue)
                        .frame(width: 7, height: 7)
                        .opacity(step == i ? 1.0 : 0.3)
                        .scaleEffect(step == i ? 1.0 : 0.7)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
