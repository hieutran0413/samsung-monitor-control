#!/usr/bin/python3
"""
Samsung IP Control -> Điều khiển độ sáng đèn nền thật (Hardware Backlight) cho Samsung ViewFinity S9 / Smart Monitor.

Giao thức: HTTPS JSON-RPC 2.0 trên cổng TCP 1516 ("Samsung IP Control G2").
Xác thực: Ghép nối 1 lần qua phương thức `createAccessToken` (màn hình hiện popup Allow).
Lưu trữ: Tự động lưu Token và mã vân tay chứng chỉ vào ~/.samsung_monitor_control.json và macOS Keychain.

Cách dùng:
    python3 samsung_ipc.py pair [HOST]     # Bắt tay ghép nối màn hình
    python3 samsung_ipc.py get             # Đọc độ sáng hiện tại (0 - 50)
    python3 samsung_ipc.py set <0-50>      # Đặt độ sáng đèn nền thật
    python3 samsung_ipc.py up [STEP]       # Tăng độ sáng (mặc định bước 5)
    python3 samsung_ipc.py down [STEP]     # Giảm độ sáng (mặc định bước 5)
    python3 samsung_ipc.py set-host <IP>   # Cập nhật địa chỉ IP màn hình
    python3 samsung_ipc.py info            # Thông tin thiết bị
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
    -32010: "thông báo Allow trên màn hình bị từ chối hoặc hết giờ"
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
    return os.environ.get("SAMSUNG_IPC_HOST", "192.168.31.135")


HOST = get_current_host()


class IPCError(Exception):
    pass


def keychain_get(account):
    r = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", account, "-w"],
        capture_output=True, text=True
    )
    return r.stdout.strip() if r.returncode == 0 else None


def keychain_set(account, secret):
    cmd = 'add-generic-password -U -s "%s" -a "%s" -w "%s"\n' % (KEYCHAIN_SERVICE, account, secret)
    r = subprocess.run(["security", "-i"], input=cmd, capture_output=True, text=True)
    if r.returncode != 0 or "error" in r.stderr.lower():
        pass


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
        reply = json.loads(raw_body.decode() or "{}")
    except ValueError:
        raise IPCError("Phản hồi không hợp lệ từ màn hình (%s)" % status)
    if "result" in reply:
        return reply["result"], fingerprint
    err = reply.get("error", reply)
    code = err.get("code")
    hint = AUTH_CODES.get(code)
    raise IPCError("%s thất bại: mã %s %s%s" % (
        method, code, err.get("message"),
        " - %s; hãy bấm [Ghép nối lại]" % hint if hint else ""
    ))


def credentials():
    cfg = load_config()
    if cfg.get("token") and cfg.get("cert"):
        return cfg["token"], cfg["cert"]

    # Dự phòng đọc từ Keychain
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
    ap = argparse.ArgumentParser(description="Samsung ViewFinity S9 IP Control - Hardware Backlight")
    sub = ap.add_subparsers(dest="cmd", required=True)
    
    p_pair = sub.add_parser("pair")
    p_pair.add_argument("host", nargs="?", default=None, help="IP của màn hình")
    
    sub.add_parser("get")
    
    p_set = sub.add_parser("set")
    p_set.add_argument("value", help="Độ sáng đèn nền thật 0-50")

    p_host = sub.add_parser("set-host")
    p_host.add_argument("host", help="Địa chỉ IP mới của màn hình")
    
    for name in ("up", "down"):
        sub.add_parser(name).add_argument("step", nargs="?", type=int, default=DEFAULT_STEP)
    sub.add_parser("info")
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
        elif args.cmd == "info":
            token, pin = credentials()
            result, _ = rpc("getDeviceInformation", token=token, pin=pin)
            print(json.dumps(result, indent=2))
    except IPCError as exc:
        sys.exit("Lỗi: %s" % exc)


if __name__ == "__main__":
    main()
