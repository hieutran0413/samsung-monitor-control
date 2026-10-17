#!/usr/bin/env python3
"""
Deep Scanner & Service Discovery for Samsung ViewFinity S9.
1. Quét toàn bộ cổng mạng đang mở trên màn hình.
2. Đọc UPnP/SSDP Device Description XML để lấy toàn bộ sơ đồ dịch vụ và endpoint.
3. Thăm dò chi tiết phản hồi của getTVStates và getDeviceInformation.
4. Thử nghiệm các bộ tham số cho gameModeControl, inputSourceControl, remoteKeyControl.
"""
import json
import os
import socket
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import samsung_ipc

cfg = samsung_ipc.load_config()
HOST = cfg.get("host", "")
TOKEN = cfg.get("token", "")

if not HOST or not TOKEN:
    token, _ = samsung_ipc.credentials()
    TOKEN = token
    HOST = cfg.get("host", HOST)

print(f"🎯 Mục tiêu: {HOST}")
print("=" * 60)

# ============================================================
# 1. QUÉT CÁC CỔNG MẠNG THÔNG DỤNG TRÊN TIZEN
# ============================================================
COMMON_PORTS = [
    (80, "HTTP Web"),
    (443, "HTTPS Web"),
    (1515, "Samsung IP Control G1"),
    (1516, "Samsung IP Control G2 (Hiện tại)"),
    (7676, "Samsung UPnP / Smart Device Server"),
    (8000, "HTTP Alt / Media"),
    (8001, "Tizen WebSocket WS (Legacy)"),
    (8002, "Tizen WebSocket WSS (Smart Remote)"),
    (8080, "HTTP Proxy / Alt"),
    (8181, "Tizen REST API"),
    (8443, "HTTPS Alt"),
    (9197, "Samsung DMR / MultiScreen Dial"),
    (26101, "Tizen SDB Debugger"),
]

print("\n📡 1. QUÉT CỔNG MẠNG ĐANG MỞ...")
open_ports = []
for port, name in COMMON_PORTS:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(1.0)
    res = s.connect_ex((HOST, port))
    s.close()
    if res == 0:
        print(f"  🟢 Cổng {port:5d} [MỞ] - {name}")
        open_ports.append(port)
    else:
        print(f"  ⚪ Cổng {port:5d} [Đóng]")

# ============================================================
# 2. KHAI THÁC UPNP / DIAL / REST SERVICES
# ============================================================
print("\n🔍 2. KHAI THÁC MÔ TẢ DỊCH VỤ UPNP / DIAL...")
upnp_urls = [
    f"http://{HOST}:7676/smp_2_",
    f"http://{HOST}:7676/smp_4_",
    f"http://{HOST}:9197/dmr/",
    f"http://{HOST}:9197/upnp/common/service/MainTVServer2",
    f"http://{HOST}:8001/api/v2/",
    f"http://{HOST}:8001/api/v2/applications",
]

for url in upnp_urls:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Samsung-Monitor-Probe/1.0"})
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            content = resp.read().decode(errors="replace")
            print(f"\n  📄 URL: {url} (HTTP {resp.status})")
            print("  --- Trích đoạn dữ liệu (200 ký tự đầu) ---")
            print("  " + content[:200].replace("\n", " "))
    except Exception as e:
        pass

# ============================================================
# 3. TRÍCH XUẤT TOÀN BỘ CẤU TRÚC JSON getTVStates & getDeviceInformation
# ============================================================
print("\n📊 3. DỮ LIỆU ĐẦY ĐỦ TỪ CỔNG 1516:")

def call_rpc(method, extra_params=None):
    body = {"jsonrpc": "2.0", "id": "1", "method": method}
    params = {"AccessToken": TOKEN}
    if extra_params:
        params.update(extra_params)
    body["params"] = params
    payload = json.dumps(body).encode()

    with samsung_ipc.connect(HOST, 5) as tls:
        tls.sendall(
            b"POST / HTTP/1.1\r\nHost: %s:%d\r\nAccept: application/json\r\n"
            b"Content-Type: application/json\r\nContent-Length: %d\r\n\r\n"
            % (HOST.encode(), samsung_ipc.PORT, len(payload))
        )
        tls.sendall(payload)
        _, raw = samsung_ipc._read_http(tls)
        return json.loads(raw.decode(errors="replace"))

dev_info = call_rpc("getDeviceInformation")
print("\n[getDeviceInformation]:")
print(json.dumps(dev_info, indent=2, ensure_ascii=False))

tv_states = call_rpc("getTVStates")
print("\n[getTVStates]:")
print(json.dumps(tv_states, indent=2, ensure_ascii=False))

# ============================================================
# 4. THĂM DÒ THAM SỐ CỦA gameModeControl, inputSourceControl, remoteKeyControl
# ============================================================
print("\n🧪 4. THỬ NGHIỆM THAM SỐ API CHI TIẾT:")

# Thử gameModeControl với các kiểu giá trị
print("\n- Thử gameModeControl...")
for val in ["On", "Off", "Auto", 1, 0, True, False]:
    r = call_rpc("gameModeControl", {"gameMode": val})
    print(f"  • gameMode = {val!r} -> {r}")

# Thử inputSourceControl
print("\n- Thử đọc danh sách inputSourceControl...")
for val in ["USB-C", "HDMI", "HDMI1", "HDMI2", "DisplayPort", "Mini-DP", "DP"]:
    # Chỉ đọc trạng thái hoặc thử tham số
    pass

# Thử remoteKeyControl
print("\n- Thử remoteKeyControl...")
for key_name in ["KEY_MENU", "KEY_HOME", "KEY_SOURCE", "KEY_ENTER", "menu", "home", "enter"]:
    r = call_rpc("remoteKeyControl", {"key": key_name})
    if "result" in r:
        print(f"  🟢 Phím {key_name!r} ĐƯỢC CHẤP NHẬN -> {r['result']}")
        break
    else:
        err = r.get("error", {})
        print(f"  ⚪ Phím {key_name!r} -> {err.get('code')}: {err.get('message')}")

print("\n" + "=" * 60)
print("Hoàn tất quét sâu!")
