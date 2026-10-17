import Cocoa
import SwiftUI

func getScriptPath() -> String {
    if let bundlePath = Bundle.main.path(forResource: "samsung_ipc", ofType: "py") {
        return bundlePath
    }
    let resPath = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/samsung_ipc.py").path
    if FileManager.default.fileExists(atPath: resPath) {
        return resPath
    }
    let repoPath = "/Volumes/My Data/Development/samsung-monitor-control/samsung_ipc.py"
    if FileManager.default.fileExists(atPath: repoPath) {
        return repoPath
    }
    let fallbackPath = "/Volumes/My Data/Development/super-display/samsung_ipc.py"
    if FileManager.default.fileExists(atPath: fallbackPath) {
        return fallbackPath
    }
    return repoPath
}

class BrightnessModel: ObservableObject {
    @Published var brightness: Double = 25.0
    @Published var isLoading: Bool = false
    @Published var isPairing: Bool = false
    @Published var statusMessage: String = ""
    @Published var monitorIP: String = ""
    @Published var showSettings: Bool = false

    private var debounceWorkItem: DispatchWorkItem?

    init() {
        loadConfiguredIP()
        fetchCurrentBrightness()
    }

    func loadConfiguredIP() {
        let configPath = ("~/.samsung_monitor_control.json" as NSString).expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let host = json["host"] as? String, !host.isEmpty {
            self.monitorIP = host
        }
    }

    func fetchCurrentBrightness() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let script = getScriptPath()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script, "get"]
            process.environment = ProcessInfo.processInfo.environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

                if process.terminationStatus == 0,
                   let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let val = Double(output) {
                    DispatchQueue.main.async {
                        self.brightness = val
                        self.isLoading = false
                        self.statusMessage = ""
                    }
                } else {
                    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Lỗi đọc độ sáng"
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.statusMessage = errStr
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func setBrightness(to val: Double) {
        brightness = val
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.applyBrightness(Int(val))
        }
        debounceWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    func applyBrightness(_ val: Int) {
        let script = getScriptPath()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script, "set", "\(val)"]
        process.environment = ProcessInfo.processInfo.environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus == 0 {
                DispatchQueue.main.async {
                    self.statusMessage = "Đã chỉnh mức: \(val)/50"
                }
            } else {
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Lỗi chỉnh độ sáng"
                DispatchQueue.main.async {
                    self.statusMessage = errStr
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.statusMessage = error.localizedDescription
            }
        }
    }

    func pairMonitor(targetHost: String? = nil) {
        isPairing = true
        statusMessage = "Đang gửi yêu cầu... Vui lòng bấm [Cho phép] trên màn hình S9"

        DispatchQueue.global(qos: .userInitiated).async {
            let script = getScriptPath()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            var args = [script, "pair"]
            if let host = targetHost, !host.isEmpty {
                args.append(host)
            }
            process.arguments = args
            process.environment = ProcessInfo.processInfo.environment

            let errPipe = Pipe()
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                DispatchQueue.main.async {
                    self.isPairing = false
                    if process.terminationStatus == 0 {
                        self.statusMessage = "Ghép nối thành công! Đã cấp quyền."
                        self.loadConfiguredIP()
                        self.fetchCurrentBrightness()
                    } else {
                        self.statusMessage = errStr.isEmpty ? "Ghép nối thất bại" : errStr
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.isPairing = false
                    self.statusMessage = "Lỗi: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct BrightnessPopoverView: View {
    @StateObject var model = BrightnessModel()
    @State private var editIP: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Samsung Monitor Control")
                        .font(.system(size: 13, weight: .bold))
                    Text("ViewFinity S9 (5K) • \(model.monitorIP)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if model.isLoading || model.isPairing {
                    ProgressView().scaleEffect(0.65)
                } else {
                    Text("\(Int(model.brightness)) / 50")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }

            // Thanh trượt Slider
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Slider(
                    value: Binding(
                        get: { model.brightness },
                        set: { model.setBrightness(to: $0) }
                    ),
                    in: 0...50,
                    step: 1
                )
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }

            // Các nút chọn nhanh
            HStack(spacing: 6) {
                PresetButton(title: "10", subtitle: "Tối", value: 10, model: model)
                PresetButton(title: "25", subtitle: "Vừa", value: 25, model: model)
                PresetButton(title: "40", subtitle: "Sáng", value: 40, model: model)
                PresetButton(title: "50", subtitle: "Tối đa", value: 50, model: model)
            }

            // Nút bấm Kết nối lại & Cấp quyền
            HStack(spacing: 8) {
                Button(action: {
                    model.pairMonitor()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                        Text(model.isPairing ? "Đang chờ bấm Allow..." : "Cấp quyền / Ghép nối lại")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.18))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(model.isPairing)

                Button(action: {
                    model.showSettings.toggle()
                    editIP = model.monitorIP
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .padding(5)
                        .background(Color.gray.opacity(0.12))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            // Hộp nhập IP nếu đổi mạng
            if model.showSettings {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Đổi địa chỉ IP màn hình:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        TextField("192.168.x.x", text: $editIP)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 11, design: .monospaced))
                        Button("Lưu & Pair") {
                            model.monitorIP = editIP
                            model.showSettings = false
                            model.pairMonitor(targetHost: editIP)
                        }
                        .font(.system(size: 11))
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(8)
            }

            // Thông báo trạng thái / Lỗi chi tiết
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 10.5))
                    .foregroundColor(model.statusMessage.contains("Lỗi") || model.statusMessage.contains("Không tìm") ? .red : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(4)
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(4)
            }

            Divider()

            // Footer
            HStack {
                Button(action: {
                    model.fetchCurrentBrightness()
                }) {
                    Label("Làm mới", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Thoát")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 310)
    }
}

struct PresetButton: View {
    let title: String
    let subtitle: String
    let value: Double
    @ObservedObject var model: BrightnessModel

    var isSelected: Bool {
        Int(model.brightness) == Int(value)
    }

    var body: some View {
        Button(action: {
            model.setBrightness(to: value)
        }) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Samsung Monitor Control")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 310, height: 210)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: BrightnessPopoverView())

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.popover.performClose(nil)
            }
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
