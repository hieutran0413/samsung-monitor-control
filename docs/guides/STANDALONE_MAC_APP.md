# Hướng dẫn Ứng dụng Menu Bar macOS (Standalone App)

Tài liệu này giới thiệu kiến trúc, cách xây dựng và vận hành ứng dụng **Samsung Monitor Control** dành cho thanh trạng thái (Menu Bar) của macOS.

---

## 🖥️ Giới thiệu tổng quan

Ứng dụng **Samsung Monitor Control** là một ứng dụng native viết hoàn toàn bằng **Swift** và **SwiftUI**, được thiết kế siêu nhẹ dành riêng cho người dùng muốn điều khiển độ sáng màn hình Samsung ViewFinity S9 mà không muốn phụ thuộc vào các công cụ trả phí của bên thứ ba.

### Đặc điểm nổi bật:
- **Menu Bar:** Không cần cửa sổ chính; chưa có số đo CPU cho phiên bản hiện tại.
- **Không có Dock Icon:** Ứng dụng hoạt động thuần túy dưới dạng Agent (`LSUIElement = true`), chỉ xuất hiện icon trên Menu Bar.
- **Thanh trượt Debounce:** Cho phép kéo thả mượt mà; lệnh chỉ được gửi đi sau 80ms ngừng kéo, giúp socket Tizen không bị quá tải.
- **Phím chọn nhanh (Presets):** Mức 10 (Ban đêm), 25 (Văn phòng), 40 (Ban ngày), 50 (Tối đa).
- **Cấp quyền 1-chạm:** Tích hợp nút bắt tay pairing ngay trong giao diện, không cần mở Terminal.
- **Thay đổi IP:** Tab Kết nối có trường nhập IP/hostname và nút Lưu & ghép nối. IP trên UI chỉ cập nhật sau ghép nối thành công.

---

## Giao diện native cập nhật 2026-10-18

App dùng `NSStatusItem`/`NSPopover` của AppKit và control SwiftUI native; không có pill, D-pad hoặc slider tự vẽ. Header chứa tên màn hình, trạng thái đọc kết nối, làm mới và nút **Tắt màn hình** luôn nhìn thấy. Popover 400×560pt giữ header/footer cố định; bốn tab có vùng cuộn riêng với chỉ báo cuộn hệ thống.

| Tab | Chức năng | Cách dùng |
| --- | --- | --- |
| Nhanh | Đèn nền 0–50, preset 10/25/40/50, âm lượng 0–100, mute, sound mode và speaker output | Slider gửi lệnh sau 80ms ngừng thay đổi; giá trị là mức phần cứng, không phải độ sáng đo bằng nit. Mute khóa trong lúc gửi để tránh toggle chồng nhau. |
| Hình ảnh | Không gian màu, Game Mode Off/On/Auto, màu 0–50, contrast 0–50, sharpness 0–20, tint −15…15, black level −5…5 | Tint/black level nằm trong Tinh chỉnh màu. Không coi Game Mode Off là bảo đảm chuẩn màu. |
| Remote | D-pad, OK, Quay lại, Home, Menu, bàn phím opt-in và công cụ developer | Chỉ bật bàn phím khi muốn gửi phím tới Samsung; đóng popover/đổi tab tắt chế độ. Không nhận phím từ app khác. |
| Kết nối | IP/hostname, ghép nối, input, danh sách USB đọc từ Mac | Nhập host rồi Lưu & ghép nối, dùng remote chọn Allow. Nguồn vào khác có thể làm mất hình ảnh Mac. USB được liệt kê từ Mac, không khẳng định mọi thiết bị đều ở hub màn hình. |

### Tắt màn hình

Bấm **Tắt màn hình** trên header. Swift gửi `samsung_ipc.py power off`; Python chuyển thành RPC `powerControl` với giá trị `powerOff`. Bản cũ gửi trực tiếp `powerOff` vào CLI và bị argparse từ chối. Trong lúc gửi nút bị khóa; kết quả hiện ở Thông báo từ màn hình. Mở disclosure để đọc/copy chi tiết, phần chi tiết cuộn được khi dài. Thành công RPC không thay thế việc quan sát panel vật lý. Dùng remote để bật màn hình lại, rồi bấm làm mới để đọc trạng thái.

### Bàn phím và focus

Ở tab Remote, bật **Dùng bàn phím cho remote**: mũi tên điều hướng, Enter chọn, Esc quay lại, M Menu, H Home, số 0–9. Chỉ local key event không có Command/Control/Option được chuyển tiếp; TextField được miễn chặn. Mặc định chế độ tắt để mũi tên/Enter phục vụ control native. Các tổ hợp hệ thống không bị đổi thành lệnh remote. Chưa kiểm chứng VoiceOver hoặc toàn bộ focus traversal qua runtime.

### Kết nối, lỗi và kiểm chứng

Nhãn Đã kết nối chỉ xuất hiện sau lượt `status` đọc JSON thành công. Khi chưa kết nối/đang đọc/đang ghép nối/đang tắt, các tab điều khiển phần cứng khóa; Kết nối và làm mới vẫn giúp phục hồi theo trạng thái. Lỗi ghi Picker khôi phục lựa chọn trước đó; slider hiện vẫn cập nhật lạc quan, cần readback để đối chiếu nếu lệnh thất bại. Không có polling kiểm chứng liên tục nên nhãn kết nối chỉ phản ánh lượt đọc gần nhất.

Ngày 2026-10-18: build và cài đặt thành công, 2 power-contract regression test pass bằng mock không gọi màn hình. Runtime UI sau sửa và tắt vật lý chưa xác nhận vì công cụ chọn app menu bar bị timeout. Audit ảnh người dùng, nguyên nhân, thay đổi và checklist đầy đủ: [AUDIT.md](../audits/2026-10-18-native-ui/AUDIT.md).

## 🏗️ Kiến trúc ứng dụng

```
+----------------------------------------------------------------+
|                   Samsung Monitor Control.app                  |
|                                                                |
|  [AppDelegate] ---> [NSStatusItem (Menu Bar)]                  |
|                           |                                    |
|                           v (Click mở Popover)                 |
|  [MonitorPopoverView (SwiftUI)]                             |
|          |                 |                                   |
|          v                 v                                   |
|  [Slider (0..50)]   [Quick Presets]   [Pair Button]            |
|          \                 |                /                  |
|           +----------------+---------------+                   |
|                            |                                   |
|                            v                                   |
|                  [MonitorModel (Swift)]                     |
|                            | (Debounce 80ms)                  |
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

### Hiệu chỉnh sRGB/P3 trên ViewFinity S9 (2026-10-18)

Theo đối chiếu OSD hai chiều của người dùng, sRGB dùng `Gen_327712`, DCI-P3 dùng `Gen_327714`. Mapping trước đó bị đảo. App/CLI nay dùng nhãn đã sửa và chỉ cập nhật lựa chọn sau khi đọc lại raw từ `getTVStates`; nếu không khớp lệnh đã gửi, app báo chưa xác nhận thay vì coi echo của lệnh là thành công. Picker khóa trong lúc chờ. Các mã firmware khác vẫn cần kiểm chứng trên thiết bị tương ứng; việc chọn preset không phải đo hoặc hiệu chuẩn gamut. Chi tiết bằng chứng và test nằm ở mục Follow-up trong [audit](../audits/2026-10-18-native-ui/AUDIT.md).

### Khôi phục độ nét sau khi bật lại màn hình

Trong tab **Hình ảnh**, dưới slider **Độ nét**, bấm **Khôi phục độ nét**. App chụp mức đang hiển thị khi bấm: ví dụ 10 → 9 → 10. Với mức 0, trình tự là 0 → 1 → 0; với mức 20 là 20 → 19 → 20. Mỗi lần chỉ lệch một đơn vị và không vượt dải phần cứng 0–20. Đây là thao tác thủ công một nút theo yêu cầu, không tự chạy khi thức dậy/bật nguồn và không đổi preset mặc định.

CLI tương ứng: `python3 samsung_ipc.py refresh-sharpness 10`. Hai lệnh ghi chạy tuần tự trong một process, chờ 150ms sau lần ghi đầu rồi trả về target. Kết thúc có đọc `sharpnessControl` để xác nhận. Nếu lần ghi đầu timeout, vẫn thử ghi target vì màn hình có thể đã nhận lệnh nhưng phản hồi bị mất. Nếu khôi phục thất bại, lỗi ghi rõ mức cần đặt lại. Không báo thành công nếu readback khác target. Mất kết nối hoặc process bị dừng giữa hai lệnh vẫn có thể để màn hình ở mức tạm; đặt lại mức cũ khi kết nối trở lại.

Nút bị khóa khi slider còn lệnh chờ/đang ghi, lúc đọc trạng thái/ghép nối/đổi profile màu hoặc khi thao tác khôi phục đã chạy. Trong lúc khôi phục, slider khóa, thao tác nguồn và làm mới không chạy xen vào. UI giữ nguyên target để người dùng biết mốc cần khôi phục; không nhấp nháy hiển thị mức tạm. Thành công chỉ xác nhận giá trị RPC trở lại mốc cũ, không chứng minh lỗi sắc nét thực tế đã hết.

Kiểm chứng 2026-10-18: 5 test mới bao gồm mức 0/10/20, timeout bước đầu vẫn restore, lỗi restore, readback sai và target ngoài dải; tổng 10 test pass bằng mock không gọi phần cứng. Build/cài lại app. Còn kiểm chứng trực tiếp sau một chu kỳ tắt/bật màn hình, quan sát hình ảnh và thử nút ở mức độ nét thường dùng. Mốc dùng là giá trị đang hiển thị khi bấm, không thêm cấu hình độ nét lưu riêng qua các phiên.
