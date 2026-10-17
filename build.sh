#!/bin/bash
set -e

APP_NAME="Samsung Monitor Control"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
TARGET_APP_DIR="/Applications/${BUNDLE_DIR}"

echo "==> 1. Dừng ứng dụng cũ nếu đang chạy..."
killall "${APP_NAME}" 2>/dev/null || true

echo "==> 2. Dọn dẹp bản build cũ và tạo cấu trúc .app..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "==> 3. Đưa samsung_ipc.py vào Bundle Resources..."
cp samsung_ipc.py "${RESOURCES_DIR}/"
chmod +x "${RESOURCES_DIR}/samsung_ipc.py"

echo "==> 4. Tạo file cấu hình Info.plist với quyền mạng cục bộ..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Samsung Monitor Control</string>
    <key>CFBundleIdentifier</key>
    <string>com.hieutran.samsungmonitorcontrol</string>
    <key>CFBundleName</key>
    <string>Samsung Monitor Control</string>
    <key>CFBundleDisplayName</key>
    <string>Samsung Monitor Control</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Ứng dụng cần quyền kết nối qua mạng nội bộ để điều khiển độ sáng màn hình Samsung ViewFinity S9.</string>
</dict>
</plist>
EOF

echo "==> 5. Biên dịch mã nguồn Swift thành ứng dụng native..."
swiftc -O main.swift -o "${MACOS_DIR}/${APP_NAME}" -framework Cocoa -framework SwiftUI

echo "==> 6. Ký số Ad-hoc để macOS cấp quyền mạng nội bộ..."
codesign --force --deep --sign - "${BUNDLE_DIR}"

echo "==> 7. Cài đặt vào /Applications..."
rm -rf "${TARGET_APP_DIR}"
cp -R "${BUNDLE_DIR}" /Applications/

echo "==> 8. Khởi chạy ứng dụng..."
open "${TARGET_APP_DIR}"

echo ""
echo "✅ HOÀN TẤT: Đã biên dịch và cài đặt vào ${TARGET_APP_DIR}!"
