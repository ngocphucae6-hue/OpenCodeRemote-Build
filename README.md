# OpenCodeRemote - iOS Client

Ứng dụng iOS để điều khiển OpenCode server từ iPhone/iPad.

## Tính năng mới

- ✅ **Update Models**: Nút cập nhật danh sách models từ server PC
- ✅ **Filter Models**: Toggle ẩn/hiện chỉ model đang dùng trong ModelPicker

## Cấu trúc dự án

```
OpenCodeRemote/
├── OpenCodeRemote.xcodeproj
├── OpenCodeRemote/
│   ├── Views/
│   │   ├── ChatView.swift          # Giao diện chat chính
│   │   ├── ModelPickerView.swift   # Chọn model
│   │   ├── SettingsView.swift
│   │   └── ContentView.swift
│   ├── ViewModels/
│   │   ├── ChatViewModel.swift
│   │   ├── ModelPickerViewModel.swift
│   │   └── SessionListViewModel.swift
│   ├── Models/
│   │   ├── Session.swift
│   │   ├── Provider.swift
│   │   └── ServerConfig.swift
│   ├── Services/
│   │   ├── OpenCodeAPI.swift       # HTTP client
│   │   ├── EventStreamService.swift # SSE
│   │   └── NotificationManager.swift
│   ├── Design/
│   │   ├── SpaceTheme.swift
│   │   └── SpaceBackground.swift
│   └── OpenCodeRemoteApp.swift
├── build.sh                         # Build script local
├── ExportOptions.plist              # Config export
└── .github/workflows/build.yml      # GitHub Actions
```

## Build trên macOS

### Yêu cầu
- macOS 14+
- Xcode 16+
- Apple Developer account
- Provisioning profile: `JQiRAaCKdW-03062026.mobileprovision`

### Setup Provisioning Profile

```bash
# Copy profile vào thư mục mặc định của Xcode
cp /path/to/JQiRAaCKdW-03062026.mobileprovision \
  ~/Library/MobileDevice/Provisioning\ Profiles/
```

### Build thủ công

```bash
# Dùng script có sẵn
chmod +x build.sh
./build.sh

# Hoặc dùng xcodebuild trực tiếp
xcodebuild -project OpenCodeRemote.xcodeproj \
  -scheme OpenCodeRemote \
  -configuration Release \
  archive \
  -archivePath build/OpenCodeRemote.xcarchive \
  DEVELOPMENT_TEAM="JQiRAaCKdW" \
  CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="JQiRAaCKdW-03062026" \
  PRODUCT_BUNDLE_IDENTIFIER="com.opencode.remote.ocr2026"

xcodebuild -exportArchive \
  -archivePath build/OpenCodeRemote.xcarchive \
  -exportPath build \
  -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates
```

### Build với GitHub Actions

1. Push code lên GitHub
2. Workflow sẽ tự động chạy trên runner macOS
3. Download IPA từ tab "Actions" → artifact "OpenCodeRemote-iPA"

#### Manual trigger:
- Vào GitHub → Actions → "Build and Sign IPA" → "Run workflow"
- Chọn environment: development / ad-hoc / enterprise

## Cấu hình Server

Lần đầu chạy app, vào **Settings** để nhập:
- **Host**: IP của server OpenCode (mặc định: 100.104.242.86)
- **Port**: 4096
- **Username**: opencode
- **Password**: mật khẩu server

Mật khẩu được lưu trong Keychain.

## Chức năng chính

### 1. Chat với AI Agent
- Gửi text và ảnh
- Xem real-time progress (todos, tool calls)
- Download file outputs (ipa, pdf, zip, images...)

### 2. Chọn Model
- Nhấn nút model ở toolbar phải
- Chọn provider và model
- Có **nút Update Models** (↻) để đồng bộ danh sách từ server

### 3. Filter Models
Trong ModelPicker, toggle **"Chỉ hiện model đang dùng"**:
- Khi bật: chỉ hiện provider đã chọn và model hiện tại
- Khi tắt: hiện tất cả models

### 4. Mode Bar
- **Lập kế hoạch**: Agent chỉ lập kế hoạch, không sửa file
- **Thực thi**: Agent thực thi đầy đủ

### 5. Skill & Commands
- Nhấn nút **Skill** để xem danh sách skill/command
- Chọn để agent biết và gọi

## Kiến trúc

### API Endpoints (OpenCodeAPI.swift)
- `/global/health` - health check
- `/session` - list/create/delete sessions
- `/project` - list projects
- `/session/{id}/prompt_async` - gửi message
- `/session/{id}/message` - lấy messages
- `/session/{id}/todo` - lấy todos
- `/session/status` - trạng thái sessions
- `/provider` - list providers/models
- `/config` - update model config
- `/skill` & `/command` - list skills/commands
- `/question` & `/question/{id}/reply` - handle questions
- `/permission` & `/permission/{id}/reply` - handle permissions
- `/file/content?path=...` - download file
- `/event` - SSE events

### Event Stream (SSE)
- Kết nối `/event` để nhận real-time updates
- Auto-reconnect khi app active
- Poll fallback nếu SSE không hoạt động

### Models
- `OCSession`: session info + model + directory
- `OCMessageWithParts`: tin nhắn với nhiều parts (text, file, tool)
- `OCPart`: text, reasoning, tool, file
- `OCToolState`: status, title, output, input, metadata
- `OCQuestionRequest`: agent hỏi người dùng
- `OCPermissionRequest`: agent xin quyền

## Troubleshooting

### "Cannot connect to server"
- Kiểm tra host/port trong Settings
- Kiểm tra firewall cho phép port 4096
- Server phải chạy và lắng nghe đúng interface

### Models not updating
- Nhấn nút ↻ (Update Models) trong toolbar
- Kiểm tra server log xem `/provider` endpoint trả data đúng

### Build lỗi signing
- Đảm bảo provisioning profile đã được install
- Team ID phải khớp với profile
- Bundle identifier phải khớp với App ID trong Apple Developer

## License

[Your License Here]

---

**Phát triển bởi:** Anthropic Claude Code  
**Version:** 1.0  
**Last Updated:** 2025
