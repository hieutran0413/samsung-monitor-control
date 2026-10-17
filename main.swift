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

    @Published var selectedTab: Int = 0 // 0: Hiển thị, 1: Âm thanh & Game, 2: Điều khiển
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
                self?.statusMessage = "Âm thanh: \(out)"
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
                self?.isMuted.toggle()
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
        VStack(spacing: 12) {
            // Header: Apple Native Style
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "display")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Samsung ViewFinity S9")
                        .font(.headline)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("5K • \(model.inputSource) • \(model.monitorIP.isEmpty ? "Đang kết nối" : model.monitorIP)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if model.isLoading || model.isPairing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button {
                        model.fetchAllStates()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Làm mới trạng thái")
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            // Native Apple Segmented Picker
            Picker("Chế độ", selection: $model.selectedTab) {
                Label("Hiển thị", systemImage: "sun.max.fill").tag(0)
                Label("Âm thanh & Game", systemImage: "gamecontroller.fill").tag(1)
                Label("Điều khiển", systemImage: "slider.horizontal.3").tag(2)
            }
            .pickerStyle(.segmented)

            // Tab Content
            if model.selectedTab == 0 {
                // TAB 0: HIỂN THỊ (DISPLAY)
                VStack(spacing: 12) {
                    // Backlight Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Đèn nền (Hardware Backlight)", systemImage: "sun.max.fill")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Int(model.brightness)) / 50")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundColor(.accentColor)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "sun.min")
                                    .foregroundColor(.secondary)
                                    .font(.caption)

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
                                    .font(.caption)
                            }

                            // Native Segmented Preset Selector
                            Picker("Mức chọn nhanh", selection: Binding(
                                get: { Int(model.brightness) },
                                set: { model.setBrightness(to: Double($0)) }
                            )) {
                                Text("10 • Tối").tag(10)
                                Text("25 • Vừa").tag(25)
                                Text("40 • Sáng").tag(40)
                                Text("50 • Max").tag(50)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(4)
                    }

                    // Contrast & Sharpness Card
                    GroupBox {
                        VStack(spacing: 10) {
                            // Contrast
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label("Độ tương phản (Contrast)", systemImage: "circle.lefthalf.filled")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(model.contrast))")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                }
                                Slider(
                                    value: Binding(
                                        get: { model.contrast },
                                        set: { model.setContrast(to: $0) }
                                    ),
                                    in: 0...50,
                                    step: 1
                                )
                            }

                            Divider()

                            // Sharpness
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label("Độ sắc nét (Sharpness)", systemImage: "aqi.medium")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(model.sharpness))")
                                        .font(.caption.weight(.semibold).monospacedDigit())
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
                        }
                        .padding(4)
                    }
                }
            } else if model.selectedTab == 1 {
                // TAB 1: GAME & AUDIO
                VStack(spacing: 12) {
                    // Game Mode GroupBox
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Game Mode (Low Latency)", systemImage: "bolt.fill")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(model.gameMode == "On" ? "ĐANG BẬT" : (model.gameMode == "Off" ? "ĐANG TẮT" : "AUTO"))
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(model.gameMode == "On" ? Color.green.opacity(0.18) : Color.gray.opacity(0.18))
                                    .foregroundColor(model.gameMode == "On" ? .green : .secondary)
                                    .cornerRadius(4)
                            }

                            Picker("Game Mode", selection: Binding(
                                get: { model.gameMode },
                                set: { model.setGameMode(to: $0) }
                            )) {
                                Text("Bật (Low Latency)").tag("On")
                                Text("Tắt (Chuẩn màu)").tag("Off")
                                Text("Tự động").tag("Auto")
                            }
                            .pickerStyle(.segmented)

                            Text(model.gameMode == "On"
                                 ? "⚡ Đang ngắt bộ lọc hình ảnh để đạt độ trễ tối thiểu khi chơi game."
                                 : "🎨 Đang giữ nguyên đầy đủ bộ lọc màu và độ tương phản chuẩn đồ họa.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }

                    // Audio GroupBox
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            // Sound profile popup menu
                            HStack {
                                Label("Chế độ âm thanh:", systemImage: "speaker.wave.3")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { model.soundMode },
                                    set: { model.setSoundMode(to: $0) }
                                )) {
                                    Text("Standard (Chuẩn)").tag("Standard")
                                    Text("Game (Vòm)").tag("Game")
                                    Text("Music (Nhạc)").tag("Music")
                                    Text("Movie (Phim)").tag("Movie")
                                    Text("Amplify (Thoại)").tag("Amplify")
                                    Text("Adaptive (Tự thích ứng)").tag("Adaptive")
                                }
                                .pickerStyle(.menu)
                                .frame(width: 155)
                            }

                            Divider()

                            // Volume & Mute
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label("Âm lượng loa màn hình:", systemImage: "speaker.wave.2")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int(model.volume))%")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                }

                                HStack(spacing: 8) {
                                    Button {
                                        model.toggleMute()
                                    } label: {
                                        Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .foregroundColor(model.isMuted ? .red : .primary)
                                            .font(.system(size: 13))
                                            .frame(width: 22)
                                    }
                                    .buttonStyle(.plain)
                                    .help(model.isMuted ? "Bật tiếng" : "Tắt tiếng")

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
                        .padding(4)
                    }
                }
            } else {
                // TAB 2: REMOTE & SYSTEM
                VStack(spacing: 12) {
                    // Remote D-Pad GroupBox
                    GroupBox {
                        VStack(spacing: 8) {
                            // Function Keys row
                            ControlGroup {
                                Button { model.sendKey("menu") } label: {
                                    Label("Menu", systemImage: "list.bullet")
                                }
                                Button { model.sendKey("firstScreen") } label: {
                                    Label("Home", systemImage: "house")
                                }
                                Button { model.sendKey("return") } label: {
                                    Label("Return", systemImage: "arrow.uturn.backward")
                                }
                            }

                            // Directional Navigation
                            VStack(spacing: 4) {
                                Button { model.sendKey("cursorUp") } label: {
                                    Image(systemName: "chevron.up")
                                        .frame(width: 38, height: 26)
                                }
                                .buttonStyle(.bordered)

                                HStack(spacing: 8) {
                                    Button { model.sendKey("cursorLeft") } label: {
                                        Image(systemName: "chevron.left")
                                            .frame(width: 32, height: 26)
                                    }
                                    .buttonStyle(.bordered)

                                    Button { model.sendKey("enter") } label: {
                                        Text("OK")
                                            .font(.caption.weight(.bold))
                                            .frame(width: 38, height: 26)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button { model.sendKey("cursorRight") } label: {
                                        Image(systemName: "chevron.right")
                                            .frame(width: 32, height: 26)
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Button { model.sendKey("cursorDn") } label: {
                                    Image(systemName: "chevron.down")
                                        .frame(width: 38, height: 26)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity)
                    }

                    // Settings & Pairing GroupBox
                    GroupBox {
                        VStack(spacing: 8) {
                            HStack {
                                Button {
                                    model.pairMonitor()
                                } label: {
                                    Label(model.isPairing ? "Đang chờ bấm Allow..." : "Ghép nối lại (Pair)", systemImage: "key.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .disabled(model.isPairing)

                                Spacer()

                                Button {
                                    model.showSettings.toggle()
                                    editIP = model.monitorIP
                                } label: {
                                    Label("Đổi IP", systemImage: "gearshape")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }

                            if model.showSettings {
                                HStack(spacing: 6) {
                                    TextField("192.168.x.x", text: $editIP)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.caption.monospaced())
                                    Button("Lưu & Pair") {
                                        model.monitorIP = editIP
                                        model.showSettings = false
                                        model.pairMonitor(targetHost: editIP)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .font(.caption)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding(4)
                    }
                }
            }

            // Status message toast
            if !model.statusMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: model.statusMessage.contains("Lỗi") ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.caption)
                        .foregroundColor(model.statusMessage.contains("Lỗi") ? .red : .accentColor)
                    Text(model.statusMessage)
                        .font(.caption2)
                        .foregroundColor(model.statusMessage.contains("Lỗi") ? .red : .primary)
                    Spacer()
                }
                .padding(6)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }

            Divider()

            // Footer
            HStack {
                Button {
                    model.setPower("powerOff")
                } label: {
                    Label("Tắt màn hình", systemImage: "power")
                        .font(.caption)
                        .foregroundColor(.red.opacity(0.9))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Thoát")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)
        }
        .padding(14)
        .frame(width: 340)
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
        popover.contentSize = NSSize(width: 340, height: 420)
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
