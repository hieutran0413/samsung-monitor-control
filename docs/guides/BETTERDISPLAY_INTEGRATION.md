# Hướng dẫn Tích hợp Chi tiết với BetterDisplay

Tài liệu này hướng dẫn cách biến màn hình **Samsung ViewFinity S9 (5K)** thành trải nghiệm tương đương **Apple Studio Display** bằng cách kết nối **BetterDisplay** với script `samsung_ipc.py`.

---

## 🌟 Trải nghiệm đạt được sau khi tích hợp

- ⌨️ **Bàn phím Apple:** Bấm phím **F1 (Giảm độ sáng)** và **F2 (Tăng độ sáng)** trên bàn phím MacBook hoặc Magic Keyboard để tăng giảm đèn nền phần cứng thật.
- ☀️ **Native macOS OSD:** Hiển thị khung vuông biểu tượng mặt trời (OSD Bezel) của macOS mỗi khi bấm phím.
- 💡 **Ambient Light Sensor Sync:** Màn hình tự động tăng giảm độ sáng dựa vào cảm biến ánh sáng tích hợp trên notch MacBook (khi phòng tối thì màn hình S9 tự dịu lại, khi phòng sáng màn hình tự nâng sáng).
- 🔄 **Đồng bộ song song:** Độ sáng của màn hình MacBook và màn hình S9 di chuyển đồng đều nhau.

---

## 📋 Bảng tham số thiết lập trong BetterDisplay

Trong cửa sổ **Settings** của BetterDisplay, chọn màn hình **Samsung ViewFinity S9** $\rightarrow$ chọn thẻ **Control** $\rightarrow$ kích hoạt **Custom Control Integration / External CLI**:

| Tham số thiết lập | Giá trị cấu hình | Giải thích ý nghĩa |
| :--- | :--- | :--- |
| **Control method** | `External CLI / Script` | Cho phép BetterDisplay gọi script bên ngoài thay vì dùng DDC/CI |
| **Action** | `Run shell script` | Thực thi mã thông qua shell môi trường |
| **Shell** | `/bin/zsh` (hoặc `/bin/sh`) | Trình thông dịch shell mặc định trên macOS |
| **Shell script to set value** | `/usr/bin/python3 "/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py" set [*:VALUE:*]` | Lệnh truyền độ sáng mới vào Tizen |
| **Value format string** | `%.0f` | Làm tròn thành số nguyên (`0` đến `50`) |
| **Shell script to get current value** | `/usr/bin/python3 "/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py" get` | Lệnh đọc độ sáng hiện tại từ màn hình |
| **Value multiplier** | `50.0` | BetterDisplay quản lý dải `0.0 - 1.0`, nhân với 50 để ra dải `0 - 50` của S9 |
| **Minimum value** | `0.0` | Tương ứng với mức 0 của đèn nền |
| **Maximum value** | `1.0` | Tương ứng với mức 50 (100% công suất đèn nền) |
| **Min time between actions** | `0.2s` | Giới hạn tần suất gọi lệnh để tránh làm nghẽn socket của Tizen |

---

## 🛠️ Hướng dẫn từng bước cấu hình

### Bước 1: Ghép nối màn hình trước
Đảm bảo bạn đã ghép nối thành công và có file `~/.samsung_monitor_control.json` theo hướng dẫn tại [PAIRING_AND_TOKENS.md](PAIRING_AND_TOKENS.md).

Kiểm tra thử trong Terminal:
```bash
/usr/bin/python3 "/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py" get
```
Nếu màn hình trả về một con số (ví dụ `25`), nghĩa là cấu hình đã sẵn sàng.

---

### Bước 2: Thiết lập trong BetterDisplay

1. Nhấp vào biểu tượng BetterDisplay trên Menu Bar $\rightarrow$ chọn biểu tượng bánh răng **Settings**.
2. Ở danh sách màn hình bên cột trái, chọn **Samsung ViewFinity S9** (hoặc tên hiển thị tương ứng).
3. Chuyển sang thẻ **Control**.
4. Tìm đến mục **Custom Control Integration** hoặc **External CLI**.
5. Nhập chính xác đường dẫn script và các thông số từ bảng trên.
6. Bấm nút **Test / Apply**. Lúc này bạn thử kéo thanh trượt độ sáng trong BetterDisplay, đèn nền màn hình S9 sẽ lập tức thay đổi!

---

### Bước 3: Kích hoạt phím F1 / F2 trên bàn phím

1. Trong BetterDisplay Settings, chuyển sang tab **Keyboard** (Bàn phím).
2. Tích chọn:
   - ✅ **Use brightness keys to adjust brightness of the display with mouse cursor** (hoặc *Active display*).
   - ✅ **Show Apple-like native OSD for brightness changes** (Bật hiển thị thanh OSD mặt trời).
3. Bây giờ bạn có thể dùng trực tiếp phím **F1** và **F2** trên bàn phím Mac!

---

### Bước 4: Kích hoạt đồng bộ cảm biến ánh sáng (Ambient Light Sensor Sync)

Tính năng này giúp bạn không cần phải tự tay chỉnh độ sáng mỗi khi thời tiết hoặc ánh sáng phòng thay đổi:

1. Trong BetterDisplay Settings, chọn mục **Sync & Auto-brightness** (hoặc mục *Displays $\rightarrow$ Sync*).
2. Tích chọn **Synchronize brightness with built-in display** (Đồng bộ độ sáng với màn hình tích hợp MacBook).
3. Đảm bảo trên macOS bạn đã bật: **System Settings $\rightarrow$ Displays $\rightarrow$ Automatically adjust brightness** (Tự động điều chỉnh độ sáng).
4. Thử nghiệm: Dùng lòng bàn tay che cụm camera/cảm biến trên đỉnh màn hình MacBook, bạn sẽ thấy cả màn hình MacBook và màn hình Samsung ViewFinity S9 cùng tự động hạ sáng một cách êm ái!

---

## 💡 Mẹo tối ưu hóa hiệu năng

- **Tần suất gọi lệnh (Rate Limiting):** Tizen OS trên màn hình S9 có bộ vi xử lý riêng, việc nhận lệnh quá dày đặc (hơn 10 lệnh/giây) có thể làm socket bị reset. Việc đặt `Min time between actions = 0.2s` trong BetterDisplay là tối ưu nhất cho cả độ mượt và độ ổn định.
- **Tự động khôi phục:** Nếu màn hình bị rút nguồn hoặc router khởi động lại, script `samsung_ipc.py` có cơ chế tự kết nối lại và tự đọc lại token mà không cần bạn phải thao tác lại trên BetterDisplay.
