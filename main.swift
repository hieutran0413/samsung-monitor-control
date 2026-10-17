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

    @Published var selectedTab: Int = 0 // 0: Hiển thị, 1: Game & Âm thanh, 2: Remote & Cài đặt
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
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1, execute: item)
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
        statusMessage = "Đang chuyển Game Mode: \(val)..."
        runScriptAsync(args: ["game-mode", val]) { [weak self] success, out in
            if success {
                self?.gameMode = out
                self?.statusMessage = "Game Mode: \(out)"
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
                self?.statusMessage = "Chế độ âm thanh: \(out)"
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
                self?.statusMessage = self?.isMuted == true ? "Đã tắt tiếng loa" : "Đã bật tiếng loa"
            } else {
                self?.isMuted.toggle() // khôi phục
                self?.statusMessage = out
            }
        }
    }

    func sendKey(_ key: String) {
        statusMessage = "Gửi phím: \(key)..."
        runScriptAsync(args: ["key", key]) { [weak self] success, out in
            if success {
                self?.statusMessage = "Đã gửi phím: \(key)"
            } else {
                self?.statusMessage = out
            }
        }
    }

    func setPower(_ action: String) {
        statusMessage = "Lệnh nguồn: \(action)..."
        runScriptAsync(args: ["power", action]) { [weak self] success, out in
            self?.statusMessage = success ? "Nguồn: \(out)" : out
        }
    }

    func pairMonitor(targetHost: String? = nil) {
        isPairing = true
        statusMessage = "Đang gửi yêu cầu... Bấm [Cho phép / Allow] trên màn hình S9"
        var args = ["pair"]
        if let host = targetHost, !host.isEmpty {
            args.append(host)
        }
        runScriptAsync(args: args) { [weak self] success, out in
            guard let self = self else { return }
            self.isPairing = false
            if success {
                self.statusMessage = "Ghép nối thành công! Đã cấp quyền."
                self.loadConfiguredIP()
                self.fetchAllStates()
            } else {
                self.statusMessage = out.isEmpty ? "Ghép nối thất bại" : out
            }
        }
    }
}

struct MonitorPopoverView: View {
    @StateObject var model = MonitorModel()
    @State private var editIP: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Samsung ViewFinity S9 (5K)")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(model.inputSource) • \(model.monitorIP)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if model.isLoading || model.isPairing {
                    ProgressView().scaleEffect(0.65)
                } else {
                    Button(action: {
                        model.fetchAllStates()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }

            // Tab Switcher
            HStack(spacing: 2) {
                TabButton(title: "Hiển thị", icon: "sun.max.fill", index: 0, selectedIndex: $model.selectedTab)
                TabButton(title: "Game & Âm thanh", icon: "gamecontroller.fill", index: 1, selectedIndex: $model.selectedTab)
                TabButton(title: "Điều khiển", icon: "slider.horizontal.3", index: 2, selectedIndex: $model.selectedTab)
            }
            .padding(2)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(8)

            Divider()

            // Nội dung theo Tab
            if model.selectedTab == 0 {
                // TAB 1: HIỂN THỊ (DISPLAY)
                VStack(alignment: .leading, spacing: 10) {
                    // Đèn nền Backlight
                    HStack {
                        Text("Độ sáng đèn nền:")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(model.brightness)) / 50")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }

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

                    // Nút chọn nhanh Presets
                    HStack(spacing: 5) {
                        PresetButton(title: "10", subtitle: "Tối", value: 10, currentVal: model.brightness) {
                            model.setBrightness(to: 10)
                        }
                        PresetButton(title: "25", subtitle: "Vừa", value: 25, currentVal: model.brightness) {
                            model.setBrightness(to: 25)
                        }
                        PresetButton(title: "40", subtitle: "Sáng", value: 40, currentVal: model.brightness) {
                            model.setBrightness(to: 40)
                        }
                        PresetButton(title: "50", subtitle: "Tối đa", value: 50, currentVal: model.brightness) {
                            model.setBrightness(to: 50)
                        }
                    }

                    Divider().padding(.vertical, 2)

                    // Độ tương phản (Contrast)
                    HStack {
                        Text("Độ tương phản:")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(model.contrast)) / 50")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { model.contrast },
                            set: { model.setContrast(to: $0) }
                        ),
                        in: 0...50,
                        step: 1
                    )

                    // Độ sắc nét (Sharpness)
                    HStack {
                        Text("Độ sắc nét:")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("\(Int(model.sharpness)) / 20")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { model.sharpness },
                            set: { model.setSharpness(to: $0) }
                        ),
                        in: 0...20,
                        step: 1
                    )
                }
            } else if model.selectedTab == 1 {
                // TAB 2: GAME MODE & ÂM THANH
                VStack(alignment: .leading, spacing: 10) {
                    // Game Mode Toggle
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Game Mode (Low Latency):")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text(model.gameMode == "On" ? "⚡ ĐANG BẬT" : (model.gameMode == "Off" ? "🎨 ĐANG TẮT" : "🔄 AUTO"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(model.gameMode == "On" ? .green : .secondary)
                        }

                        HStack(spacing: 6) {
                            GameModeButton(title: "Bật (Low Latency)", mode: "On", currentMode: model.gameMode) {
                                model.setGameMode(to: "On")
                            }
                            GameModeButton(title: "Tắt (Chuẩn màu)", mode: "Off", currentMode: model.gameMode) {
                                model.setGameMode(to: "Off")
                            }
                            GameModeButton(title: "Tự động", mode: "Auto", currentMode: model.gameMode) {
                                model.setGameMode(to: "Auto")
                            }
                        }
                    }

                    Divider().padding(.vertical, 2)

                    // Chế độ Âm thanh
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Chế độ âm thanh:")
                            .font(.system(size: 11, weight: .medium))

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 5) {
                            ForEach(["Standard", "Game", "Music", "Movie", "Amplify", "Adaptive"], id: \.self) { sm in
                                SoundModePill(title: sm, current: model.soundMode) {
                                    model.setSoundMode(to: sm)
                                }
                            }
                        }
                    }

                    Divider().padding(.vertical, 2)

                    // Âm lượng loa màn hình
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Âm lượng loa màn hình:")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(Int(model.volume))%")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                model.toggleMute()
                            }) {
                                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(model.isMuted ? .red : .primary)
                                    .font(.system(size: 12))
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
                    }
                }
            } else {
                // TAB 3: ĐIỀU KHIỂN & CÀI ĐẶT
                VStack(alignment: .leading, spacing: 10) {
                    // Phím Remote giả lập
                    Text("Phím điều khiển nhanh:")
                        .font(.system(size: 11, weight: .medium))

                    HStack(spacing: 6) {
                        RemoteButton(title: "Menu", icon: "list.bullet") { model.sendKey("menu") }
                        RemoteButton(title: "Home", icon: "house.fill") { model.sendKey("firstScreen") }
                        RemoteButton(title: "Return", icon: "arrow.uturn.backward") { model.sendKey("return") }
                        RemoteButton(title: "Enter", icon: "checkmark.circle.fill") { model.sendKey("enter") }
                    }

                    // Phím điều hướng
                    HStack(spacing: 6) {
                        Spacer()
                        RemoteButton(title: "▲", icon: "") { model.sendKey("cursorUp") }
                        Spacer()
                    }
                    HStack(spacing: 6) {
                        RemoteButton(title: "◀", icon: "") { model.sendKey("cursorLeft") }
                        RemoteButton(title: "OK", icon: "") { model.sendKey("enter") }
                        RemoteButton(title: "▶", icon: "") { model.sendKey("cursorRight") }
                    }
                    HStack(spacing: 6) {
                        Spacer()
                        RemoteButton(title: "▼", icon: "") { model.sendKey("cursorDn") }
                        Spacer()
                    }

                    Divider().padding(.vertical, 2)

                    // Quản lý nguồn & Ghép nối
                    HStack(spacing: 8) {
                        Button(action: {
                            model.pairMonitor()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "key.fill")
                                Text(model.isPairing ? "Đang chờ Allow..." : "Cấp quyền / Ghép nối lại")
                            }
                            .font(.system(size: 10.5, weight: .medium))
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
                }
            }

            // Thông báo trạng thái
            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(model.statusMessage.contains("Lỗi") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.06))
                    .cornerRadius(4)
            }

            Divider()

            // Footer
            HStack {
                Button(action: {
                    model.setPower("powerOff")
                }) {
                    Label("Tắt màn hình", systemImage: "power")
                        .font(.system(size: 10.5))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text("Thoát")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .frame(width: 325)
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let index: Int
    @Binding var selectedIndex: Int

    var isSelected: Bool { selectedIndex == index }

    var body: some View {
        Button(action: {
            selectedIndex = index
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor : Color.clear)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct GameModeButton: View {
    let title: String
    let mode: String
    let currentMode: String
    let action: () -> Void

    var isSelected: Bool { currentMode.lowercased() == mode.lowercased() }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12))
                .foregroundColor(isSelected ? .accentColor : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct SoundModePill: View {
    let title: String
    let current: String
    let action: () -> Void

    var isSelected: Bool { current.lowercased() == title.lowercased() }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.12))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

struct RemoteButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}

struct PresetButton: View {
    let title: String
    let subtitle: String
    let value: Double
    let currentVal: Double
    let action: () -> Void

    var isSelected: Bool {
        Int(currentVal) == Int(value)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.gray.opacity(0.12))
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
        popover.contentSize = NSSize(width: 325, height: 350)
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
