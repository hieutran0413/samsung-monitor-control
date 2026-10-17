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

struct USBPeripheral: Identifiable {
    let id = UUID()
    let name: String
    let vendor: String
}

class MonitorModel: ObservableObject {
    @Published var brightness: Double = 50.0
    @Published var contrast: Double = 50.0
    @Published var sharpness: Double = 10.0
    @Published var color: Double = 27.0
    @Published var tint: Double = 0.0
    @Published var blackLevel: Double = 0.0
    @Published var gameMode: String = "On"
    @Published var pictureMode: String = "sRGB"
    @Published var soundMode: String = "Standard"
    @Published var volume: Double = 50.0
    @Published var isMuted: Bool = false
    @Published var speakerSelect: String = "Internal"
    @Published var inputSource: String = "USB-C"
    @Published var peripherals: [USBPeripheral] = []

    @Published var isAdvancedExpanded: Bool = false
    @Published var isPeripheralsExpanded: Bool = false
    @Published var isLoading: Bool = false
    @Published var isPairing: Bool = false
    @Published var statusMessage: String = ""
    @Published var monitorIP: String = ""
    @Published var showSettings: Bool = false

    // Keyboard & Remote D-Pad feedback
    @Published var activeKey: String = ""
    @Published var activeKeyBadge: String = ""
    private var resetKeyWorkItem: DispatchWorkItem?

    private var debounceBacklight: DispatchWorkItem?
    private var debounceContrast: DispatchWorkItem?
    private var debounceSharpness: DispatchWorkItem?
    private var debounceColor: DispatchWorkItem?
    private var debounceTint: DispatchWorkItem?
    private var debounceBlackLevel: DispatchWorkItem?
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

                if let col = json["color"] as? Double { self.color = col }
                else if let col = json["color"] as? Int { self.color = Double(col) }

                if let t = json["tint"] as? Double { self.tint = t }
                else if let t = json["tint"] as? Int { self.tint = Double(t) }

                if let bl = json["blackLevel"] as? Double { self.blackLevel = bl }
                else if let bl = json["blackLevel"] as? Int { self.blackLevel = Double(bl) }

                if let g = json["gameMode"] as? String { self.gameMode = g }
                if let pm = json["pictureMode"] as? String { self.pictureMode = pm }
                if let sm = json["soundMode"] as? String { self.soundMode = sm }
                if let spk = json["speakerSelect"] as? String { self.speakerSelect = spk }

                if let v = json["volume"] as? Double { self.volume = v }
                else if let v = json["volume"] as? Int { self.volume = Double(v) }

                if let m = json["mute"] as? String { self.isMuted = (m == "muteOn") }
                if let inp = json["inputSource"] as? String { self.inputSource = inp }

                if let periphs = json["peripherals"] as? [[String: Any]] {
                    self.peripherals = periphs.compactMap { dict in
                        guard let name = dict["name"] as? String else { return nil }
                        let vendor = dict["vendor"] as? String ?? ""
                        if name == "Root" || (name.contains("Hub") && vendor.isEmpty) {
                            return nil
                        }
                        return USBPeripheral(name: name, vendor: vendor)
                    }
                }

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

    func setColor(to val: Double) {
        color = val
        debounceColor?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runScriptAsync(args: ["color", "\(Int(val))"]) { success, out in
                if !success { self?.statusMessage = out }
            }
        }
        debounceColor = item
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
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08, execute: item)
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
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    func setTint(to val: Double) {
        tint = val
        debounceTint?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runScriptAsync(args: ["tint", "\(Int(val))"]) { success, out in
                if !success { self?.statusMessage = out }
            }
        }
        debounceTint = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    func setBlackLevel(to val: Double) {
        blackLevel = val
        debounceBlackLevel?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.runScriptAsync(args: ["black-level", "\(Int(val))"]) { success, out in
                if !success { self?.statusMessage = out }
            }
        }
        debounceBlackLevel = item
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08, execute: item)
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

    func setPictureMode(to val: String) {
        pictureMode = val
        runScriptAsync(args: ["picture-mode", val.lowercased()]) { [weak self] success, out in
            if success {
                self?.fetchAllStates()
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

    func setSpeakerSelect(to val: String) {
        speakerSelect = val
        runScriptAsync(args: ["speaker", val]) { [weak self] success, out in
            if success {
                self?.speakerSelect = out
                self?.statusMessage = ""
            } else {
                self?.statusMessage = out
            }
        }
    }

    func setInputSource(to val: String) {
        inputSource = val
        runScriptAsync(args: ["input", val]) { [weak self] success, out in
            if success {
                self?.inputSource = out
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
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.08, execute: item)
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

    func flashKey(_ keyName: String, label: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeKey = keyName
            self.activeKeyBadge = label
            self.resetKeyWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.activeKey = ""
                self?.activeKeyBadge = ""
            }
            self.resetKeyWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: item)
        }
    }

    func triggerDevMode() {
        statusMessage = "Đang gửi chuỗi 1-2-3-4-5 kích hoạt Dev Mode..."
        runScriptAsync(args: ["dev-mode"]) { [weak self] success, out in
            self?.statusMessage = out
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

// Global shared model instance
let sharedModel = MonitorModel()

// ============================================================
// GIAO DIỆN CHUẨN DESIGN SYSTEM APPLE (macOS CONTROL CENTER STYLE)
// ============================================================
struct MonitorPopoverView: View {
    @ObservedObject var model: MonitorModel
    @State private var editIP: String = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
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
                        .help("Làm mới trạng thái")
                    }
                }

                Divider()

                // 2. Độ sáng màn hình (Apple Display Slider)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Độ sáng đèn nền")
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

                // 3. Độ đậm màu (Color Saturation)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                            Text("Độ đậm màu (Color)")
                                .font(.system(size: 12, weight: .medium))
                        }
                        Spacer()
                        Text("\(Int(model.color)) / 50")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.striped.horizontal")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Slider(
                            value: Binding(
                                get: { model.color },
                                set: { model.setColor(to: $0) }
                            ),
                            in: 0...50,
                            step: 1
                        )

                        Image(systemName: "circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.purple)
                    }
                }

                Divider()

                // 4. Game Mode (Công tắc Toggle Switch của macOS)
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
                            Text("Game Mode (Low Latency)")
                                .font(.system(size: 12, weight: .medium))
                            Text(model.gameMode == "On" ? "Đang bật (Phản hồi tức thì)" : "Đang tắt (Chuẩn màu đồ họa)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)

                Divider()

                // 4b. Picture Mode (Không gian màu chuẩn phần cứng)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.indigo)
                            .frame(width: 16)
                        Text("Không gian màu (Color Space)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(model.pictureMode)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 5) {
                        ColorModePill(title: "sRGB", subtitle: "Web", isSelected: model.pictureMode.contains("sRGB") || model.pictureMode.contains("327714")) {
                            model.setPictureMode(to: "srgb")
                        }
                        ColorModePill(title: "DCI-P3", subtitle: "Cinema", isSelected: model.pictureMode.contains("P3") || model.pictureMode.contains("327712")) {
                            model.setPictureMode(to: "dci-p3")
                        }
                        ColorModePill(title: "BT.709", subtitle: "HDTV", isSelected: model.pictureMode.contains("709") || model.pictureMode.contains("327713")) {
                            model.setPictureMode(to: "bt709")
                        }
                        ColorModePill(title: "Phim", subtitle: "Giải trí", isSelected: model.pictureMode.contains("Entertainment") || model.pictureMode.contains("65541")) {
                            model.setPictureMode(to: "entertainment")
                        }
                    }
                }

                Divider()

                // 5. Âm thanh loa màn hình & Chọn đầu ra
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Âm lượng loa")
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

                    // Chế độ âm thanh & Ngõ ra
                    HStack {
                        Text("Chế độ âm thanh")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.soundMode },
                            set: { model.setSoundMode(to: $0) }
                        )) {
                            Text("Standard (Chuẩn)").tag("Standard")
                            Text("Game (Âm vòm)").tag("Game")
                            Text("Music (Nhạc)").tag("Music")
                            Text("Movie (Phim)").tag("Movie")
                            Text("Amplify (Hội thoại)").tag("Amplify")
                            Text("Adaptive (Tự thích ứng)").tag("Adaptive")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.system(size: 11))
                    }

                    // Đầu ra âm thanh
                    HStack {
                        Text("Đầu ra âm thanh")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.speakerSelect },
                            set: { model.setSpeakerSelect(to: $0) }
                        )) {
                            Text("Loa trong màn hình").tag("Internal")
                            Text("Thiết bị ngoài / Receiver").tag("Receiver")
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.system(size: 11))
                    }
                }

                Divider()

                // 6. Cụm điều khiển từ xa D-Pad & Bàn phím Mac (Remote Control)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 5) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                            Text("Điều khiển từ xa (Remote)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Spacer()
                        if !model.activeKeyBadge.isEmpty {
                            Text("Đã bấm: \(model.activeKeyBadge)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }

                    // Visual D-Pad
                    VStack(spacing: 4) {
                        // Up
                        HStack {
                            Spacer()
                            RemoteDpadKey(
                                title: "↑",
                                icon: "arrow.up",
                                isHighlighted: model.activeKey == "cursorUp"
                            ) {
                                model.sendKey("cursorUp")
                                model.flashKey("cursorUp", label: "↑")
                            }
                            .frame(width: 48, height: 26)
                            Spacer()
                        }

                        // Left - OK - Right
                        HStack(spacing: 6) {
                            Spacer()
                            RemoteDpadKey(
                                title: "←",
                                icon: "arrow.left",
                                isHighlighted: model.activeKey == "cursorLeft"
                            ) {
                                model.sendKey("cursorLeft")
                                model.flashKey("cursorLeft", label: "←")
                            }
                            .frame(width: 48, height: 26)

                            RemoteDpadKey(
                                title: "OK",
                                icon: "checkmark",
                                isProminent: true,
                                isHighlighted: model.activeKey == "enter"
                            ) {
                                model.sendKey("enter")
                                model.flashKey("enter", label: "Enter")
                            }
                            .frame(width: 54, height: 26)

                            RemoteDpadKey(
                                title: "→",
                                icon: "arrow.right",
                                isHighlighted: model.activeKey == "cursorRight"
                            ) {
                                model.sendKey("cursorRight")
                                model.flashKey("cursorRight", label: "→")
                            }
                            .frame(width: 48, height: 26)
                            Spacer()
                        }

                        // Down
                        HStack {
                            Spacer()
                            RemoteDpadKey(
                                title: "↓",
                                icon: "arrow.down",
                                isHighlighted: model.activeKey == "cursorDn"
                            ) {
                                model.sendKey("cursorDn")
                                model.flashKey("cursorDn", label: "↓")
                            }
                            .frame(width: 48, height: 26)
                            Spacer()
                        }
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)

                    // Cụm phím chức năng
                    HStack(spacing: 5) {
                        AppleButton(title: "Menu (M)", icon: "list.bullet") {
                            model.sendKey("menu")
                            model.flashKey("menu", label: "Menu")
                        }
                        AppleButton(title: "Home (H)", icon: "house") {
                            model.sendKey("firstScreen")
                            model.flashKey("firstScreen", label: "Home")
                        }
                        AppleButton(title: "Back (Esc)", icon: "arrow.uturn.backward") {
                            model.sendKey("return")
                            model.flashKey("return", label: "Esc")
                        }
                        AppleButton(title: "Dev Mode (12345)", icon: "terminal") {
                            model.triggerDevMode()
                        }
                    }

                    // Hướng dẫn phím Mac
                    HStack(spacing: 4) {
                        Image(systemName: "command")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text("Phím Mac: Mũi tên (↑ ↓ ← →), Enter, Esc, M, H, Phím số (0-9)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 2)
                }

                Divider()

                // 7. Cụm thiết bị ngoại vi & Cổng kết nối (USB Hub & Peripherals)
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { model.isPeripheralsExpanded },
                        set: { _ in
                            withAnimation(.snappy(duration: 0.15)) {
                                model.isPeripheralsExpanded.toggle()
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Nguồn vào (Input Source)
                        HStack {
                            Text("Nguồn đầu vào")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { model.inputSource },
                                set: { model.setInputSource(to: $0) }
                            )) {
                                Text("USB-C (Thunderbolt Mac)").tag("USB-C")
                                Text("Mini-DisplayPort").tag("Mini-DP")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .font(.system(size: 11))
                        }

                        // Danh sách thiết bị cắm vào USB Hub
                        Text("Thiết bị cắm qua USB Hub màn hình:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)

                        if model.peripherals.isEmpty {
                            Text("Không có thiết bị ngoại vi nào được cắm")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(model.peripherals) { dev in
                                    HStack(spacing: 6) {
                                        Image(systemName: iconForDevice(name: dev.name))
                                            .font(.system(size: 10))
                                            .foregroundColor(.accentColor)
                                            .frame(width: 14)
                                        Text(dev.name)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                        if !dev.vendor.isEmpty {
                                            Text("(\(dev.vendor))")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                    .padding(.horizontal, 6)
                                    .background(Color.secondary.opacity(0.06))
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cable.connector.horizontal")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text("Thiết bị ngoại vi & Cổng kết nối")
                            .font(.system(size: 11, weight: .medium))
                    }
                }

                Divider()

                // 8. Tùy chỉnh hình ảnh nâng cao (DisclosureGroup)
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { model.isAdvancedExpanded },
                        set: { _ in
                            withAnimation(.snappy(duration: 0.15)) {
                                model.isAdvancedExpanded.toggle()
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Contrast
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Độ tương phản (Contrast)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(model.contrast)) / 50")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            Slider(value: Binding(get: { model.contrast }, set: { model.setContrast(to: $0) }), in: 0...50, step: 1)
                        }

                        // Sharpness
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Độ sắc nét (Sharpness)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(model.sharpness)) / 20")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            Slider(value: Binding(get: { model.sharpness }, set: { model.setSharpness(to: $0) }), in: 0...20, step: 1)
                        }

                        // Sắc thái màu (Tint)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Sắc thái màu (Tint G/R)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(model.tint))")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            Slider(value: Binding(get: { model.tint }, set: { model.setTint(to: $0) }), in: -15...15, step: 1)
                        }

                        // Mức sáng điểm đen (Black Level)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Mức sáng điểm đen (Black Level)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(model.blackLevel))")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            Slider(value: Binding(get: { model.blackLevel }, set: { model.setBlackLevel(to: $0) }), in: -5...5, step: 1)
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
                                .font(.system(size: 10))
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isPairing)

                            Spacer()

                            Button {
                                model.showSettings.toggle()
                                editIP = model.monitorIP
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 10))
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
                                .font(.system(size: 10))
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Tùy chỉnh hình ảnh & Mạng")
                            .font(.system(size: 11, weight: .medium))
                    }
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

                // 9. Footer (macOS Menu Bar Standard)
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
        }
        .frame(width: 295)
        .frame(maxHeight: 530)
    }

    func iconForDevice(name: String) -> String {
        let n = name.lowercased()
        if n.contains("keyboard") || n.contains("lofree") || n.contains("key") {
            return "keyboard"
        } else if n.contains("mouse") {
            return "mouse"
        } else if n.contains("speaker") || n.contains("kanto") || n.contains("audio") || n.contains("ora4") {
            return "speaker.wave.2"
        } else if n.contains("cam") || n.contains("slimfit") {
            return "web.camera"
        } else if n.contains("adapter") || n.contains("av") {
            return "cable.connector"
        } else if n.contains("s27c900p") {
            return "display"
        }
        return "usb"
    }
}

// D-Pad Button with highlight effect
struct RemoteDpadKey: View {
    let title: String
    let icon: String
    var isProminent: Bool = false
    var isHighlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: isProminent ? .bold : .medium))
                }
                if isProminent {
                    Text(title)
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                isHighlighted ? Color.accentColor :
                (isProminent ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.12))
            )
            .foregroundColor(
                isHighlighted || isProminent ? .white : .primary
            )
            .cornerRadius(5)
            .animation(.snappy(duration: 0.1), value: isHighlighted)
        }
        .buttonStyle(.plain)
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

// Nút chọn không gian màu phần cứng
struct ColorModePill: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
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
    var mouseEventMonitor: Any?
    var localKeyMonitor: Any?
    var globalKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Samsung Monitor Control")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.animates = false
        popover.contentSize = NSSize(width: 295, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MonitorPopoverView(model: sharedModel))

        // Monitor click outside to close popover
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.popover.performClose(nil)
            }
        }

        // Local monitor for Mac keyboard when app/popover is active
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover.isShown else { return event }

            // Do not intercept if user is typing in TextField (e.g. editIP)
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView || responder is NSTextField {
                return event
            }

            if self.dispatchKey(event.keyCode) {
                return nil // Event handled and consumed
            }
            return event
        }

        // Global monitor as fallback while popover is shown
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover.isShown else { return }
            _ = self.dispatchKey(event.keyCode)
        }
    }

    func dispatchKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 126: // Up Arrow
            sharedModel.sendKey("cursorUp")
            sharedModel.flashKey("cursorUp", label: "↑")
            return true
        case 125: // Down Arrow
            sharedModel.sendKey("cursorDn")
            sharedModel.flashKey("cursorDn", label: "↓")
            return true
        case 123: // Left Arrow
            sharedModel.sendKey("cursorLeft")
            sharedModel.flashKey("cursorLeft", label: "←")
            return true
        case 124: // Right Arrow
            sharedModel.sendKey("cursorRight")
            sharedModel.flashKey("cursorRight", label: "→")
            return true
        case 36, 76: // Enter / Return
            sharedModel.sendKey("enter")
            sharedModel.flashKey("enter", label: "OK (Enter)")
            return true
        case 53: // Escape
            sharedModel.sendKey("return")
            sharedModel.flashKey("return", label: "Back (Esc)")
            return true
        case 46: // 'M' or 'm' -> Menu
            sharedModel.sendKey("menu")
            sharedModel.flashKey("menu", label: "Menu (M)")
            return true
        case 4: // 'H' or 'h' -> Home
            sharedModel.sendKey("firstScreen")
            sharedModel.flashKey("firstScreen", label: "Home (H)")
            return true
        case 18, 83: // 1
            sharedModel.sendKey("number1")
            sharedModel.flashKey("number1", label: "1")
            return true
        case 19, 84: // 2
            sharedModel.sendKey("number2")
            sharedModel.flashKey("number2", label: "2")
            return true
        case 20, 85: // 3
            sharedModel.sendKey("number3")
            sharedModel.flashKey("number3", label: "3")
            return true
        case 21, 86: // 4
            sharedModel.sendKey("number4")
            sharedModel.flashKey("number4", label: "4")
            return true
        case 23, 87: // 5
            sharedModel.sendKey("number5")
            sharedModel.flashKey("number5", label: "5")
            return true
        case 22, 88: // 6
            sharedModel.sendKey("number6")
            sharedModel.flashKey("number6", label: "6")
            return true
        case 26, 89: // 7
            sharedModel.sendKey("number7")
            sharedModel.flashKey("number7", label: "7")
            return true
        case 28, 91: // 8
            sharedModel.sendKey("number8")
            sharedModel.flashKey("number8", label: "8")
            return true
        case 25, 92: // 9
            sharedModel.sendKey("number9")
            sharedModel.flashKey("number9", label: "9")
            return true
        case 29, 82: // 0
            sharedModel.sendKey("number0")
            sharedModel.flashKey("number0", label: "0")
            return true
        default:
            return false
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
