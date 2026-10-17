# Hướng dẫn Ứng dụng Menu Bar macOS (Standalone App)

Tài liệu này giới thiệu kiến trúc, cách xây dựng và vận hành ứng dụng **Samsung Monitor Control** dành cho thanh trạng thái (Menu Bar) của macOS.

---

## 🖥️ Giới thiệu tổng quan

Ứng dụng **Samsung Monitor Control** là một ứng dụng native viết hoàn toàn bằng **Swift** và **SwiftUI**, được thiết kế siêu nhẹ dành riêng cho người dùng muốn điều khiển độ sáng màn hình Samsung ViewFinity S9 mà không muốn phụ thuộc vào các công cụ trả phí của bên thứ ba.

### Đặc điểm nổi bật:
- **0% CPU Idle:** Không chạy ngầm tiêu tốn tài nguyên, chỉ kích hoạt khi tương tác.
- **Không có Dock Icon:** Ứng dụng hoạt động thuần túy dưới dạng Agent (`LSUIElement = true`), chỉ xuất hiện icon trên Menu Bar.
- **Thanh trượt Debounce:** Cho phép kéo thả mượt mà; lệnh chỉ được gửi đi sau 100ms ngừng kéo, giúp socket Tizen không bị quá tải.
- **Phím chọn nhanh (Presets):** Mức 10 (Ban đêm), 25 (Văn phòng), 40 (Ban ngày), 50 (Tối đa).
- **Cấp quyền 1-chạm:** Tích hợp nút bắt tay pairing ngay trong giao diện, không cần mở Terminal.
- **Thay đổi IP linh hoạt:** Nút bánh răng cài đặt cho phép nhập lại IP mới bất cứ khi nào router cấp phát lại IP.

---

## 🏗️ Kiến trúc ứng dụng

```
+----------------------------------------------------------------+
|                   Samsung Monitor Control.app                  |
|                                                                |
|  [AppDelegate] ---> [NSStatusItem (Menu Bar)]                  |
|                           |                                    |
|                           v (Click mở Popover)                 |
|  [BrightnessPopoverView (SwiftUI)]                             |
|          |                 |                                   |
|          v                 v                                   |
|  [Slider (0..50)]   [Quick Presets]   [Pair Button]            |
|          \                 |                /                  |
|           +----------------+---------------+                   |
|                            |                                   |
|                            v                                   |
|                  [BrightnessModel (Swift)]                     |
|                            | (Debounce 100ms)                  |
|                            v                                   |
|                   [Foundation.Process]                         |
|                            | (Async background thread)         |
|                            v                                   |
|          [/usr/bin/python3 Resources/samsung_ipc.py]           |
+----------------------------+-----------------------------------+
                             |
                      (HTTPS Port 1516)
                             |
                             v
               [Samsung ViewFinity S9 Monitor]
```

### 1. Phân luồng bất đồng bộ (Non-blocking I/O)
Mọi tác vụ mạng (`get`, `set`, `pair`) đều được thực thi trên `DispatchQueue.global(qos: .userInitiated)` thông qua lớp `Foundation.Process`. Khi tiến trình con hoàn tất, kết quả được đồng bộ trở lại Main Thread để cập nhật UI, đảm bảo giao diện luôn phản hồi tức thì và không có hiện tượng giật lag ("bánh xe cầu vồng").

### 2. Định vị mã nguồn script thông minh
Hàm `getScriptPath()` trong [main.swift](file:///Volumes/My%20Data/Development/samsung-monitor-control/main.swift) kiểm tra theo thứ tự ưu tiên:
1. `Bundle.main.path(forResource: "samsung_ipc", ofType: "py")` (khi đã đóng gói thành file `.app`).
2. Đường dẫn `Contents/Resources/samsung_ipc.py`.
3. Thư mục mã nguồn phát triển tại `/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py`.

---

## ⚙️ Yêu cầu bảo mật trên macOS Sequoia (macOS 15+)

Kể từ macOS 15, Apple đưa ra cơ chế bảo vệ quyền riêng tư mạng nội bộ (**Local Network Privacy**). Để ứng dụng có thể kết nối đến cổng 1516 của màn hình S9 mà không bị hệ điều hành chặn:

1. **Khai báo trong `Info.plist`:**
   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>Ứng dụng cần quyền kết nối qua mạng nội bộ để điều khiển độ sáng màn hình Samsung ViewFinity S9.</string>
   ```
2. **Ký số Ad-hoc (Ad-hoc Code Signing):**
   Mã nhị phân biên dịch phải được ký định danh để hệ thống macOS lưu vết quyền cấp phép:
   ```bash
   codesign --force --deep --sign - "Samsung Monitor Control.app"
   ```

Khi bạn mở ứng dụng lần đầu, macOS sẽ hiển thị thông báo xin cấp quyền mạng nội bộ. Hãy bấm **Cho phép (Allow)**.

---

## 🚀 Hướng dẫn biên dịch và cài đặt

1. Mở Terminal và di chuyển vào thư mục dự án:
   ```bash
   cd "/Volumes/My Data/Development/samsung-monitor-control"
   ```
2. Chạy script đóng gói tự động:
   ```bash
   chmod +x build.sh
   ./build.sh
   ```
3. Script sẽ tự động hoàn tất quá trình biên dịch, chép ứng dụng vào thư mục `/Applications/Samsung Monitor Control.app` và khởi động ứng dụng lên Menu Bar của bạn.

---

## 🔄 Tự động mở khi khởi động máy Mac (Launch at Login)

Để ứng dụng tự chạy mỗi khi bạn bật máy Mac:
1. Vào **System Settings (Cài đặt hệ thống)** $\rightarrow$ **General (Cài đặt chung)** $\rightarrow$ **Login Items (Mục đăng nhập)**.
2. Tại mục **Open at Login (Mở khi đăng nhập)**, bấm dấu cộng **(+)**.
3. Chọn file `/Applications/Samsung Monitor Control.app` và bấm **Open**.
