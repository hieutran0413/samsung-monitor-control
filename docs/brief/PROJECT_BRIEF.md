# Project Brief: Samsung ViewFinity S9 Hardware Brightness Control

> **Tài liệu Định hướng & Phạm vi Sản phẩm (Product Brief)**  
> Chuẩn hóa theo tiêu chuẩn dự án của `init-product-project`.

---

## 1. Bối cảnh & Vấn đề Cốt lõi (Problem Statement)

- **Thực trạng:** Màn hình **Samsung ViewFinity S9 (5K - S90PC)** có phần cứng hiển thị cao cấp (tấm nền 5K, phủ matte, tích hợp Tizen Smart TV), nhưng firmware Samsung đã vô hiệu hóa hoàn toàn giao thức DDC/CI chuẩn VESA qua cổng Thunderbolt/Type-C.
- **Hệ quả đối với người dùng Mac:**
  - Không thể điều chỉnh độ sáng bằng phím vật lý F1/F2.
  - macOS Control Center không hiển thị thanh trượt độ sáng màn hình ngoài.
  - Các phần mềm phổ biến như *MonitorControl* hay *DisplayBuddy* thất bại trong việc điều khiển đèn nền phần cứng; một số phần mềm âm thầm chuyển sang "software dimming" (phủ lớp đen mờ ảo), làm bệt màu đen và giảm sút độ tương phản gốc của màn hình 5K.
- **Giải pháp của dự án:** Khai thác dịch vụ **Samsung IP Control G2** trên cổng **TCP 1516** (HTTPS JSON-RPC 2.0) để điều chỉnh trực tiếp mức đèn nền vật lý (`backlight` 0–50) của màn hình qua mạng nội bộ.

---

## 2. Mục tiêu Sản phẩm (Goals & Outcomes)

### A. Mục tiêu đạt được (Core Outcomes)
1. **100% Đèn nền Phần cứng (Hardware Backlight):** Thay đổi cường độ phát sáng của bóng LED vật lý từ mức 0 đến 50, không sử dụng lớp phủ mờ phần mềm, bảo toàn 100% độ chính xác màu và độ tương phản.
2. **Trải nghiệm Native macOS thông qua BetterDisplay:**
   - Điều khiển mượt mà bằng phím **F1 / F2** trên bàn phím Mac.
   - Hiển thị **Apple Native Sun OSD Bezel**.
   - Tự động đồng bộ độ sáng theo cảm biến ánh sáng xung quanh của MacBook (**Ambient Light Sensor Sync**).
3. **Ứng dụng Standalone Menu Bar Native (Swift + SwiftUI):**
   - Ứng dụng thanh menu siêu nhẹ, 0% CPU lúc nghỉ.
   - Hỗ trợ thanh trượt Debounce, 4 nút chọn nhanh (10, 25, 40, 50).
   - Nút bấm ghép nối / cấp quyền trực tiếp trong giao diện và ô thay đổi địa chỉ IP.
4. **Công cụ dòng lệnh CLI độc lập (`samsung_ipc.py`):**
   - Hoạt động độc lập bằng Python 3 chuẩn của macOS, không cần cài đặt thư viện ngoài (`pip`).
   - Sẵn sàng tích hợp vào Raycast Script Commands, Alfred Workflow, hoặc macOS Shortcuts.

### B. Những gì nằm ngoài phạm vi (Non-Goals)
- Không can thiệp sâu vào kernel macOS (không cài kext, không tắt SIP).
- Không can thiệp vào chỉnh âm lượng Tizen (loa ngoài hoặc tai nghe đã được macOS quản lý qua audio endpoint).
- Không hỗ trợ các màn hình không có hệ điều hành Tizen / IP Control.

---

## 3. Ranh giới Kỹ thuật & Ràng buộc (Constraints)

- **Hệ điều hành:** macOS 12.0 Monterey trở lên (đã kiểm thử và tối ưu cho macOS 15 Sequoia với quyền `NSLocalNetworkUsageDescription`).
- **Môi trường:**
  - Python 3 (sử dụng `/usr/bin/python3` có sẵn của hệ điều hành).
  - Swift 5.9+ với `swiftc` native command-line tool.
- **Yêu cầu mạng:** Máy Mac và Màn hình Samsung S9 phải kết nối chung một mạng LAN/WiFi nội bộ (có thể ping thấy nhau).
- **Quyền riêng tư:** Lưu trữ AccessToken bảo mật tại `~/.samsung_monitor_control.json` (chmod 0600) và macOS Keychain.

---

## 4. Người dùng Mục tiêu (Target Audience)

- Người dùng sở hữu máy Mac (MacBook Pro, Mac Studio, Mac mini) kết nối với màn hình Samsung ViewFinity S9 (5K) hoặc các dòng Samsung Smart Monitor có hỗ trợ Tizen IP Control.
- Lập trình viên, nhà thiết kế đồ họa yêu cầu độ chính xác màu sắc tuyệt đối (không chấp nhận software dimming làm sai màu).
- Người dùng mong muốn trải nghiệm đồng bộ như Apple Studio Display mà không phải chi trả thêm chi phí phần cứng.
