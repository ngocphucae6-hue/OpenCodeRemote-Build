import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SessionListViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var isTesting = false
    @State private var testResult: String?

    init(viewModel: SessionListViewModel) {
        self.viewModel = viewModel
        let config = ServerConfig.load()
        _host = State(initialValue: config.host)
        _port = State(initialValue: String(config.port))
        _username = State(initialValue: config.username)
        _password = State(initialValue: config.password)
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    SectionLabel("Kết nối Tailscale")
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        row("Địa chỉ", value: $host, keyboard: .URL)
                        Divider().overlay(SpaceTheme.cardBorder).padding(.leading, 16)
                        portRow()
                    }
                    .spaceCard()
                    .padding(.horizontal, 16)

                    Text("Nhập IP/host của máy chủ (vd IP Tailscale hoặc LAN)")
                        .font(.system(size: 10))
                        .foregroundColor(SpaceTheme.tertiary)
                        .padding(.top, 6)

                    SectionLabel("Xác thực")
                    VStack(spacing: 0) {
                        row("Tên đăng nhập", value: $username, keyboard: .default)
                        Divider().overlay(SpaceTheme.cardBorder).padding(.leading, 16)
                        secureRow("Mật khẩu", value: $password)
                    }
                    .spaceCard()
                    .padding(.horizontal, 16)

                    SectionLabel("Hướng dẫn")
                    hintCard

                    Button(action: testConnection) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text("Kiểm tra kết nối")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(SpaceTheme.accentGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: SpaceTheme.accentEnd.opacity(0.25), radius: 16)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    }
                    .disabled(isTesting)

                    if let result = testResult {
                        HStack(spacing: 6) {
                            Image(systemName: result.contains("thành công") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 12))
                            Text(result)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(result.contains("thành công") ? SpaceTheme.connected : SpaceTheme.error)
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, 32)
            }
            .spaceBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Cài đặt")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { dismiss() }
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.5))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Lưu") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SpaceTheme.accentStart)
                }
            }
        }
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trên máy tính chạy lệnh")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(SpaceTheme.secondary)
            codeBlock("opencode serve --port 4096 --hostname 0.0.0.0")
            Text("Máy tính phải bật Tailscale, điện thoại dùng chung tài khoản Tailscale")
                .font(.system(size: 10))
                .foregroundColor(SpaceTheme.tertiary)
                .padding(.top, 2)
        }
        .padding(14)
        .background(SpaceTheme.subtle)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SpaceTheme.cardBorder, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func row(_ label: String, value: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(SpaceTheme.secondary)
            Spacer()
            TextField("", text: value)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func portRow() -> some View {
        HStack {
            Text("Cổng")
                .font(.system(size: 13))
                .foregroundColor(SpaceTheme.secondary)
            Spacer()
            TextField("4096", text: $port)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
                .keyboardType(.numberPad)
                .frame(width: 80)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func secureRow(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(SpaceTheme.secondary)
            Spacer()
            SecureField("", text: value)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func save() {
        let config = ServerConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 4096,
            username: username,
            password: password
        )
        viewModel.updateConfig(config)
        dismiss()
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let config = ServerConfig(
            host: host.trimmingCharacters(in: .whitespaces),
            port: Int(port) ?? 4096,
            username: username,
            password: password
        )
        let api = OpenCodeAPI(config: config)
        Task {
            do {
                let health = try await api.checkHealth()
                testResult = health.healthy
                    ? "Kết nối thành công - v\(health.version ?? "?")"
                    : "Máy chủ không khỏe"
            } catch {
                testResult = "Thất bại: \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}