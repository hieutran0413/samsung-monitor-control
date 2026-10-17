# Hướng dẫn Ghép nối (Pairing) & Quản lý Token Xác thực

Tài liệu này giải thích chi tiết quy trình bắt tay bảo mật của giao thức **Samsung IP Control G2**, cách lấy AccessToken và cơ chế lưu trữ an toàn trên macOS.

---

## 1. Yêu cầu tiên quyết trên màn hình Samsung ViewFinity S9

Trước khi tiến hành ghép nối, bạn cần kích hoạt các tính năng cho phép điều khiển từ xa qua mạng IP:

1. **Bật IP Remote:**
   - Dùng remote, vào **Cài đặt (Settings)** $\rightarrow$ **Tất cả cài đặt (All Settings)**.
   - Chọn **Kết nối (Connection)** $\rightarrow$ **Mạng (Network)** $\rightarrow$ **Cài đặt chuyên môn (Expert Settings)**.
   - Bật **IP Remote** sang **ON**.

2. **Bật Bật nguồn bằng thiết bị di động (Power On with Mobile):**
   - Vẫn trong mục **Expert Settings**, bật tính năng này sang **ON**. Tính năng này giữ cho card mạng WiFi/LAN của màn hình luôn lắng nghe tín hiệu ngay cả khi màn hình đang ở trạng thái Standby.

3. **Kiểm tra trạng thái hiển thị của màn hình:**
   - Đảm bảo màn hình đang cắm cáp Type-C/Thunderbolt vào máy Mac và đang hiển thị màn hình desktop của Mac.
   - **Lưu ý:** Nếu màn hình đang ở trang chủ Tizen Home hoặc đang mở một ứng dụng OTT (Netflix, YouTube), hộp thoại xin cấp quyền có thể bị ẩn ở chế độ nền.

---

## 2. Quy trình ghép nối kỹ thuật (Pairing Protocol)

Giao thức Samsung IP Control sử dụng chuẩn mã hóa TLS kết hợp JSON-RPC 2.0 trên cổng TCP 1516:

```
[Máy Mac (samsung_ipc.py)]                          [Màn hình Samsung S9 (Port 1516)]
            |                                                      |
            | ---------- 1. Kết nối TLS (Bỏ qua CA tự ký) -------->|
            |                                                      |
            | ---------- 2. JSON-RPC "createAccessToken" --------->|
            |    { "params": { "client": "macOS", ... } }          |
            |                                                      |
            |                                            [Hiển thị Popup]
            |                                      "Cho phép kết nối từ Mac?"
            |                                                      |
            |                                           (Người dùng bấm Allow)
            |                                                      |
            |<---------- 3. Phản hồi Token thành công -------------|
            |    { "result": { "token": "a1b2c3d4..." } }          |
            |                                                      |
   [Lưu vào Keychain & JSON]
```

### Các bước thực hiện:

1. Mở Terminal trên Mac, chạy lệnh:
   ```bash
   python3 "/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py" pair 192.168.x.x
   ```
2. Socket kết nối sẽ giữ trạng thái chờ (blocking) tối đa 65 giây.
3. Khi popup hiển thị trên màn hình S9, dùng remote bấm nút tròn giữa để chọn **Cho phép (Allow)**.
4. Lập tức Terminal sẽ in ra thông báo:
   ```
   [OK] Ghép nối thành công! Đã lưu AccessToken.
   ```

---

## 3. Cơ chế lưu trữ Token kép (Dual Storage Architecture)

Để đảm bảo vừa an toàn vừa tiện lợi cho nhiều công cụ khác nhau, dự án sử dụng chiến lược lưu trữ kép:

### A. File cấu hình cục bộ (`~/.samsung_monitor_control.json`)
- File được lưu tại thư mục gốc của người dùng: `~/.samsung_monitor_control.json`.
- Tự động gán quyền `0600` (`chmod 0600`), chỉ cho phép chính tài khoản người dùng hiện tại có quyền đọc/ghi.
- Định dạng lưu trữ:
  ```json
  {
    "host": "192.168.x.x",
    "token": "4a8f9c1b...",
    "cert_fingerprint": "e3b0c442..."
  }
  ```
- **Lợi ích:** Tránh tình trạng macOS liên tục bật hộp thoại xin cấp quyền truy cập Keychain khi BetterDisplay hoặc Menu Bar App gọi script Python dưới quyền tiến trình con (subprocess).

### B. Lưu vào macOS Keychain
- Đồng thời lưu một bản sao an toàn vào Keychain hệ thống:
  - **Service:** `samsung-ip-control`
  - **Account:** `samsung-s9`
- Có thể kiểm tra bằng lệnh:
  ```bash
  security find-generic-password -s "samsung-ip-control" -w
  ```

---

## 4. Xử lý lỗi ghép nối thường gặp

### Lỗi 1: `[Errno 65] No route to host`
- **Nguyên nhân:** Kể từ macOS 15 Sequoia, Apple siết chặt quyền truy cập mạng cục bộ (**Local Network Privacy**). Mọi tiến trình CLI hoặc ứng dụng cố gắng kết nối tới địa chỉ IP nội bộ (`192.168.x.x`) có thể bị tường lửa ngầm của macOS chặn.
- **Cách khắc phục:**
  1. Mở **System Settings (Cài đặt hệ thống)** $\rightarrow$ **Privacy & Security (Quyền riêng tư & Bảo mật)**.
  2. Chọn **Local Network (Mạng cục bộ)**.
  3. Tìm **Terminal** (hoặc ứng dụng Terminal bạn đang dùng như iTerm, Warp) và **Samsung Monitor Control**, gạt nút sang màu xanh (Bật).

### Lỗi 2: Lỗi `-32010: thông báo Allow trên màn hình bị từ chối hoặc hết giờ`
- **Nguyên nhân:** Quá 60 giây không bấm nút Allow trên remote, hoặc lỡ bấm nút Deny.
- **Cách khắc phục:** Chạy lại lệnh `pair`, hướng remote vào màn hình và sẵn sàng bấm Allow ngay khi popup vừa xuất hiện.

### Lỗi 3: Làm sao để hủy quyền kết nối hoặc ghép nối lại từ đầu?
- **Trên màn hình Samsung S9:**
  - Vào **Settings** $\rightarrow$ **Connection** $\rightarrow$ **External Device Manager (Trình quản lý thiết bị ngoài)**.
  - Chọn **Device Connect Manager (Trình quản lý kết nối thiết bị)** $\rightarrow$ **Device List (Danh sách thiết bị)**.
  - Tìm tên máy Mac của bạn và chọn **Xóa (Delete)**.
- **Trên máy Mac:**
  - Chạy lệnh `python3 samsung_ipc.py pair [IP]` hoặc bấm nút **Cấp quyền / Ghép nối lại** trên Menu Bar App để bắt đầu phiên ghép nối mới.
