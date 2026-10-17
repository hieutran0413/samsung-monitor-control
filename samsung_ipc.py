#!/usr/bin/env python3
"""
Samsung ViewFinity S9 / Smart Monitor Hardware Control CLI.

Giao thức: HTTPS JSON-RPC 2.0 trên cổng TCP 1516 ("Samsung IP Control G2").
Xác thực: Ghép nối 1 lần qua `pair` (lưu an toàn vào ~/.samsung_monitor_control.json và Keychain).

Các lệnh hỗ trợ:
    python3 samsung_ipc.py pair [HOST]          # Ghép nối và lấy token
    python3 samsung_ipc.py get                  # Đọc độ sáng đèn nền thật (0-50)
    python3 samsung_ipc.py set <0-50>           # Đặt độ sáng đèn nền thật
    python3 samsung_ipc.py up [STEP]            # Tăng độ sáng (mặc định 5)
    python3 samsung_ipc.py down [STEP]          # Giảm độ sáng (mặc định 5)
    python3 samsung_ipc.py game-mode [on|off|auto]  # Đọc/bật/tắt Game Mode (Low Latency)
    python3 samsung_ipc.py sound-mode [MODE]    # Đọc/đổi chế độ âm thanh (Standard/Game/Music/Movie...)
    python3 samsung_ipc.py contrast [<0-50>]    # Đọc/đặt độ tương phản
    python3 samsung_ipc.py sharpness [<0-20>]   # Đọc/đặt độ sắc nét
    python3 samsung_ipc.py volume [<0-100>]     # Đọc/đặt âm lượng loa màn hình
    python3 samsung_ipc.py mute [on|off|toggle] # Đọc/bật/tắt mute
    python3 samsung_ipc.py power [on|off|reboot]# Bật/tắt nguồn/khởi động lại màn hình
    python3 samsung_ipc.py key <remoteKey>      # Gửi phím remote (cursorUp, enter, menu, return...)
    python3 samsung_ipc.py input [source]       # Đọc/chuyển nguồn vào (USB-C, HDMI...)
    python3 samsung_ipc.py status               # Đọc toàn bộ trạng thái màn hình (JSON)
    python3 samsung_ipc.py set-host <IP>        # Cập nhật địa chỉ IP màn hình
    python3 samsung_ipc.py info                 # Thông tin phần cứng màn hình
"""
import argparse
import hashlib
import hmac
import json
import os
import socket
import ssl
import subprocess
import sys

CONFIG_FILE      = os.path.expanduser("~/.samsung_monitor_control.json")
PORT             = 1516
KEYCHAIN_SERVICE = "samsung-ip-control"
BACKLIGHT_MIN    = 0
BACKLIGHT_MAX    = 50
DEFAULT_STEP     = 5
TIMEOUT          = 5
PAIR_TIMEOUT     = 65

AUTH_CODES = {
    -32700: "chưa ghép nối (not paired) hoặc token đã bị đổi",
    -32010: "thông báo Allow trên màn hình bị từ chối hoặc hết giờ",
    -32602: "tham số không hợp lệ",
    -32601: "chức năng không được hỗ trợ bởi firmware",
}


def load_config():
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_config(cfg):
    try:
        with open(CONFIG_FILE, "w") as f:
            json.dump(cfg, f, indent=2)
        os.chmod(CONFIG_FILE, 0o600)
    except Exception:
        pass


def get_current_host():
    cfg = load_config()
    if cfg.get("host"):
        return cfg["host"]
    return os.environ.get("SAMSUNG_IPC_HOST", "")


HOST = get_current_host()


class IPCError(Exception):
    pass


def keychain_get(account):
    cmd = ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None


def keychain_set(account, secret):
    cmd = 'add-generic-password -U -s "%s" -a "%s" -w "%s"\n' % (KEYCHAIN_SERVICE, account, secret)
    subprocess.run(["security", "-i"], input=cmd, capture_output=True, text=True)


def _read_http(sock):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    head, _, body = data.partition(b"\r\n\r\n")
    length = None
    for line in head.split(b"\r\n")[1:]:
        name, _, value = line.partition(b":")
        if name.strip().lower() == b"content-length":
            length = int(value.strip())
    while length is None or len(body) < length:
        chunk = sock.recv(4096)
        if not chunk:
            break
        body += chunk
    return head.split(b"\r\n")[0].decode(errors="replace"), body


def connect(host, timeout):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx.wrap_socket(socket.create_connection((host, PORT), timeout=timeout), server_hostname=host)


def rpc(method, params=None, token=None, pin=None, timeout=TIMEOUT, host=None):
    target_host = host or HOST
    if not target_host:
        raise IPCError("Chưa cấu hình địa chỉ IP màn hình; hãy chạy `python3 samsung_ipc.py pair <IP>`")

    body = {"jsonrpc": "2.0", "id": "1", "method": method}
    if token is not None:
        body["params"] = dict({"AccessToken": token}, **(params or {}))
    elif params:
        body["params"] = params
    payload = json.dumps(body).encode()

    try:
        with connect(target_host, timeout) as tls:
            fingerprint = hashlib.sha256(tls.getpeercert(binary_form=True)).hexdigest().upper()
            if pin is not None and not hmac.compare_digest(fingerprint, pin):
                raise IPCError("Chứng chỉ bảo mật màn hình đã đổi; vui lòng bấm Ghép nối lại")
            tls.sendall(
                b"POST / HTTP/1.1\r\nHost: %s:%d\r\nAccept: application/json\r\n"
                b"Content-Type: application/json\r\nContent-Length: %d\r\n\r\n"
                % (target_host.encode(), PORT, len(payload))
            )
            tls.sendall(payload)
            status, raw_body = _read_http(tls)
    except socket.timeout:
        raise IPCError("Màn hình không phản hồi (Timeout)")
    except OSError as exc:
        if exc.errno == 65:
            raise IPCError("Không tìm thấy IP %s (Màn hình ngủ, đổi IP hoặc mất Wi-Fi)" % target_host)
        raise IPCError("Không thể kết nối %s:%d (%s)" % (target_host, PORT, exc))
    except Exception as exc:
        raise IPCError("Lỗi kết nối: %s" % exc)

    try:
        reply = json.loads(raw_body.decode(errors="replace") or "{}")
    except ValueError:
        raise IPCError("Phản hồi không hợp lệ từ màn hình (%s)" % status)

    if "result" in reply:
        return reply["result"], fingerprint
    err = reply.get("error", reply)
    code = err.get("code")
    hint = AUTH_CODES.get(code)
    raise IPCError("%s thất bại: mã %s %s%s" % (
        method, code, err.get("message"),
        " - %s" % hint if hint else ""
    ))


def credentials():
    cfg = load_config()
    if cfg.get("token") and cfg.get("cert"):
        return cfg["token"], cfg["cert"]

    token = keychain_get(HOST + ":token")
    pin = keychain_get(HOST + ":cert")
    if token and pin:
        cfg["host"] = HOST
        cfg["token"] = token
        cfg["cert"] = pin
        save_config(cfg)
        return token, pin

    raise IPCError("Chưa ghép nối màn hình; hãy chạy `python3 samsung_ipc.py pair`")


def get_backlight():
    token, pin = credentials()
    result, _ = rpc("backlightControl", token=token, pin=pin)
    return int(result["backlight"])


def set_backlight(value):
    value = max(BACKLIGHT_MIN, min(BACKLIGHT_MAX, int(round(float(value)))))
    token, pin = credentials()
    rpc("backlightControl", {"backlight": value}, token=token, pin=pin)
    return value


def get_game_mode():
    token, pin = credentials()
    result, _ = rpc("gameModeControl", token=token, pin=pin)
    return result.get("gameMode", "Unknown")


def set_game_mode(mode):
    norm = mode.strip().lower()
    mapping = {"on": "On", "off": "Off", "auto": "Auto", "1": "On", "0": "Off", "true": "On", "false": "Off"}
    target = mapping.get(norm, mode.capitalize())
    token, pin = credentials()
    result, _ = rpc("gameModeControl", {"gameMode": target}, token=token, pin=pin)
    return result.get("gameMode", target)


def get_sound_mode():
    token, pin = credentials()
    result, _ = rpc("soundModeControl", token=token, pin=pin)
    return result.get("soundMode", "Unknown")


def set_sound_mode(mode):
    token, pin = credentials()
    result, _ = rpc("soundModeControl", {"soundMode": mode}, token=token, pin=pin)
    return result.get("soundMode", mode)


def get_contrast():
    token, pin = credentials()
    result, _ = rpc("contrastControl", token=token, pin=pin)
    return int(result["contrast"])


def set_contrast(value):
    val = max(0, min(50, int(round(float(value)))))
    token, pin = credentials()
    result, _ = rpc("contrastControl", {"contrast": val}, token=token, pin=pin)
    return int(result.get("contrast", val))


def get_sharpness():
    token, pin = credentials()
    result, _ = rpc("sharpnessControl", token=token, pin=pin)
    return int(result["sharpness"])


def set_sharpness(value):
    val = max(0, min(20, int(round(float(value)))))
    token, pin = credentials()
    result, _ = rpc("sharpnessControl", {"sharpness": val}, token=token, pin=pin)
    return int(result.get("sharpness", val))


def get_volume():
    token, pin = credentials()
    result, _ = rpc("directVolumeControl", token=token, pin=pin)
    return int(result.get("volume", 0))


def set_volume(value):
    val = max(0, min(100, int(round(float(value)))))
    token, pin = credentials()
    result, _ = rpc("directVolumeControl", {"volume": val}, token=token, pin=pin)
    return int(result.get("volume", val))


def get_mute():
    token, pin = credentials()
    result, _ = rpc("muteControl", token=token, pin=pin)
    return result.get("mute", "muteOff")


def set_mute(action):
    token, pin = credentials()
    if action == "toggle":
        cur = get_mute()
        target = "muteOff" if cur == "muteOn" else "muteOn"
    else:
        norm = action.strip().lower()
        target = "muteOn" if norm in ("on", "true", "1", "muteon") else "muteOff"
    result, _ = rpc("muteControl", {"mute": target}, token=token, pin=pin)
    return result.get("mute", target)


def control_power(action):
    norm = action.strip().lower()
    mapping = {
        "on": "powerOn", "poweron": "powerOn",
        "off": "powerOff", "poweroff": "powerOff",
        "reboot": "reboot"
    }
    target = mapping.get(norm, action)
    token, pin = credentials()
    result, _ = rpc("powerControl", {"power": target}, token=token, pin=pin)
    return result.get("power", target)


def send_remote_key(key):
    token, pin = credentials()
    result, _ = rpc("remoteKeyControl", {"remoteKey": key}, token=token, pin=pin)
    return result.get("remoteKey", key)


def get_input_source():
    token, pin = credentials()
    result, _ = rpc("inputSourceControl", token=token, pin=pin)
    return result.get("inputSource", "Unknown")


def set_input_source(source):
    token, pin = credentials()
    result, _ = rpc("inputSourceControl", {"inputSource": source}, token=token, pin=pin)
    return result.get("inputSource", source)


def trigger_dev_mode():
    import time
    token, pin = credentials()
    for num in [1, 2, 3, 4, 5]:
        rpc("remoteKeyControl", {"remoteKey": f"number{num}"}, token=token, pin=pin)
        time.sleep(0.2)
    return "Đã gửi chuỗi số 1-2-3-4-5 kích hoạt Developer Mode!"


def get_color():
    token, pin = credentials()
    result, _ = rpc("colorControl", token=token, pin=pin)
    return int(result.get("color", 27))


def set_color(value):
    val = max(0, min(50, int(round(float(value)))))
    token, pin = credentials()
    result, _ = rpc("colorControl", {"color": val}, token=token, pin=pin)
    return int(result.get("color", val))


def get_tint():
    token, pin = credentials()
    result, _ = rpc("tintControl", token=token, pin=pin)
    return int(result.get("tint", 0))


def set_tint(value):
    val = max(-15, min(15, int(round(float(value)))))
    token, pin = credentials()
    result, _ = rpc("tintControl", {"tint": val}, token=token, pin=pin)
    return int(result.get("tint", val))


def get_black_level():
    token, pin = credentials()
    result, _ = rpc("brightnessControl", token=token, pin=pin)
    return int(result.get("brightness", 0))


def set_black_level(value):
    val = max(-5, min(5, int(round(float(value)))))
    token, pin = credentials()
    result, _ = rpc("brightnessControl", {"brightness": val}, token=token, pin=pin)
    return int(result.get("brightness", val))


def get_auto_motion_plus():
    token, pin = credentials()
    result, _ = rpc("autoMotionPlusControl", token=token, pin=pin)
    return result.get("autoMotionPlus", "Off")


def set_auto_motion_plus(mode):
    norm = mode.strip().lower()
    mapping = {"on": "On", "off": "Off", "auto": "Auto"}
    target = mapping.get(norm, mode.capitalize())
    token, pin = credentials()
    result, _ = rpc("autoMotionPlusControl", {"autoMotionPlus": target}, token=token, pin=pin)
    return result.get("autoMotionPlus", target)


def get_speaker_select():
    token, pin = credentials()
    result, _ = rpc("speakerSelectControl", token=token, pin=pin)
    return result.get("speakerSelect", "Internal")


def set_speaker_select(target):
    token, pin = credentials()
    result, _ = rpc("speakerSelectControl", {"speakerSelect": target}, token=token, pin=pin)
    return result.get("speakerSelect", target)


def get_peripherals():
    try:
        out = subprocess.check_output(
            ["ioreg", "-p", "IOUSB", "-l", "-w0"],
            stderr=subprocess.DEVNULL
        ).decode(errors="ignore")
        items = out.split("+-o ")
        devices = []
        for item in items[1:]:
            import re
            name_m = re.match(r"([^<]+)", item)
            name = name_m.group(1).strip() if name_m else "Thiết bị USB"
            prod_m = re.search(r'"USB Product Name" = "([^"]+)"', item)
            vendor_m = re.search(r'"USB Vendor Name" = "([^"]+)"', item)
            prod_name = prod_m.group(1) if prod_m else name
            vendor_name = vendor_m.group(1) if vendor_m else ""
            if "Root Hub" not in prod_name and "AppleT6000" not in prod_name:
                devices.append({
                    "name": prod_name,
                    "vendor": vendor_name
                })
        return devices
    except Exception:
        return []


def get_full_status():
    token, pin = credentials()
    states, _ = rpc("getTVStates", token=token, pin=pin)
    backlight = get_backlight()
    game_mode = get_game_mode()
    contrast = get_contrast()
    sharpness = get_sharpness()
    color = get_color()
    tint = get_tint()
    black_level = get_black_level()
    speaker_sel = get_speaker_select()
    peripherals = get_peripherals()

    return {
        "host": HOST,
        "backlight": backlight,
        "contrast": contrast,
        "sharpness": sharpness,
        "color": color,
        "tint": tint,
        "blackLevel": black_level,
        "gameMode": game_mode,
        "soundMode": states.get("soundMode", "Unknown"),
        "volume": states.get("volume", 0),
        "mute": states.get("mute", "muteOff"),
        "speakerSelect": speaker_sel,
        "inputSource": states.get("inputSource", "Unknown"),
        "pictureMode": states.get("pictureMode", "Unknown"),
        "pictureSize": states.get("pictureSize", "Unknown"),
        "peripherals": peripherals,
    }


def pair(target_host=None):
    global HOST
    if target_host:
        HOST = target_host

    try:
        with connect(HOST, TIMEOUT) as tls:
            fingerprint = hashlib.sha256(tls.getpeercert(binary_form=True)).hexdigest().upper()
    except OSError as exc:
        if exc.errno == 65:
            raise IPCError("Không tìm thấy IP %s (Màn hình ngủ hoặc sai IP)" % HOST)
        raise IPCError("Không thể kết nối tới %s:%d (%s)" % (HOST, PORT, exc))
    except Exception as exc:
        raise IPCError("Lỗi kết nối: %s" % exc)

    print(">> Đang gửi yêu cầu... Bấm [Cho phép / Allow] trên màn hình S9...", file=sys.stderr)
    result, seen = rpc("createAccessToken", timeout=PAIR_TIMEOUT, host=HOST)
    token = result.get("AccessToken") if isinstance(result, dict) else None
    if not token:
        raise IPCError("Không nhận được token; hãy chắc chắn màn hình đang ở ngõ vào Type-C/Mac (không ở màn hình Home của Tizen)")

    cfg = load_config()
    cfg["host"] = HOST
    cfg["token"] = token
    cfg["cert"] = fingerprint
    save_config(cfg)

    keychain_set(HOST + ":cert", fingerprint)
    keychain_set(HOST + ":token", token)
    print(">> Ghép nối thành công! Đã lưu cấu hình an toàn.")


def main():
    global HOST
    ap = argparse.ArgumentParser(description="Samsung ViewFinity S9 IP Control - Hardware Control")
    sub = ap.add_subparsers(dest="cmd", required=True)

    # 1. Ghép nối & kết nối
    p_pair = sub.add_parser("pair", help="Ghép nối với màn hình")
    p_pair.add_argument("host", nargs="?", default=None, help="IP của màn hình")

    p_host = sub.add_parser("set-host", help="Cập nhật IP màn hình")
    p_host.add_argument("host", help="Địa chỉ IP mới")

    # 2. Độ sáng đèn nền (Backlight)
    sub.add_parser("get", help="Đọc độ sáng đèn nền thật (0-50)")

    p_set = sub.add_parser("set", help="Đặt độ sáng đèn nền thật (0-50)")
    p_set.add_argument("value", help="Giá trị độ sáng 0-50")

    for name in ("up", "down"):
        sub.add_parser(name, help="Tăng/giảm độ sáng").add_argument("step", nargs="?", type=int, default=DEFAULT_STEP)

    # 3. Game Mode (Low Latency)
    p_gm = sub.add_parser("game-mode", help="Đọc hoặc đặt Game Mode")
    p_gm.add_argument("mode", nargs="?", choices=["on", "off", "auto", "On", "Off", "Auto"], help="Chế độ Game Mode")

    # 4. Sound Mode
    p_sm = sub.add_parser("sound-mode", help="Đọc hoặc đặt chế độ âm thanh")
    p_sm.add_argument("mode", nargs="?", help="Chế độ âm thanh (Standard, Game, Music, Movie, Amplify, Adaptive, Optimized)")

    # 5. Hình ảnh: Contrast, Sharpness, Color, Tint, Black Level
    p_contrast = sub.add_parser("contrast", help="Đọc hoặc đặt độ tương phản (0-50)")
    p_contrast.add_argument("value", nargs="?", type=int, help="Độ tương phản 0-50")

    p_sharp = sub.add_parser("sharpness", help="Đọc hoặc đặt độ sắc nét (0-20)")
    p_sharp.add_argument("value", nargs="?", type=int, help="Độ sắc nét 0-20")

    p_color = sub.add_parser("color", help="Đọc hoặc đặt độ đậm màu / bão hòa (0-50)")
    p_color.add_argument("value", nargs="?", type=int, help="Độ đậm màu 0-50 (chuẩn: 27)")

    p_tint = sub.add_parser("tint", help="Đọc hoặc đặt sắc thái màu (-15..15)")
    p_tint.add_argument("value", nargs="?", type=int, help="Sắc thái màu -15 đến 15 (chuẩn: 0)")

    p_bl = sub.add_parser("black-level", help="Đọc hoặc đặt mức sáng điểm đen (-5..5)")
    p_bl.add_argument("value", nargs="?", type=int, help="Mức điểm đen -5 đến 5 (chuẩn: 0)")

    p_mp = sub.add_parser("motion-plus", help="Đọc hoặc bật/tắt Auto Motion Plus")
    p_mp.add_argument("mode", nargs="?", choices=["on", "off", "auto"], help="Chế độ Motion Plus")

    # 6. Âm thanh: Volume, Mute & Speaker Output
    p_vol = sub.add_parser("volume", help="Đọc hoặc đặt âm lượng (0-100)")
    p_vol.add_argument("value", nargs="?", type=int, help="Mức âm lượng 0-100")

    p_mute = sub.add_parser("mute", help="Đọc hoặc đặt tắt tiếng")
    p_mute.add_argument("action", nargs="?", choices=["on", "off", "toggle"], help="Trạng thái mute")

    p_spk = sub.add_parser("speaker", help="Đọc hoặc chọn đầu ra âm thanh")
    p_spk.add_argument("target", nargs="?", choices=["Internal", "Receiver", "internal", "receiver"], help="Internal hoặc Receiver")

    # 7. Nguồn, Thiết bị ngoại vi & Phím remote
    p_power = sub.add_parser("power", help="Điều khiển nguồn màn hình")
    p_power.add_argument("action", nargs="?", choices=["on", "off", "reboot"], default="on", help="powerOn, powerOff, reboot")

    p_key = sub.add_parser("key", help="Gửi phím điều khiển từ xa")
    p_key.add_argument("name", help="Tên phím (cursorUp, cursorDn, cursorLeft, cursorRight, enter, menu, return, firstScreen)")

    p_input = sub.add_parser("input", help="Đọc hoặc chuyển nguồn vào")
    p_input.add_argument("source", nargs="?", help="Tên nguồn (USB-C, HDMI1, HDMI2...)")

    sub.add_parser("peripherals", help="Liệt kê thiết bị ngoại vi đang cắm qua USB Hub của màn hình")

    sub.add_parser("dev-mode", help="Gửi chuỗi phím 1-2-3-4-5 để mở popup Developer Mode")

    # 8. Trạng thái & thông tin
    sub.add_parser("status", help="Đọc toàn bộ trạng thái màn hình (JSON)")
    sub.add_parser("info", help="Thông tin phần cứng màn hình")

    args = ap.parse_args()

    try:
        if args.cmd == "pair":
            pair(args.host)
        elif args.cmd == "set-host":
            cfg = load_config()
            cfg["host"] = args.host
            save_config(cfg)
            print("Đã lưu IP: %s" % args.host)
        elif args.cmd == "get":
            print(get_backlight())
        elif args.cmd == "set":
            print(set_backlight(args.value))
        elif args.cmd in ("up", "down"):
            step = args.step if args.cmd == "up" else -args.step
            print(set_backlight(get_backlight() + step))
        elif args.cmd == "game-mode":
            if args.mode:
                print(set_game_mode(args.mode))
            else:
                print(get_game_mode())
        elif args.cmd == "sound-mode":
            if args.mode:
                print(set_sound_mode(args.mode))
            else:
                print(get_sound_mode())
        elif args.cmd == "contrast":
            if args.value is not None:
                print(set_contrast(args.value))
            else:
                print(get_contrast())
        elif args.cmd == "sharpness":
            if args.value is not None:
                print(set_sharpness(args.value))
            else:
                print(get_sharpness())
        elif args.cmd == "color":
            if args.value is not None:
                print(set_color(args.value))
            else:
                print(get_color())
        elif args.cmd == "tint":
            if args.value is not None:
                print(set_tint(args.value))
            else:
                print(get_tint())
        elif args.cmd == "black-level":
            if args.value is not None:
                print(set_black_level(args.value))
            else:
                print(get_black_level())
        elif args.cmd == "motion-plus":
            if args.mode:
                print(set_auto_motion_plus(args.mode))
            else:
                print(get_auto_motion_plus())
        elif args.cmd == "speaker":
            if args.target:
                target = "Receiver" if args.target.lower() == "receiver" else "Internal"
                print(set_speaker_select(target))
            else:
                print(get_speaker_select())
        elif args.cmd == "peripherals":
            print(json.dumps(get_peripherals(), indent=2, ensure_ascii=False))
        elif args.cmd == "volume":
            if args.value is not None:
                print(set_volume(args.value))
            else:
                print(get_volume())
        elif args.cmd == "mute":
            if args.action:
                print(set_mute(args.action))
            else:
                print(get_mute())
        elif args.cmd == "power":
            print(control_power(args.action))
        elif args.cmd == "key":
            print(send_remote_key(args.name))
        elif args.cmd == "input":
            if args.source:
                print(set_input_source(args.source))
            else:
                print(get_input_source())
        elif args.cmd == "dev-mode":
            print(trigger_dev_mode())
        elif args.cmd == "status":
            print(json.dumps(get_full_status(), indent=2, ensure_ascii=False))
        elif args.cmd == "info":
            token, pin = credentials()
            result, _ = rpc("getDeviceInformation", token=token, pin=pin)
            print(json.dumps(result, indent=2))
    except IPCError as exc:
        sys.exit("Lỗi: %s" % exc)


if __name__ == "__main__":
    main()
