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

class MonitorModel: ObservableObject {
    @Published var brightness: Double = 50.0
    @Published var contrast: Double = 50.0
    @Published var sharpness: Double = 10.0
    @Published var gameMode: String = "On"
    @Published var soundMode: String = "Standard"
    @Published var volume: Double = 50.0
    @Published var isMuted: Bool = false
    @Published var inputSource: String = "USB-C"

    @Published var isAdvancedExpanded: Bool = false
    @Published var isLoading: Bool = false
    @Published var isPairing: Bool = false
    @Published var statusMessage: String = ""
    @Published var monitorIP: String = ""
    @Published var showSettings: Bool = false

    private var debounceBacklight: DispatchWorkItem?
    private var debounceContrast: DispatchWorkItem?
    private var debounceSharpness: DispatchWorkItem?
    private var debounceVolume: DispatchWorkItem?

    init() {
        loadConfiguredIP()
        fetchAllStates()
    }

    func loadConfiguredIP() {
        let configPath = ("~/.samsung_monitor_control.json" as NSString).expandingTildeInPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let host = json["host"] as? String, !host.isEmpty {
            self.monitorIP = host
        }
    }

    func runScriptAsync(args: [String], completion: @escaping (Bool, String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let script = getScriptPath()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script] + args
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

                let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0, process.terminationStatus == 0 ? outStr : errStr)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(false, error.localizedDescription)
                }
            }
        }
    }

    func fetchAllStates() {
        isLoading = true
        runScriptAsync(args: ["status"]) { [weak self] success, output in
            guard let self = self else { return }
            self.isLoading = false
            if success, let data = output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let b = json["backlight"] as? Double { self.brightness = b }
                else if let b = json["backlight"] as? Int { self.brightness = Double(b) }

                if let c = json["contrast"] as? Double { self.contrast = c }
                else if let c = json["contrast"] as? Int { self.contrast = Double(c) }

                if let s = json["sharpness"] as? Double { self.sharpness = s }
                else if let s = json["sharpness"] as? Int { self.sharpness = Double(s) }

                if let g = json["gameMode"] as? String { self.gameMode = g }
                if let sm = json["soundMode"] as? String { self.soundMode = sm }

                if let v = json["volume"] as? Double { self.volume = v }
                else if let v = json["volume"] as? Int { self.volume = Double(v) }

                if let m = json["mute"] as? String { self.isMuted = (m == "muteOn") }
                if let inp = json["inputSource"] as? String { self.inputSource = inp }

                self.statusMessage = ""
            } else {
                self.statusMessage = output.isEmpty ? "Không đọc được trạng thái" : output
            }
        }
    }

    func setBrightness(to val: Double) {
        brightness = val
        debounceBacklight?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runScriptAsync(args: ["set", "\(Int(val))"]) { success, out in
                if !success { self?.statusMessage = out }
            }
        }
        debounceBacklight = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    func setContrast(to val: Double) {
        contrast = val
        debounceContrast?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runScriptAsync(args: ["contrast", "\(Int(val))"]) { success, out in
                if !success { self?.statusMessage = out }
            }
        }
        debounceContrast = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    func setSharpness(to val: Double) {
        sharpness = val
        debounceSharpness?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runScriptAsync(args: ["sharpness", "\(Int(val))"]) { success, out in
                if !success { self?.statusMessage = out }
            }
        }
        debounceSharpness = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    func setGameMode(to val: String) {
        gameMode = val
        runScriptAsync(args: ["game-mode", val]) { [weak self] success, out in
            if success {
                self?.gameMode = out
                self?.statusMessage = ""
            } else {
                self?.statusMessage = out
            }
        }
    }

    func setSoundMode(to val: String) {
        soundMode = val
        runScriptAsync(args: ["sound-mode", val]) { [weak self] success, out in
            if success {
                self?.soundMode = out
                self?.statusMessage = ""
            } else {
                self?.statusMessage = out
            }
        }
    }

    func setVolume(to val: Double) {
        volume = val
        debounceVolume?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runScriptAsync(args: ["volume", "\(Int(val))"]) { success, out in
                if !success { self?.statusMessage = out }
            }
        }
        debounceVolume = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    func toggleMute() {
        let target = isMuted ? "off" : "on"
        isMuted.toggle()
        runScriptAsync(args: ["mute", target]) { [weak self] success, out in
            if success {
                self?.isMuted = (out == "muteOn")
                self?.statusMessage = ""
            } else {
                self?.isMuted.toggle()
                self?.statusMessage = out
            }
        }
    }

    func sendKey(_ key: String) {
        runScriptAsync(args: ["key", key]) { [weak self] success, out in
            if !success { self?.statusMessage = out }
        }
    }

    func setPower(_ action: String) {
        runScriptAsync(args: ["power", action]) { [weak self] success, out in
            if !success { self?.statusMessage = out }
        }
    }

    func pairMonitor(targetHost: String? = nil) {
        isPairing = true
        statusMessage = "Bấm [Cho phép / Allow] trên màn hình S9..."
        var args = ["pair"]
        if let host = targetHost, !host.isEmpty {
            args.append(host)
        }
        runScriptAsync(args: args) { [weak self] success, out in
            guard let self = self else { return }
            self.isPairing = false
            if success {
                self.statusMessage = "Ghép nối thành công!"
                self.loadConfiguredIP()
                self.fetchAllStates()
            } else {
                self.statusMessage = out.isEmpty ? "Ghép nối thất bại" : out
            }
        }
    }
}

// ============================================================
// GIAO DIỆN CHUẨN DESIGN SYSTEM APPLE (macOS CONTROL CENTER STYLE)
// ============================================================
struct MonitorPopoverView: View {
    @StateObject var model = MonitorModel()
    @State private var editIP: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Header chuẩn macOS Control Center
            HStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Samsung ViewFinity S9")
                        .font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("5K • \(model.inputSource)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if model.isLoading || model.isPairing {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Button {
                        model.fetchAllStates()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Làm mới")
                }
            }

            Divider()

            // 2. Độ sáng màn hình (Apple Display Slider Style)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Độ sáng")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(model.brightness)) / 50")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "sun.min.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Slider(
                        value: Binding(
                            get: { model.brightness },
                            set: { model.setBrightness(to: $0) }
                        ),
                        in: 0...50,
                        step: 1
                    )

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                // 4 Nút preset chuẩn Apple Capsule Pills
                HStack(spacing: 6) {
                    PresetPill(title: "10", subtitle: "Tối", value: 10, current: model.brightness) {
                        model.setBrightness(to: 10)
                    }
                    PresetPill(title: "25", subtitle: "Vừa", value: 25, current: model.brightness) {
                        model.setBrightness(to: 25)
                    }
                    PresetPill(title: "40", subtitle: "Sáng", value: 40, current: model.brightness) {
                        model.setBrightness(to: 40)
                    }
                    PresetPill(title: "50", subtitle: "Max", value: 50, current: model.brightness) {
                        model.setBrightness(to: 50)
                    }
                }
            }

            Divider()

            // 3. Game Mode (Chuẩn công tắc Toggle Switch của macOS)
            Toggle(isOn: Binding(
                get: { model.gameMode == "On" },
                set: { model.setGameMode(to: $0 ? "On" : "Off") }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(model.gameMode == "On" ? .orange : .secondary)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Game Mode")
                            .font(.system(size: 12, weight: .medium))
                        Text(model.gameMode == "On" ? "Đang bật (Low Latency tối thiểu)" : "Đang tắt (Chuẩn màu đồ họa)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .toggleStyle(.switch)

            Divider()

            // 4. Âm thanh loa màn hình
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Âm lượng")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int(model.volume))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    Button {
                        model.toggleMute()
                    } label: {
                        Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12))
                            .foregroundColor(model.isMuted ? .red : .secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)

                    Slider(
                        value: Binding(
                            get: { model.volume },
                            set: { model.setVolume(to: $0) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                }

                // Chế độ âm thanh (Native Menu Picker)
                HStack {
                    Text("Chế độ âm thanh")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { model.soundMode },
                        set: { model.setSoundMode(to: $0) }
                    )) {
                        Text("Standard (Tiêu chuẩn)").tag("Standard")
                        Text("Game (Âm vòm)").tag("Game")
                        Text("Music (Nghe nhạc)").tag("Music")
                        Text("Movie (Xem phim)").tag("Movie")
                        Text("Amplify (Khuếch đại thoại)").tag("Amplify")
                        Text("Adaptive (Tự thích ứng)").tag("Adaptive")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.system(size: 11))
                }
            }

            Divider()

            // 5. Tùy chỉnh nâng cao (Apple DisclosureGroup)
            DisclosureGroup(isExpanded: $model.isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    // Contrast
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Độ tương phản (Contrast)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(model.contrast))")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        Slider(value: Binding(get: { model.contrast }, set: { model.setContrast(to: $0) }), in: 0...50, step: 1)
                    }

                    // Sharpness
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Độ sắc nét (Sharpness)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(model.sharpness))")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        Slider(value: Binding(get: { model.sharpness }, set: { model.setSharpness(to: $0) }), in: 0...20, step: 1)
                    }

                    // Phím điều khiển nhanh (Remote Buttons)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Phím điều khiển nhanh")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            AppleButton(title: "Menu", icon: "list.bullet") { model.sendKey("menu") }
                            AppleButton(title: "Home", icon: "house") { model.sendKey("firstScreen") }
                            AppleButton(title: "Back", icon: "arrow.uturn.backward") { model.sendKey("return") }
                            AppleButton(title: "OK", icon: "checkmark") { model.sendKey("enter") }
                        }
                    }

                    // Cài đặt mạng / Ghép nối
                    HStack(spacing: 8) {
                        Button {
                            model.pairMonitor()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                Text(model.isPairing ? "Đang chờ..." : "Ghép nối lại")
                            }
                            .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isPairing)

                        Spacer()

                        Button {
                            model.showSettings.toggle()
                            editIP = model.monitorIP
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                    }

                    if model.showSettings {
                        HStack(spacing: 6) {
                            TextField("192.168.x.x", text: $editIP)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 11, design: .monospaced))
                            Button("Lưu") {
                                model.monitorIP = editIP
                                model.showSettings = false
                                model.pairMonitor(targetHost: editIP)
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.system(size: 11))
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Tùy chỉnh & Phím điều khiển")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            // Status message
            if !model.statusMessage.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: model.statusMessage.contains("Lỗi") ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(model.statusMessage.contains("Lỗi") ? .red : .accentColor)
                    Text(model.statusMessage)
                        .font(.system(size: 10))
                        .foregroundColor(model.statusMessage.contains("Lỗi") ? .red : .secondary)
                        .lineLimit(2)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }

            Divider()

            // 6. Footer (macOS Menu Bar Standard)
            HStack {
                Button {
                    model.setPower("powerOff")
                } label: {
                    Label("Tắt màn hình", systemImage: "power")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Thoát")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}

// Capsule Pill Button chuẩn macOS Control Center
struct PresetPill: View {
    let title: String
    let subtitle: String
    let value: Double
    let current: Double
    let action: () -> Void

    var isSelected: Bool { Int(current) == Int(value) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct AppleButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(5)
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
        popover.contentSize = NSSize(width: 290, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MonitorPopoverView())

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
