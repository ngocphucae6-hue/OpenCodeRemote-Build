import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SessionListViewModel()
    @State private var showSettings = false
    @State private var showNewSession = false
    @State private var newSessionTitle = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connBar

                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white.opacity(0.5))
                    Text("Đang tải...")
                        .font(.caption)
                        .foregroundColor(SpaceTheme.tertiary)
                        .padding(.top, 8)
                    Spacer()
                } else if let error = viewModel.error {
                    Spacer()
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 36))
                        .foregroundColor(SpaceTheme.error.opacity(0.6))
                    Text(error)
                        .font(.body)
                        .foregroundColor(SpaceTheme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                    Button("Thử lại") {
                        viewModel.connectAndLoad()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(SpaceTheme.accentGradient)
                    .clipShape(Capsule())
                    .padding(.top, 16)
                    Spacer()
                } else {
                    sessionList
                }
            }
            .spaceBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("OpenCode")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(LinearGradient(
                            colors: [.white, .white.opacity(0.7)],
                            startPoint: .top, endPoint: .bottom))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Button { Task { await viewModel.sync() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNewSession = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .alert("Tạo phiên mới", isPresented: $showNewSession) {
                TextField("Tiêu đề (tùy chọn)", text: $newSessionTitle)
                Button("Tạo") {
                    Task {
                        await viewModel.createSession(title: newSessionTitle)
                        newSessionTitle = ""
                    }
                }
                Button("Hủy", role: .cancel) { newSessionTitle = "" }
            }
            .navigationDestination(for: OCSession.self) { session in
                ChatView(session: session)
            }
            .onAppear { viewModel.connectAndLoad() }
            .onDisappear { viewModel.disconnect() }
        }
    }

    private var connBar: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isConnected ? SpaceTheme.connected : SpaceTheme.error)
                .frame(width: 7, height: 7)
                .shadow(color: viewModel.isConnected ? SpaceTheme.connectedGlow : .clear, radius: 4)
            Text(viewModel.isConnected ? "ĐÃ KẾT NỐI" : "CHƯA KẾT NỐI")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(SpaceTheme.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassBar()
    }

    private var sessionList: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionLabel("Phiên làm việc")
                    .padding(.bottom, 2)

                if viewModel.sessions.isEmpty {
                    VStack(spacing: 8) {
                        Text("Chưa có phiên làm việc")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(SpaceTheme.primary)
                        Text("Nhấn + để tạo phiên mới")
                            .font(.caption)
                            .foregroundColor(SpaceTheme.tertiary)
                    }
                    .padding(.vertical, 60)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 3) {
                        ForEach(viewModel.sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session, status: viewModel.sessionStatuses[session.id])
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteSession(session) }
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                                if viewModel.sessionStatuses[session.id] == "busy" {
                                    Button {
                                        Task { await viewModel.abortSession(session) }
                                    } label: {
                                        Label("Dừng", systemImage: "stop.circle")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .refreshable { await viewModel.sync() }
    }
}

struct SessionRow: View {
    let session: OCSession
    let status: String?

    // Mỗi phiên 1 gradient riêng (theo hash id) cho icon hình thoi
    private var sessionGradient: LinearGradient {
        let palettes: [[Color]] = [
            [SpaceTheme.blue, SpaceTheme.purple],
            [SpaceTheme.pink, SpaceTheme.amber],
            [SpaceTheme.green, SpaceTheme.blue],
            [SpaceTheme.purple, SpaceTheme.pink],
            [SpaceTheme.amber, SpaceTheme.pink],
            [SpaceTheme.blue, SpaceTheme.pink]
        ]
        let hash = abs(session.id.hashValue)
        return LinearGradient(colors: palettes[hash % palettes.count],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon hình thoi gradient (style Gemini)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(sessionGradient)
                    .frame(width: 38, height: 38)
                Image(systemName: "sparkle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(SpaceTheme.primary)
                    .lineLimit(1)
                if let time = session.timeLabel {
                    Text(time)
                        .font(.system(size: 13))
                        .foregroundColor(SpaceTheme.tertiary)
                }
            }
            Spacer()
            if let status = status {
                switch status {
                case "busy":
                    Text("Đang xử lý")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SpaceTheme.amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SpaceTheme.amber.opacity(0.14))
                        .clipShape(Capsule())
                case "idle":
                    Text("Rảnh")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SpaceTheme.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(SpaceTheme.green.opacity(0.14))
                        .clipShape(Capsule())
                default:
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundColor(SpaceTheme.tertiary)
                }
            }
        }
        .padding(16)
        .spaceCard()
        .padding(.vertical, 5)
    }
}
