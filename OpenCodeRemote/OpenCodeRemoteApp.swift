import SwiftUI

@main
struct OpenCodeRemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Bật watcher thông báo nền + xin quyền notif 1 lần ngay khi mở app.
        NotificationManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            // Vào lại app -> nối lại watcher để không bỏ lỡ câu hỏi/quyền khi ở nền.
            if phase == .active {
                NotificationManager.shared.resume()
            }
        }
    }
}
