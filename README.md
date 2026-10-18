# Samsung ViewFinity S9 Hardware Brightness Control for macOS

> **Điều khiển độ sáng đèn nền vật lý (Real Hardware Backlight 0–50) cho màn hình Samsung ViewFinity S9 (5K) và các dòng Samsung Smart Monitor trên macOS thông qua giao thức Samsung IP Control (Cổng 1516).**

[![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue.svg)](https://apple.com/macos)
[![Python](https://img.shields.io/badge/python-3.8%2B-green.svg)](https://python.org)
[![Swift](https://img.shields.io/badge/swift-5.9%2B-orange.svg)](https://swift.org)
[![BetterDisplay](https://img.shields.io/badge/integration-BetterDisplay-purple.svg)](https://github.com/waydabber/BetterDisplay)

---

## 📌 Mục lục

1. [Tại sao dự án này ra đời?](#-tại-sao-dự-án-này-ra-đời)
2. [Sự thật về DDC/CI và DisplayBuddy](#-sự-thật-về-ddcci-và-displaybuddy)
3. [Kiến trúc giải pháp: Samsung IP Control (Port 1516)](#-kiến-trúc-giải-pháp-samsung-ip-control-port-1516)
4. [Các phương thức sử dụng](#-các-phương-thức-sử-dụng)
   - [Phương án 1: Tích hợp BetterDisplay (Khuyên dùng)](#phương-án-1-tích-hợp-betterdisplay-khuyên-dùng---trải-nghiệm-native)
   - [Phương án 2: Ứng dụng Menu Bar macOS (Native Swift)](#phương-án-2-ứng-dụng-menu-bar-macos-native-swift--swiftui)
   - [Phương án 3: Python CLI (Dành cho Raycast / Alfred / Terminal)](#phương-án-3-python-cli)
5. [Cấu hình trên màn hình Samsung ViewFinity S9](#-cấu-hình-trên-màn-hình-samsung-viewfinity-s9)
6. [Hướng dẫn ghép nối (Pairing) & Lấy AccessToken](#-hướng-dẫn-ghép-nối-pairing--lấy-accesstoken)
7. [Cấu hình chi tiết trong BetterDisplay](#-cấu-hình-chi-tiết-trong-betterdisplay)
8. [Biên dịch và cài đặt ứng dụng Menu Bar](#-biên-dịch-và-cài-đặt-ứng-dụng-menu-bar)
9. [Xử lý sự cố (Troubleshooting)](#-xử-lý-sự-cố-troubleshooting)

---

## 🎯 Tại sao dự án này ra đời?

Màn hình **Samsung ViewFinity S9 (S90PC - 5K)** là một trong những lựa chọn thay thế tốt nhất cho Apple Studio Display với tấm nền 5K sắc nét, lớp phủ chống chói Matte và tích hợp hệ điều hành Tizen Smart TV.

Tuy nhiên, trải nghiệm trên macOS lại gặp phải rào cản lớn:
- **macOS không cho phép điều khiển độ sáng màn hình ngoài** nếu không phải màn hình chính hãng của Apple (Studio Display / Pro Display XDR) hoặc màn hình hợp tác độc quyền (LG UltraFine qua Apple USB-HID).
- Các thanh trượt độ sáng trong **Control Center** của macOS bị khóa cứng (chỉ áp dụng cho màn hình tích hợp của MacBook).

---

## 🔍 Sự thật về DDC/CI và DisplayBuddy

Rất nhiều người dùng Mac khi mua ViewFinity S9 đã thử các giải pháp phổ biến và thất vọng:

| Giải pháp | Cơ chế hoạt động | Kết quả trên Samsung ViewFinity S9 |
| :--- | :--- | :--- |
| **MonitorControl / Lunar / DDC tiêu chuẩn** | Gửi lệnh VESA MCCS (`0x10`) qua kênh DDC/CI trên cáp DisplayPort/Thunderbolt | ❌ **Thất bại hoàn toàn.** Samsung đã tắt hoàn toàn kênh nhận lệnh DDC/CI phần cứng trên firmware của dòng màn hình thông minh. |
| **DisplayBuddy (kết nối WiFi Tizen)** | Kết nối WebSocket vào cổng `8002` (cổng điều khiển Smart TV thông thường) | ⚠️ **Chỉ là giảm độ sáng giả lập (Software Dimming).** Cổng 8002 không có API điều khiển đèn nền phần cứng; app âm thầm phủ một lớp đen mờ lên màn hình, làm bệt màu đen và mất độ tương phản gốc của panel 5K. |
| **Samsung IP Control (Dự án này)** | Kết nối HTTPS JSON-RPC 2.0 vào cổng **TCP 1516** | ✅ **100% Đèn nền phần cứng (Hardware Backlight).** Thay đổi trực tiếp giá trị `backlight` từ `0` đến `50` trong chip điều khiển của Tizen, tiết kiệm điện năng và bảo toàn độ chính xác màu sắc. |

---

## ⚡ Kiến trúc giải pháp: Samsung IP Control (Port 1516)

Samsung trang bị giao thức chuyên nghiệp **Samsung IP Control G2** trên cổng `1516` (thường dành cho các hệ thống tự động hóa nhà cao cấp như Crestron, Control4, Savant):

```
+-------------------------------------------------------------------------+
|                              macOS Host                                 |
|                                                                         |
|  [F1/F2 Keys] ---> [BetterDisplay]                                      |
|                            | (Gọi lệnh qua Custom Control)              |
|  [Menu Bar App] ---> [samsung_ipc.py]                                    |
|                            |                                            |
|                            v                                            |
|         HTTPS JSON-RPC 2.0 (TLS tự ký, Port 1516)                      |
|         Method: "backlightControl" { "backlight": 0..50 }               |
+----------------------------+--------------------------------------------+
                             |
                      (WiFi / LAN Nội bộ)
                             |
                             v
+-------------------------------------------------------------------------+
|                  Samsung ViewFinity S9 (Tizen OS)                       |
|                                                                         |
|  [TCP 1516 Daemon] ---> [Tizen Backlight Controller] ---> [LED Backlight]|
+-------------------------------------------------------------------------+
```

---

## 🚀 Các phương thức sử dụng

### Phương án 1: Tích hợp BetterDisplay (Khuyên dùng - Trải nghiệm Native)
- Sử dụng phím **F1 / F2** trên bàn phím Mac để tăng giảm độ sáng.
- Hiển thị **OSD biểu tượng mặt trời** native của macOS.
- Tự động đồng bộ độ sáng theo cảm biến ánh sáng của MacBook (**Ambient Light Sensor Sync**).
- Xem chi tiết: [Hướng dẫn cấu hình BetterDisplay](docs/guides/BETTERDISPLAY_INTEGRATION.md).

### Phương án 2: Ứng dụng Menu Bar macOS (Native Swift + SwiftUI)
- Ứng dụng menu bar native AppKit + SwiftUI, dùng Button, Slider, Picker, TabView và GroupBox hệ thống.
- Nút **Tắt màn hình** nằm cố định ở header, gửi `power off` đúng hợp đồng CLI; có trạng thái chờ và chống bấm lặp.
- Bốn tab: **Nhanh** (đèn nền/âm lượng), **Hình ảnh** (profile/Game Mode/chỉnh màu), **Remote**, **Kết nối** (pairing/IP/nguồn vào/USB).
- Shortcut remote chỉ hoạt động trong app, ở tab Remote sau khi bật chế độ bàn phím; không nhận phím từ app khác.
- Bản 2026-10-18 đã build/cài và qua test hợp đồng power bằng mock; nghiệm thu UI và tắt màn hình vật lý còn mở. [Audit và giới hạn kiểm chứng](docs/audits/2026-10-18-native-ui/AUDIT.md).
- Xem chi tiết: [Hướng dẫn Standalone Mac App](docs/guides/STANDALONE_MAC_APP.md).

### Phương án 3: Python CLI Đa Năng
Hỗ trợ đầy đủ các tính năng phần cứng, tích hợp dễ dàng vào Raycast Script Commands, Alfred Workflow, hoặc macOS Shortcuts:
```bash
# 1. Điều khiển độ sáng đèn nền thật (0-50)
python3 samsung_ipc.py get                  # Đọc độ sáng hiện tại
python3 samsung_ipc.py set 35               # Đặt độ sáng mức 35
python3 samsung_ipc.py up / down            # Tăng / Giảm 5 mức

# 2. Điều khiển Game Mode (Low Latency)
python3 samsung_ipc.py game-mode            # Xem trạng thái Game Mode
python3 samsung_ipc.py game-mode on         # Bật Game Mode (giảm độ trễ tối đa)
python3 samsung_ipc.py game-mode off        # Tắt Game Mode (chuẩn màu đồ họa)
python3 samsung_ipc.py game-mode auto       # Chế độ tự động

# 3. Chỉnh thông số hình ảnh phần cứng
python3 samsung_ipc.py contrast 45          # Đặt độ tương phản (0-50)
python3 samsung_ipc.py sharpness 10         # Đặt độ sắc nét (0-20)

# 4. Điều khiển âm thanh & loa màn hình
python3 samsung_ipc.py sound-mode Music     # Đổi chế độ âm thanh (Standard/Game/Music/Movie/Amplify/Adaptive)
python3 samsung_ipc.py volume 60            # Đặt âm lượng loa 60%
python3 samsung_ipc.py mute toggle          # Bật/tắt tiếng loa màn hình

# 5. Phím điều khiển từ xa & Nguồn
python3 samsung_ipc.py key menu             # Gửi phím remote (enter, return, firstScreen, cursorUp...)
python3 samsung_ipc.py power off            # Tắt màn hình thật
python3 samsung_ipc.py status               # Xuất toàn bộ trạng thái hiện tại dưới dạng JSON
```

---

## 📺 Cấu hình trên màn hình Samsung ViewFinity S9

Để màn hình chấp nhận kết nối qua cổng 1516, bạn bắt buộc phải bật 2 tính năng sau trên màn hình:

1. Dùng Remote điều khiển của màn hình, bấm nút **Home/Settings**.
2. Vào **All Settings (Tất cả cài đặt)** $\rightarrow$ **Connection (Kết nối)** $\rightarrow$ **Network (Mạng)** $\rightarrow$ **Expert Settings (Cài đặt chuyên môn)**.
3. Bật **IP Remote** sang trạng thái **ON (Bật)**.
4. Bật **Power On with Mobile** sang trạng thái **ON (Bật)**.
5. Kiểm tra địa chỉ IP của màn hình tại: **Network $\rightarrow$ Network Status $\rightarrow$ IP Settings** (Ví dụ: `192.168.x.x`).

> ⚠️ **LƯU Ý QUAN TRỌNG:** Màn hình phải đang hiển thị hình ảnh từ máy Mac (ngõ Type-C / Thunderbolt). Nếu màn hình đang ở giao diện Tizen Home Screen hoặc đang chạy app YouTube/Netflix, cửa sổ popup xin cấp quyền sẽ không thể hiển thị đè lên màn hình!

---

## 🔑 Hướng dẫn ghép nối (Pairing) & Lấy AccessToken

Chỉ cần thực hiện **1 lần duy nhất**:

1. Mở Terminal trên Mac và chạy lệnh pair:
   ```bash
   python3 samsung_ipc.py pair 192.168.x.x
   ```
   *(Thay bằng IP màn hình của bạn)*

2. Nhìn lên góc trên bên phải màn hình Samsung S9, bạn sẽ thấy popup:
   > **"Do you want to allow Mac to control this monitor?"**

3. Dùng remote điều khiển của màn hình bấm **Allow (Cho phép)**.
4. Terminal sẽ lập tức nhận Token và tự động lưu an toàn vào:
   - `~/.samsung_monitor_control.json` (chế độ bảo mật `0600`)
   - macOS Keychain (`service: samsung-ip-control`)

5. Kiểm tra thử xem đèn nền có đổi thật hay không:
   ```bash
   python3 samsung_ipc.py set 10
   python3 samsung_ipc.py set 40
   ```

Xem thêm chi tiết tại [Hướng dẫn Pairing & Token](docs/guides/PAIRING_AND_TOKENS.md).

---

## 🎛️ Cấu hình chi tiết trong BetterDisplay

Nếu bạn dùng BetterDisplay (bản Pro), hãy làm theo các bước sau để điều khiển bằng phím F1/F2:

1. Mở **BetterDisplay Settings** $\rightarrow$ chọn màn hình **Samsung ViewFinity S9**.
2. Chọn tab **Control** $\rightarrow$ cuộn xuống mục **Custom Control Integration** (hoặc External CLI Integration).
3. Điền các thông số chuẩn xác như sau:

| Mục thiết lập trong BetterDisplay | Giá trị cần điền |
| :--- | :--- |
| **Control method** | `External CLI / Script` |
| **Action** | `Run shell script` |
| **Shell script (zsh)** | `/usr/bin/python3 "/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py" set [*:VALUE:*]` |
| **Value format string** | `%.0f` |
| **Get current value script** | `/usr/bin/python3 "/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py" get` |
| **Value multiplier** | `50.0` |
| **Minimum / Maximum** | `0.0` / `1.0` (quy đổi sang dải 0–50) |
| **Min time between actions** | `0.2s` |

Sau khi áp dụng, bạn có thể chỉnh độ sáng bằng phím **F1/F2** trên bàn phím Apple, hiển thị OSD mặt trời chuẩn macOS!

Xem hình ảnh và hướng dẫn chi tiết tại [Tài liệu BetterDisplay Integration](docs/guides/BETTERDISPLAY_INTEGRATION.md).

---

## 🛠️ Biên dịch và cài đặt ứng dụng Menu Bar

Nếu bạn muốn có một app menu bar riêng biệt chạy native bằng Swift:

1. Di chuyển vào thư mục dự án và cấp quyền thực thi cho script:
   ```bash
   cd "/Volumes/My Data/Development/samsung-monitor-control"
   chmod +x build.sh
   ```

2. Chạy script đóng gói tự động:
   ```bash
   ./build.sh
   ```

Script sẽ tự động:
- Biên dịch mã nguồn Swift tối ưu hóa (`-O`).
- Đóng gói cấu trúc `Samsung Monitor Control.app`.
- Thêm `NSLocalNetworkUsageDescription` vào `Info.plist` (tránh lỗi No route to host trên macOS 15 Sequoia).
- Ký số ad-hoc code-signing (`codesign --force --deep --sign -`).
- Chép vào thư mục `/Applications/` và khởi chạy ngay lập tức.

---

## 🔧 Xử lý sự cố (Troubleshooting)

### 1. Lỗi `[Errno 65] No route to host`
- **Nguyên nhân:** Tính năng bảo mật Local Network Privacy của macOS Sequoia (macOS 15+).
- **Khắc phục:** Vào **System Settings $\rightarrow$ Privacy & Security $\rightarrow$ Local Network**, tìm **Terminal** hoặc **Samsung Monitor Control** và bật công tắc cho phép.

### 2. Lỗi `Pairing timed out` hoặc không thấy popup Allow
- **Nguyên nhân:** Màn hình đang ở Home Tizen hoặc màn hình khóa, hoặc chưa bật "IP Remote".
- **Khắc phục:** Chuyển màn hình về nguồn phát của Mac (Thunderbolt), kiểm tra lại mục **Expert Settings $\rightarrow$ IP Remote = ON**, sau đó chạy lại lệnh pair.

### 3. Đổi router WiFi hoặc IP màn hình bị nhảy
- Nếu router cấp IP mới cho màn hình, bạn chỉ cần cập nhật IP mới:
  ```bash
  python3 samsung_ipc.py set-host <IP_MỚI>
  ```
  Hoặc bấm biểu tượng **bánh răng cài đặt** trên ứng dụng Menu Bar để lưu IP mới và bấm Pair lại.

---

## 📄 License
Phát hành dưới giấy phép MIT. Tự do sử dụng, chỉnh sửa và tích hợp.
