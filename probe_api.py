#!/usr/bin/env python3
"""
Samsung ViewFinity S9 — API Probe / Reverse Engineering Scout
Thăm dò toàn bộ các method JSON-RPC 2.0 trên cổng 1516 để tìm tính năng ẩn.

Cách dùng:
    python3 probe_api.py              # Dùng host từ config sẵn
    python3 probe_api.py 192.168.x.x  # Chỉ định IP trực tiếp
"""
import json
import os
import socket
import ssl
import sys
import time

# Import helper functions từ samsung_ipc
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import samsung_ipc

PORT = samsung_ipc.PORT
TIMEOUT = 5

# Danh sách methods thăm dò
CONFIRMED_METHODS = [
    ("backlightControl", {}, "Đọc độ sáng đèn nền"),
    ("getDeviceInformation", {}, "Thông tin phần cứng"),
    ("getTVStates", {}, "Trạng thái tổng hợp"),
]

LIKELY_METHODS = [
    ("inputSourceControl", {}, "Đọc nguồn đầu vào hiện tại"),
    ("pictureModeControl", {}, "Đọc chế độ hình ảnh hiện tại"),
    ("powerControl", {}, "Đọc trạng thái nguồn"),
    ("muteControl", {}, "Đọc trạng thái tắt tiếng"),
    ("directVolumeControl", {}, "Đọc âm lượng hiện tại"),
    ("soundModeControl", {}, "Đọc chế độ âm thanh"),
    ("remoteKeyControl", {"key": "enter"}, "Mô phỏng phím remote"),
]

EXPLORATORY_METHODS = [
    # Game Mode / Latency
    ("gameModeControl", {}, "Game Mode control"),
    ("gameMode", {}, "Game Mode status"),
    ("setGameMode", {}, "Set Game Mode"),
    ("inputLagControl", {}, "Input lag control"),
    ("lowLatencyControl", {}, "Low latency control"),
    ("motionPlusControl", {}, "Motion Plus"),
    # Refresh rate & Sync
    ("refreshRateControl", {}, "Tần số quét"),
    ("vrrControl", {}, "VRR status"),
    ("freeSyncControl", {}, "FreeSync status"),
    ("adaptiveSyncControl", {}, "Adaptive Sync"),
    # Panel settings
    ("contrastControl", {}, "Contrast"),
    ("brightnessControl", {}, "Brightness"),
    ("sharpnessControl", {}, "Sharpness"),
    ("colorTempControl", {}, "Color temp"),
    ("colorToneControl", {}, "Color tone"),
    ("gammaControl", {}, "Gamma"),
    ("hdrControl", {}, "HDR"),
    ("hdrModeControl", {}, "HDR mode"),
    ("localDimmingControl", {}, "Local dimming"),
    ("eyeSaverModeControl", {}, "Eye Saver Mode"),
    ("eyeComfortControl", {}, "Eye Comfort"),
    ("pictureSizeControl", {}, "Picture size"),
    # System & Info
    ("getSystemInformation", {}, "Thông tin hệ thống"),
    ("getNetworkInformation", {}, "Thông tin mạng"),
    ("getVersion", {}, "Phiên bản firmware"),
    ("getFirmwareVersion", {}, "Firmware version"),
    ("getSoftwareVersion", {}, "Software version"),
    ("getModelName", {}, "Tên model"),
    ("getPanelInformation", {}, "Thông tin panel"),
    # Methods & discovery
    ("getSupportedMethods", {}, "Supported methods"),
    ("listMethods", {}, "List all methods"),
    ("system.listMethods", {}, "JSON-RPC standard list"),
    ("rpc.discover", {}, "JSON-RPC discovery"),
    ("sourceListControl", {}, "Danh sách nguồn"),
    ("getSourceList", {}, "Get source list"),
    ("getPictureMode", {}, "Get picture mode"),
    ("getInputSource", {}, "Get input source"),
    ("getPowerStatus", {}, "Get power status"),
    ("artModeControl", {}, "Art mode"),
]


def send_rpc_http(host, method, extra_params, token=None, timeout=TIMEOUT):
    """Gửi JSON-RPC 2.0 bọc trong HTTP POST qua TLS chuẩn Tizen."""
    body = {"jsonrpc": "2.0", "id": "1", "method": method}
    if token is not None:
        body["params"] = dict({"AccessToken": token}, **(extra_params or {}))
    elif extra_params:
        body["params"] = extra_params
    payload = json.dumps(body).encode()

    try:
        with samsung_ipc.connect(host, timeout) as tls:
            tls.sendall(
                b"POST / HTTP/1.1\r\nHost: %s:%d\r\nAccept: application/json\r\n"
                b"Content-Type: application/json\r\nContent-Length: %d\r\n\r\n"
                % (host.encode(), PORT, len(payload))
            )
            tls.sendall(payload)
            status, raw_body = samsung_ipc._read_http(tls)
    except socket.timeout:
        return {"_error": "Timeout"}
    except OSError as exc:
        return {"_error": str(exc)}
    except Exception as exc:
        return {"_error": str(exc)}

    try:
        return json.loads(raw_body.decode(errors="replace") or "{}")
    except ValueError:
        return {"_error": f"Phản hồi không phải JSON: {status}"}


def probe_one(host, token, method, params, desc):
    resp = send_rpc_http(host, method, params, token=token)

    if "_error" in resp:
        return "error", resp["_error"]
    if "error" in resp:
        err = resp["error"]
        code = err.get("code", 0)
        msg = err.get("message", "")
        if code == -32601:
            return "not_found", msg
        elif code == -32602:
            return "exists_need_params", f"code={code}: {msg}"
        elif code == -32700:
            return "auth_failed", f"code={code}: {msg}"
        else:
            return "other_error", f"code={code}: {msg}"
    if "result" in resp:
        return "success", resp["result"]
    return "unknown", resp


def main():
    cfg = samsung_ipc.load_config()
    host = sys.argv[1] if len(sys.argv) > 1 else cfg.get("host", "")
    token = cfg.get("token", "")

    if not host or not token:
        # Thử đọc từ credentials
        try:
            token, _ = samsung_ipc.credentials()
            host = cfg.get("host", host)
        except Exception as e:
            print(f"❌ Lỗi: {e}")
            sys.exit(1)

    print(f"🔍 Đang thăm dò API Samsung ViewFinity S9 (Cổng 1516)...")
    print(f"   IP: {host} | Token: {token[:6]}***")
    print("=" * 65)

    all_tests = (
        [("XÁC NHẬN", m) for m in CONFIRMED_METHODS] +
        [("RẤT CÓ THỂ", m) for m in LIKELY_METHODS] +
        [("KHÁM PHÁ", m) for m in EXPLORATORY_METHODS]
    )

    found = []
    need_params = []
    not_supported = []

    for group, (method, params, desc) in all_tests:
        status, data = probe_one(host, token, method, params, desc)

        if status == "success":
            d_str = json.dumps(data, ensure_ascii=False) if isinstance(data, (dict, list)) else str(data)
            if len(d_str) > 80:
                d_str = d_str[:80] + "..."
            print(f"  ✅ [{group}] {method:25s} -> {d_str}")
            found.append((method, desc, data))
        elif status == "exists_need_params":
            print(f"  🟡 [{group}] {method:25s} -> TỒN TẠI (cần tham số đúng): {data}")
            need_params.append((method, desc, data))
        elif status == "not_found":
            print(f"  ❌ {method:25s} -> Không hỗ trợ (-32601)")
            not_supported.append(method)
        else:
            print(f"  ⚠️  {method:25s} -> {status}: {data}")

        time.sleep(0.12)

    print("\n" + "=" * 65)
    print("📊 KẾT QUẢ THĂM DÒ:")
    print(f"  • Methods HOẠT ĐỘNG: {len(found)}")
    for m, d, res in found:
        print(f"    - {m}: {d} -> {res}")
    print(f"  • Methods TỒN TẠI nhưng cần tham số: {len(need_params)}")
    for m, d, res in need_params:
        print(f"    - {m}: {d}")
    print(f"  • Methods KHÔNG TỒN TẠI: {len(not_supported)}")

    # Ghi file kết quả
    out = {
        "host": host,
        "active_methods": [{"method": m, "desc": d, "result": r} for m, d, r in found],
        "parameter_required_methods": [{"method": m, "desc": d, "detail": r} for m, d, r in need_params],
        "unsupported_methods": not_supported,
    }
    with open("probe_results.json", "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    print(f"\n💾 Đã lưu kết quả chi tiết vào probe_results.json")


if __name__ == "__main__":
    main()
