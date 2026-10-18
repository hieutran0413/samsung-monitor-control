# Implementation Status Tracker

> Bảng theo dõi tiến độ và trạng thái các tính năng của dự án **Samsung Monitor Control**.  
> Cập nhật lần cuối: **2026-10-18**.

## Trạng thái điều phối hiện hành — design trước coding

**Private glass được người dùng cho phép thử:** app đã chuyển widget sang `_Glass.controlCenter` qua bridge giới hạn đúng build `26B5112a`, có public-regular fallback và opt-out. Probe ABI/regular equivalence và ảnh overview installed-app xác nhận material mới; private-material submenu/morph chưa được QC thành công. Text/icon dùng white + Plus Lighter theo yêu cầu tiếp theo. Slider chưa chuyển sang private slider recipe. [Chi tiết và giới hạn](../audits/2026-10-18-native-ui/CONTROL_CENTER_GLASS_TRACE.md).

**Control Center trace:** binary Apple trên macOS 27.2 import private `_Glass.controlCenter` và `_Glass.slider` qua `_glassEffect`. Public `.regular` của app không được coi là cùng recipe. [Bằng chứng static trace](../audits/2026-10-18-native-ui/CONTROL_CENTER_GLASS_TRACE.md); per-widget/runtime mapping chưa xác định. Lượt sửa reconnect/keys/Back không đổi glass.

**Sửa reconnect / phím / Back hiện hành:** đã xác định LG mất UUID khi disable; reconnect dùng identity phần cứng duy nhất và xác nhận active trước khi xóa trạng thái. Hardware reconnect và fresh-controller startup recovery đều pass trên LG. Đã thêm đăng ký login item, ký Apple Development ổn định, lưu ý định bật phím và chờ quyền không hỏi lặp; Back có vùng bấm 44×44 pt. Reboot thật, phím vật lý và click Back qua Computer Use vẫn chưa nghiệm thu. Xem [bằng chứng và giới hạn](../audits/2026-10-18-native-ui/RECONNECT_KEYS_BACK.md). Phần cập nhật này ưu tiên hơn các ghi chú prototype cũ phía dưới.

**Khôi phục sau regression:** `.clear` nguyên bản không đủ tương phản trên nền trắng, người dùng báo UI hỏng. Đã trở về `.regular` + Dark Aqua để phục hồi nội dung đọc được. Không coi bản clear là hoàn thành; visual 1:1 vẫn mở.

**Thử nghiệm mới nhất — “glass small”:** `Glass` không có small; nền widget đổi sang `.clear` nguyên bản, không dim/tint/shadow tùy chỉnh, vì regular dark quá đục theo ảnh người dùng. Chưa visual accepted. Thumb/slider giữ hiệu chỉnh riêng.

**Appearance mới nhất:** theo yêu cầu “glass medium”, đã đổi từ clear + dim/shadow tùy biến sang `Glass.regular` hệ thống, không tint/dim/shadow View tự vẽ; giữ Dark Aqua, slider trắng và padding shadow 24pt. Không có API `Glass.medium`. Visual acceptance vẫn mở; xem [Product Design](../design/PRODUCT_DESIGN.md).

**Thumb kéo mới nhất:** tách Aqua appearance của regular glass thumb khỏi Dark Aqua widget để sửa cục đen khi dragging; tăng vùng slider lên 24pt cho thumb cao 20pt. Chưa báo dragging visual acceptance nếu chưa có ảnh/video lúc giữ kéo.

**Cập nhật mới nhất:** người dùng đã yêu cầu tiếp tục. UI đang `in-progress`, không còn dừng coding. Đã build/cài flow overview sync → Display/Audio detail; QC bằng Computer Use xác nhận Audio detail có Samsung và LG. Widget chuyển sang clear Liquid Glass với dim dưới kính, Dark Aqua, slider idle/drag riêng và margin shadow 24pt. Chưa visual accepted: lượt QC menu con cuối timeout; morph video, key event và reconnect thật còn mở. Chi tiết hiện hành ở phần cập nhật đầu [Product Design](../design/PRODUCT_DESIGN.md).

Người dùng yêu cầu dừng coding để tổng hợp Product Design trước. [PRODUCT_DESIGN.md](../design/PRODUCT_DESIGN.md) là đặc tả hiện hành, trạng thái **draft/chờ review**, chưa accepted hoặc code-ready. Các hàng “Hoàn thành” phía dưới mô tả nền tảng/lịch sử, không chứng minh UI mới hay toàn bộ scope đã được nghiệm thu. Không commit/push/release theo các đề xuất cũ phía cuối.

| Hạng mục hiện hành | Trạng thái | Bằng chứng có | Còn lại / bước tiếp theo | Nguồn | Ngày |
| --- | --- | --- | --- | --- | --- |
| Product design essential | Draft, chờ review | IA, screen/flow, state, sync, DDC capability, keys theo con trỏ, motion và acceptance đã tổng hợp | Review bố cục overview, brightness sync và reconnect recovery trước khi coding lại | [Product Design](../design/PRODUCT_DESIGN.md) | 2026-10-18 |
| UI Control Center / morph | Prototype exists; chưa visual acceptance | Nhiều vòng build/render; menu bar BetterDisplay đã đọc/chụp qua Computer Use | Bỏ double border, kiểm chứng morph giữa menu, overview → audio detail và accessibility; không claim 1:1 | [Audit](../audits/2026-10-18-native-ui/AUDIT.md) | 2026-10-18 |
| DDC LG brightness / volume | Prototype; brightness có hardware read/write | LG brightness 100→99→100 đúng readback; volume đọc 99/max100 | Test volume write, partial errors và latest volume sync; không chỉnh màu DDC | [Product Design §6/13/14](../design/PRODUCT_DESIGN.md) | 2026-10-18 |
| Audio sync ngoài / riêng trong | Source prototype; chỉ typecheck mới nhất | UI/action sync mới thêm trước yêu cầu dừng; chưa build/cài bản này | Theo contract trong Product Design, QC với Samsung/LG và lỗi một phần | [main.swift](../../main.swift) | 2026-10-18 |
| DDC reconnect / startup recovery | Hardware reconnect và fresh-controller recovery pass; reboot gate mở | UUID-loss được xác định; identity fallback duy nhất; xác nhận active; startup retry; login-item registration | Login/reboot thật, approval login item nếu macOS yêu cầu, thiết bị trùng serial | [Bằng chứng](../audits/2026-10-18-native-ui/RECONNECT_KEYS_BACK.md) | 2026-10-18 |
| Keys theo con trỏ / AX | Đã sửa source và signing; physical-key gate mở | Apple Development signing; intent riêng readiness; prompt một lần, tự retry silent | Xác nhận AX/tap của bản signed và phím thật/repeat/modifier | [Bằng chứng](../audits/2026-10-18-native-ui/RECONNECT_KEYS_BACK.md) | 2026-10-18 |
| Back menu con | Implemented, build pass | Hit target 44×44 pt, contentShape và accessibility label | Pointer click thực tế; Computer Use đang timeout app | [main.swift](../../main.swift) | 2026-10-18 |
| Remote memory / Samsung sharpness | Prototype + Python regression cho sharpness | Remote preference có lưu; sharpness mock tests pass | Kiểm tra remote giữ lựa chọn và không bắt phím khi panel đóng; sharpness chỉ Samsung | [Product Design §8](../design/PRODUCT_DESIGN.md) | 2026-10-18 |

---

## 📊 Bảng tổng hợp trạng thái tính năng (Feature Status Matrix)

| Tính năng / Hạng mục | Trạng thái | Đã hoàn thành (What Works) | Còn lại (What Remains) | Hành động tiếp theo | Tài liệu & Mã nguồn liên quan | Ngày kiểm tra |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Python Core CLI (`samsung_ipc.py`)** | `Hoàn thành` | • Giao thức HTTPS JSON-RPC 2.0 cổng 1516<br>• Lệnh `pair` bắt tay lấy Token<br>• Lệnh `get`, `set <0-50>`, `up`, `down`<br>• Cơ chế lưu trữ kép Keychain + JSON 0600<br>• Xử lý timeout và mã lỗi Tizen | Tự động dò tìm IP màn hình qua mDNS / SSDP (tùy chọn) | Khởi tạo repo và push lên Git | [samsung_ipc.py](file:///Volumes/My%20Data/Development/samsung-monitor-control/samsung_ipc.py)<br>[PAIRING_AND_TOKENS.md](file:///Volumes/My%20Data/Development/samsung-monitor-control/docs/guides/PAIRING_AND_TOKENS.md) | 2026-10-17 |
| **Standalone macOS App (`main.swift`)** | `Đã build; chờ nghiệm thu UI/phần cứng` | Overview Control Center 420×610: tile Tắt màn hình lớn, menu màu, Khôi phục độ nét, module slider Màn hình/Âm thanh và lối vào cài đặt sâu; Button/Menu/Picker/Slider/Toggle native; tắt nguồn gửi CLI `off`; shortcut remote có opt-in, chỉ local; đủ Game Mode Auto; ghép nối không ghi IP sớm; sửa đảo sRGB/P3 theo OSD người dùng và readback picture mode | Runtime visual ở light/dark wallpaper, VoiceOver/focus, power vật lý; readback slider và firmware capabilities chưa xác nhận | Mở app đã cài, kiểm tra overview và checklist Control Center trong audit | [Audit và evidence](../audits/2026-10-18-native-ui/AUDIT.md), [Hướng dẫn](../guides/STANDALONE_MAC_APP.md), [main.swift](../../main.swift), [Power regression](../../tests/test_power_contract.py) | 2026-10-18 |
| **Khôi phục độ nét một nút** | `Đã build; chờ phần cứng` | Native Button dưới slider; chụp target 0–20; lệch 1 mức rồi trả lại sau 150ms; luôn thử restore khi bước đầu lỗi; readback; khóa bấm lặp/slider | Xác nhận lỗi quá nét sau tắt/bật hết trên panel; không tự động wake hoặc lưu mốc riêng | Sau bật lại, bấm Khôi phục độ nét và đối chiếu hình ảnh | [Hướng dẫn](../guides/STANDALONE_MAC_APP.md), [Regression tests](../../tests/test_refresh_sharpness.py) | 2026-10-18 |
| **Tự động đóng gói & Cài đặt (`build.sh`)** | `Hoàn thành` | • Biên dịch Swift tối ưu hóa (`-O`)<br>• Đóng gói cấu trúc `.app` chuẩn macOS<br>• Nhúng script Python vào Bundle Resources<br>• Cấu hình `NSLocalNetworkUsageDescription`<br>• Ký số ad-hoc chống chặn mạng Sequoia<br>• Cài đặt tự động vào `/Applications/` | Tích hợp Apple Developer ID Certificate (nếu phân phối công khai) | Cấp quyền `chmod +x build.sh` | [build.sh](file:///Volumes/My%20Data/Development/samsung-monitor-control/build.sh) | 2026-10-17 |
| **Tích hợp BetterDisplay** | `Hoàn thành` | • Điều khiển đèn nền phần cứng qua phím F1/F2<br>• Hiển thị Apple Native Sun OSD<br>• Đồng bộ cảm biến ánh sáng MacBook (Ambient Light Sensor Sync)<br>• Rate-limit 0.2s chống nghẽn Tizen | Xuất file BetterDisplay Display Profile (.json) sẵn để import 1 chạm | Đã có tài liệu bảng thông số chi tiết | [BETTERDISPLAY_INTEGRATION.md](file:///Volumes/My%20Data/Development/samsung-monitor-control/docs/guides/BETTERDISPLAY_INTEGRATION.md) | 2026-10-17 |
| **Bộ Tài liệu Hướng dẫn (Docs Suite)** | `Hoàn thành` | • `README.md` toàn diện<br>• Hướng dẫn Pairing & Token<br>• Hướng dẫn cấu hình BetterDisplay<br>• Hướng dẫn Standalone Menu Bar App<br>• Đặc tả Kiến trúc & Giao thức Cổng 1516<br>• Project Brief chuẩn hóa | Đính kèm ảnh chụp màn hình UI BetterDisplay | Hoàn tất | [README.md](file:///Volumes/My%20Data/Development/samsung-monitor-control/README.md)<br>[SYSTEM_ARCHITECTURE.md](file:///Volumes/My%20Data/Development/samsung-monitor-control/docs/architecture/SYSTEM_ARCHITECTURE.md) | 2026-10-17 |

---

## 📌 Các bước tiếp theo được đề xuất (Recommended Next Steps)

1. **Khởi tạo Git Repository và Commit:**
   Thực thi lệnh `git init`, thêm các file và commit phiên bản đầu tiên `v1.0.0`.
2. **Push lên GitHub/GitLab:**
   Tạo repository mới trên GitHub (ví dụ: `samsung-viewfinity-s9-mac-control`) và thực hiện `git push -u origin main`.
3. **Phân phối:**
   Cung cấp file cài đặt hoặc hướng dẫn người dùng khác cùng sở hữu Samsung ViewFinity S9 dễ dàng sử dụng.
