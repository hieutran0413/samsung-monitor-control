import Cocoa
import SwiftUI
import ServiceManagement

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
    @Published var pictureMode: String = "Unknown"
    @Published var isPictureModeBusy = false
    @Published var soundMode: String = "Standard"
    @Published var volume: Double = 50.0
    @Published var isMuted: Bool = false
    @Published var speakerSelect: String = "Internal"
    @Published var inputSource: String = "USB-C"
    @Published var peripherals: [USBPeripheral] = []

    @Published var isConnected = false
    @Published var isPowerBusy = false
    @Published var isMuteBusy = false
    @Published var isRefreshingSharpness = false
    @Published var isSharpnessSetting = false
    private var sharpnessWritesInFlight = 0
    private var sharpnessWritePending = false
    @Published var remoteKeyboardEnabled = UserDefaults.standard.bool(forKey: "remoteKeyboardEnabled") {
        didSet { UserDefaults.standard.set(remoteKeyboardEnabled, forKey: "remoteKeyboardEnabled") }
    }
    @Published var remoteTabActive = false
    @Published var isLoading: Bool = false
    @Published var isPairing: Bool = false
    @Published var statusMessage: String = ""
    @Published var monitorIP: String = ""

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
        guard !isLoading, !isPairing, !isPowerBusy, !isRefreshingSharpness else { return }
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

                self.isConnected = true
                self.statusMessage = ""
            } else {
                self.isConnected = false
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
        guard !isRefreshingSharpness else { return }
        sharpness = val
        debounceSharpness?.cancel()
        sharpnessWritePending = true
        isSharpnessSetting = true
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.sharpnessWritePending = false
            self.sharpnessWritesInFlight += 1
            self.runScriptAsync(args: ["sharpness", "\(Int(val))"]) { [weak self] success, out in
                guard let self = self else { return }
                self.sharpnessWritesInFlight -= 1
                self.isSharpnessSetting = self.sharpnessWritePending || self.sharpnessWritesInFlight > 0
                if !success { self.statusMessage = out }
            }
        }
        debounceSharpness = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    func refreshSharpness() {
        guard isConnected, !isRefreshingSharpness, !isSharpnessSetting,
              !isLoading, !isPairing, !isPowerBusy, !isPictureModeBusy else { return }
        let target = Int(sharpness)
        isRefreshingSharpness = true
        statusMessage = "Đang khôi phục độ nét về \(target)…"
        runScriptAsync(args: ["refresh-sharpness", "\(target)"]) { [weak self] success, out in
            guard let self = self else { return }
            self.isRefreshingSharpness = false
            self.statusMessage = success ? "Đã khôi phục độ nét về \(target)." : out
        }
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
        let previous = gameMode
        gameMode = val
        runScriptAsync(args: ["game-mode", val]) { [weak self] success, out in
            if success {
                self?.gameMode = out
                self?.statusMessage = ""
            } else {
                self?.gameMode = previous
                self?.statusMessage = out
            }
        }
    }

    func setPictureMode(to val: String) {
        guard !isPictureModeBusy, !isRefreshingSharpness else { return }
        isPictureModeBusy = true
        runScriptAsync(args: ["picture-mode", val.lowercased()]) { [weak self] success, out in
            guard let self = self else { return }
            self.isPictureModeBusy = false
            if success {
                // CLI returns the verified raw mode; update only after readback.
                self.pictureMode = out
                self.statusMessage = ""
                self.fetchAllStates()
            } else {
                self.statusMessage = out
            }
        }
    }

    func setSoundMode(to val: String) {
        let previous = soundMode
        soundMode = val
        runScriptAsync(args: ["sound-mode", val]) { [weak self] success, out in
            if success {
                self?.soundMode = out
                self?.statusMessage = ""
            } else {
                self?.soundMode = previous
                self?.statusMessage = out
            }
        }
    }

    func setSpeakerSelect(to val: String) {
        let previous = speakerSelect
        speakerSelect = val
        runScriptAsync(args: ["speaker", val]) { [weak self] success, out in
            if success {
                self?.speakerSelect = out
                self?.statusMessage = ""
            } else {
                self?.speakerSelect = previous
                self?.statusMessage = out
            }
        }
    }

    func setInputSource(to val: String) {
        let previous = inputSource
        inputSource = val
        runScriptAsync(args: ["input", val]) { [weak self] success, out in
            if success {
                self?.inputSource = out
                self?.statusMessage = ""
            } else {
                self?.inputSource = previous
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
        guard !isMuteBusy else { return }
        isMuteBusy = true
        let target = isMuted ? "off" : "on"
        isMuted.toggle()
        runScriptAsync(args: ["mute", target]) { [weak self] success, out in
            self?.isMuteBusy = false
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
        guard !isPowerBusy, !isRefreshingSharpness else { return }
        isPowerBusy = true
        statusMessage = "Đang gửi lệnh tắt màn hình…"
        runScriptAsync(args: ["power", action]) { [weak self] success, out in
            guard let self = self else { return }
            self.isPowerBusy = false
            self.statusMessage = success ? "Màn hình đã nhận lệnh tắt. Dùng remote để bật lại." : (out.isEmpty ? "Không gửi được lệnh tắt. Kiểm tra kết nối rồi thử lại." : out)
            if success { self.isConnected = false }
        }
    }

    func pairMonitor(targetHost: String? = nil) {
        guard !isPairing, !isRefreshingSharpness else { return }
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
let sharedBrightness = DisplayBrightnessController()

// ============================================================
// CONTROL CENTER: thao tác hàng ngày trước, cấu hình sâu sau.
// SwiftUI không có API công khai để nhúng Control Center của macOS,
// vì vậy layout này giữ control và material hệ thống nhưng không sao chép UI hệ thống.
// ============================================================
struct MonitorPopoverView: View {
    @ObservedObject var model: MonitorModel
    @ObservedObject private var controller = sharedBrightness
    @State private var page = "overview"
    @State private var editIP = ""
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var samsungReady: Bool {
        model.isConnected && !model.isLoading && !model.isPairing && !model.isPowerBusy && !model.isRefreshingSharpness
    }
    private var ddc: [DDCDisplay] { controller.displays.filter { $0.brightness != nil || $0.volume != nil } }
    private var panelHeight: CGFloat {
        switch page {
        case "overview": return 326
        case "display": return min(570, 218 + CGFloat(ddc.count + controller.disconnected.count) * 72)
        case "audio": return min(570, 174 + CGFloat(ddc.filter { $0.volume != nil }.count) * 76)
        case "remote": return 350
        case "picture": return 492
        default: return 480
        }
    }
    private var effectID: String { page == "audio" ? "audio" : "display" }

    var body: some View {
        CCGlassContainer {
            if page == "overview" { overview }
            else {
                detail.id(page)
                    .modifier(CCGlass(radius: 26, interactive: false))
                    .modifier(MenuGlassIdentity(id: effectID, namespace: glass))
            }
        }
        .padding(24)
        .frame(width: 348, height: panelHeight + 48, alignment: .top)
        .preferredColorScheme(.dark)
        .onAppear { editIP = model.monitorIP; resizePanel() }
        .onChange(of: page) { _ in resizePanel() }
        .onChange(of: controller.displays.count) { _ in resizePanel() }
        .onChange(of: controller.disconnected.count) { _ in resizePanel() }
        .onDisappear { model.remoteTabActive = false }
    }

    private var overview: some View {
        VStack(spacing: 12) {
            overviewModule("Màn hình", id: "display", low: "sun.min.fill", high: "sun.max.fill", value: groupValue(volume: false), enabled: samsungReady || ddc.contains { $0.brightness != nil }) { setGroup($0, volume: false) }
            overviewModule("Âm thanh", id: "audio", low: "speaker.fill", high: "speaker.wave.3.fill", value: groupValue(volume: true), enabled: samsungReady || ddc.contains { $0.volume != nil }) { setGroup($0, volume: true) }
            HStack(spacing: 12) {
                shortcut("Remote", symbol: "av.remote.fill", enabled: samsungReady) { navigate("remote") }
                shortcut("Áp lại nét", symbol: "arrow.clockwise", enabled: samsungReady && !model.isSharpnessSetting && !model.isPictureModeBusy) { model.refreshSharpness() }
                shortcut("Tắt S9", symbol: "power", enabled: samsungReady) { model.setPower("off") }
            }
            HStack(spacing: 12) {
                Button { navigate("settings") } label: {
                    Label("Cài đặt", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(RoundedRectangle(cornerRadius: 19))
                        .modifier(CCGlass(radius: 19, interactive: true))
                }.buttonStyle(.plain)
                Menu {
                    Button("Làm mới") { controller.refresh(); model.fetchAllStates() }
                    if !model.statusMessage.isEmpty { Text(model.statusMessage) }
                    if !controller.message.isEmpty { Text(controller.message) }
                    Divider()
                    Button("Thoát") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 38)
                        .modifier(CCGlass(radius: 19, interactive: true))
                }
                .menuStyle(.button).buttonStyle(.plain).fixedSize()
            }
            .font(.system(size: 12))
        }
    }

    private func overviewModule(_ title: String, id: String, low: String, high: String, value: Double, enabled: Bool, action: @escaping (Double) -> Void) -> some View {
        ZStack {
            Button { navigate(id) } label: {
                Color.clear.contentShape(RoundedRectangle(cornerRadius: 24))
            }.buttonStyle(.plain).accessibilityLabel("Mở \(title)")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }.allowsHitTesting(false)
            ControlCenterSlider(symbol: low, trailingSymbol: high, value: value, range: 0...100, action: action, accessibilityName: "\(title), đồng bộ các màn hình")
                .disabled(!enabled)
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(height: 72)
        .modifier(CCGlass(radius: 24, interactive: false))
        .modifier(MenuGlassIdentity(id: id, namespace: glass))
    }

    private func shortcut(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium)).frame(width: 52, height: 46)
                Text(title).font(.system(size: 10, weight: .semibold))
            }.frame(maxWidth: .infinity).padding(.vertical, 7)
                .modifier(CCGlass(radius: 25, interactive: true))
        }.buttonStyle(.plain).disabled(!enabled).help("\(title) · Samsung S9").accessibilityLabel("\(title), Samsung S9")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { navigate("overview") } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain).help("Quay lại").accessibilityLabel("Quay lại")
                Menu {
                    Button("Màn hình") { navigate("display") }
                    Button("Âm thanh") { navigate("audio") }
                    Divider()
                    Button("Samsung · Hình ảnh") { navigate("picture") }
                    Button("Samsung · Remote") { navigate("remote") }
                    Button("Cài đặt") { navigate("settings") }
                } label: { Text(pageTitle).font(.system(size: 14, weight: .semibold)) }
                .menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Button { controller.refresh(); model.fetchAllStates() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Làm mới")
                    .disabled(controller.scanning || model.isLoading || model.isPowerBusy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if page == "display" { displayDetail }
                    if page == "audio" { audioDetail }
                    if page == "picture" { pictureDetail }
                    if page == "remote" { remoteDetail }
                    if page == "settings" { settingsDetail }
                }.padding(.horizontal, 2).padding(.vertical, 2)
            }
            if !controller.message.isEmpty || !model.statusMessage.isEmpty {
                DisclosureGroup("Thông báo") {
                    Text(!controller.message.isEmpty ? controller.message : model.statusMessage)
                        .font(.caption).textSelection(.enabled)
                }.font(.caption)
            }
        }.padding(16)
    }

    private var pageTitle: String {
        switch page {
        case "display": return "Màn hình"
        case "audio": return "Âm thanh"
        case "picture": return "Samsung · Hình ảnh"
        case "remote": return "Samsung · Remote"
        default: return "Cài đặt"
        }
    }

    private var displayDetail: some View {
        Group {
            VStack(alignment: .leading, spacing: 10) {
                Button { navigate("picture") } label: {
                    HStack { Text("Samsung ViewFinity S9").font(.headline); Spacer(); Image(systemName: "chevron.right") }
                }.buttonStyle(.plain)
                ControlCenterSlider(symbol: "sun.min.fill", trailingSymbol: "sun.max.fill", value: model.brightness, range: 0...50, action: model.setBrightness, accessibilityName: "Độ sáng Samsung")
                    .disabled(!samsungReady)
            }
            ForEach(ddc.filter { $0.brightness != nil }) { display in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(display.name).font(.headline)
                        Spacer()
                        Menu {
                            Button("Ngắt kết nối") { controller.setConnected(false, uuid: display.id, name: display.name) }
                        } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                    }
                    ControlCenterSlider(symbol: "sun.min.fill", trailingSymbol: "sun.max.fill", value: display.brightness ?? 0, range: 0...(display.maximum ?? 100), action: { controller.setBrightness($0, for: display.id) }, accessibilityName: "Độ sáng \(display.name)")
                }
            }
            reconnectRows
            Divider()
            Button("Cài đặt màn hình…") { navigate("settings") }.buttonStyle(.plain)
        }
    }

    private var audioDetail: some View {
        Group {
            ControlCenterDetailSlider(title: "Samsung ViewFinity S9", value: model.volume, range: 0...100, action: model.setVolume).disabled(!samsungReady)
            ForEach(ddc.filter { $0.volume != nil }) { display in
                ControlCenterDetailSlider(title: display.name, value: display.volume ?? 0, range: 0...(display.maximumVolume ?? 100), action: { controller.setVolume($0, for: display.id) })
            }
            DisclosureGroup("Âm thanh Samsung") {
                VStack(spacing: 12) {
                    Toggle("Tắt tiếng", isOn: Binding(get: { model.isMuted }, set: { _ in model.toggleMute() }))
                    Picker("Đầu ra", selection: Binding(get: { model.speakerSelect }, set: model.setSpeakerSelect)) {
                        Text("Loa màn hình").tag("Internal"); Text("Thiết bị ngoài").tag("Receiver")
                    }
                    Picker("Chế độ", selection: Binding(get: { model.soundMode }, set: model.setSoundMode)) {
                        ForEach(["Standard", "Game", "Music", "Movie", "Amplify", "Adaptive", "Optimized"], id: \.self) { Text($0).tag($0) }
                    }
                }.padding(.top, 8).disabled(!samsungReady)
            }.font(.caption)
        }
    }

    private var pictureDetail: some View {
        Group {
            Picker("Không gian màu", selection: Binding(get: { pictureSelection }, set: model.setPictureMode)) {
                Text("sRGB").tag("srgb"); Text("DCI-P3").tag("dci-p3"); Text("BT.709").tag("bt709")
                Text("Giải trí").tag("entertainment"); Text("Standard").tag("standard")
                Text("DICOM").tag("dicom"); Text("Custom").tag("custom")
                if pictureSelection == "unknown" { Text(model.pictureMode).tag("unknown") }
            }.disabled(!samsungReady || model.isPictureModeBusy)
            Picker("Game Mode", selection: Binding(get: { model.gameMode }, set: model.setGameMode)) {
                Text("Tắt").tag("Off"); Text("Bật").tag("On"); Text("Tự động").tag("Auto")
            }.disabled(!samsungReady)
            ControlCenterDetailSlider(title: "Độ đậm màu", value: model.color, range: 0...50, action: model.setColor).disabled(!samsungReady)
            ControlCenterDetailSlider(title: "Tương phản", value: model.contrast, range: 0...50, action: model.setContrast).disabled(!samsungReady)
            ControlCenterDetailSlider(title: "Độ nét", value: model.sharpness, range: 0...20, action: model.setSharpness).disabled(!samsungReady)
            Button { model.refreshSharpness() } label: { Label(model.isRefreshingSharpness ? "Đang áp lại nét…" : "Áp lại độ nét", systemImage: "arrow.clockwise") }
                .disabled(!samsungReady || model.isSharpnessSetting || model.isPictureModeBusy)
            DisclosureGroup("Tinh chỉnh màu") {
                VStack(spacing: 14) {
                    ControlCenterDetailSlider(title: "Sắc thái G/R", value: model.tint, range: -15...15, action: model.setTint)
                    ControlCenterDetailSlider(title: "Mức điểm đen", value: model.blackLevel, range: -5...5, action: model.setBlackLevel)
                }.padding(.top, 10).disabled(!samsungReady)
            }
        }
    }

    private var remoteDetail: some View {
        VStack(spacing: 12) {
            remoteButton("Lên", symbol: "chevron.up", key: "cursorUp")
            HStack {
                remoteButton("Trái", symbol: "chevron.left", key: "cursorLeft")
                remoteButton("OK", symbol: "checkmark", key: "enter")
                remoteButton("Phải", symbol: "chevron.right", key: "cursorRight")
            }
            remoteButton("Xuống", symbol: "chevron.down", key: "cursorDn")
            HStack {
                remoteButton("Quay lại", symbol: "arrow.uturn.backward", key: "return")
                remoteButton("Home", symbol: "house", key: "firstScreen")
                remoteButton("Menu", symbol: "gearshape", key: "menu")
            }
            Toggle("Dùng bàn phím cho remote", isOn: Binding(get: { model.remoteKeyboardEnabled }, set: {
                model.remoteKeyboardEnabled = $0; model.remoteTabActive = $0
            }))
            Text("↑ ↓ ← → · Enter chọn · Esc quay lại · M Menu · H Home · 0–9")
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(!samsungReady)
    }

    private var settingsDetail: some View {
        Group {
            Toggle("Phím độ sáng & âm lượng", isOn: Binding(get: { controller.keysRequested }, set: {
                if $0 { controller.enableKeys() } else { controller.disableKeys() }
            }))
            Text("F1/F2 và F10–F12 điều khiển màn hình dưới con trỏ.")
                .font(.caption).foregroundStyle(.secondary)
            if controller.keysRequested && !controller.keysEnabled {
                Text("Phím tắt chưa sẵn sàng. Kiểm tra quyền Trợ năng cho bản app hiện tại.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Mở Trợ năng…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Button(controller.scanning ? "Đang quét…" : "Quét lại màn hình") { controller.refresh(); model.fetchAllStates() }.disabled(controller.scanning)
            reconnectRows
            DisclosureGroup("Kết nối Samsung") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Địa chỉ IP", text: $editIP).textFieldStyle(.roundedBorder).onSubmit { pair() }
                    Button(model.isPairing ? "Đang ghép nối…" : "Lưu & ghép nối") { pair() }.disabled(model.isPairing || model.isLoading)
                    Picker("Nguồn vào", selection: Binding(get: { model.inputSource }, set: model.setInputSource)) {
                        Text("USB-C").tag("USB-C"); Text("Mini-DisplayPort").tag("Mini-DP")
                    }.disabled(!samsungReady)
                    DisclosureGroup("Thiết bị USB trên Mac (\(model.peripherals.count))") {
                        ForEach(model.peripherals) { Text($0.name).font(.caption) }
                    }
                }.padding(.top, 10)
            }
            DisclosureGroup("Trạng thái DDC") {
                ForEach(controller.displays) { display in
                    Text("\(display.name): \(display.error ?? "Đã kết nối")").font(.caption)
                }
            }
        }
    }

    private var reconnectRows: some View {
        ForEach(controller.disconnected.keys.sorted(), id: \.self) { id in
            Button("Kết nối lại \(controller.disconnected[id] ?? "màn hình")") {
                controller.setConnected(true, uuid: id, name: controller.disconnected[id] ?? "Màn hình")
            }
        }
    }

    private func groupValue(volume: Bool) -> Double {
        var values = ddc.compactMap { display -> Double? in
            guard let current = volume ? display.volume : display.brightness,
                  let maximum = volume ? display.maximumVolume : display.maximum, maximum > 0 else { return nil }
            return current / maximum * 100
        }
        if model.isConnected { values.append(volume ? model.volume : model.brightness * 2) }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
    private func setGroup(_ percent: Double, volume: Bool) {
        if samsungReady {
            if volume { model.setVolume(to: percent) } else { model.setBrightness(to: (percent / 2).rounded()) }
        }
        for display in ddc {
            if let maximum = volume ? display.maximumVolume : display.maximum {
                if volume { controller.setVolume(percent * maximum / 100, for: display.id) }
                else { controller.setBrightness(percent * maximum / 100, for: display.id) }
            }
        }
    }
    private var pictureSelection: String {
        let value = model.pictureMode.lowercased()
        for (text, code, tag) in [("srgb", "327712", "srgb"), ("p3", "327714", "dci-p3"), ("709", "327713", "bt709"), ("entertainment", "65541", "entertainment"), ("standard", "458753", "standard"), ("dicom", "327715", "dicom"), ("custom", "327716", "custom")] {
            if value.contains(text) || value.contains(code) { return tag }
        }
        return "unknown"
    }
    private func remoteButton(_ title: String, symbol: String, key: String) -> some View {
        Button { model.sendKey(key); model.flashKey(key, label: title) } label: { Label(title, systemImage: symbol) }
            .accessibilityLabel(title)
    }
    private func pair() {
        let host = editIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !model.isPairing, !model.isLoading else { return }
        model.pairMonitor(targetHost: host)
    }
    private func navigate(_ destination: String) {
        model.remoteTabActive = model.remoteKeyboardEnabled
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) { page = destination }
    }
    private func resizePanel() {
        guard let panel = NSApp.windows.first(where: { $0 is ControlCenterPanel }) as? ControlCenterPanel else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - (panelHeight + 48)
        frame.size = NSSize(width: 348, height: panelHeight + 48)
        // Glass owns the geometry transition; a second NSWindow resize animation
        // leaves an independent window silhouette behind the glass surface.
        panel.setFrame(frame, display: true, animate: false)
        panel.positionAtAnchor()
        panel.invalidateShadow()
    }
}

struct ControlCenterSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.28), lineWidth: 0.8))
    }
}

struct CCGlassContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { content }
        } else { content }
    }
}

struct CCGlass: ViewModifier {
    let radius: CGFloat
    let interactive: Bool
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .foregroundStyle(.white)
                .blendMode(.plusLighter)
                .glassEffect(PrivateControlCenterGlass.material.tint(.black.opacity(0.10)).interactive(interactive), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .environment(\.colorScheme, .dark)
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .environment(\.colorScheme, .dark)
        }
    }
}

struct MenuGlassIdentity: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffectID(id, in: namespace).glassEffectTransition(.matchedGeometry)
        } else { content }
    }
}

struct ControlCenterTileStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(tint)
            .background(tint.opacity(configuration.isPressed ? 0.20 : 0.11), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 0.8))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct ControlCenterPresetStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundColor(selected ? .white : .primary)
            .background(selected ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09), in: Capsule())
    }
}

struct ControlCenterFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09), in: Capsule())
            .contentShape(Capsule())
    }
}

struct ControlCenterIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.09), in: Circle())
            .contentShape(Circle())
    }
}

struct ControlCenterSlider: View {
    let symbol: String
    let trailingSymbol: String
    let value: Double
    let range: ClosedRange<Double>
    let action: (Double) -> Void
    let accessibilityName: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            CCNativeSlider(value: value, range: range, label: accessibilityName, action: action)
                .frame(height: 24)
            Image(systemName: trailingSymbol).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(Int(value)), từ \(Int(range.lowerBound)) đến \(Int(range.upperBound))")
    }
}

final class CCSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let track = NSRect(x: rect.minX, y: rect.midY - 2, width: rect.width, height: 4)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        let fraction = (doubleValue - minValue) / max(1, maxValue - minValue)
        let filled = NSRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        if #available(macOS 26.0, *), isHighlighted { return }
        NSColor.white.setFill()
        let knob = NSRect(x: knobRect.midX - 9, y: knobRect.midY - 7, width: 18, height: 14)
        NSBezierPath(roundedRect: knob, xRadius: 7, yRadius: 7).fill()
    }
}

final class CCGlassSlider: NSSlider {
    private var glassThumb: NSView?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        if #available(macOS 26.0, *) {
            let thumb = NSGlassEffectView()
            // The control-center thumb is a light lens even on a dark widget.
            // Isolate its appearance from the dark panel; inheriting Dark Aqua
            // turns regular glass into an opaque-looking charcoal capsule.
            thumb.appearance = NSAppearance(named: .aqua)
            thumb.cornerRadius = 10
            thumb.effectIsInteractive = true
            thumb.style = .regular
            thumb.isHidden = true
            addSubview(thumb)
            glassThumb = thumb
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func mouseDown(with event: NSEvent) {
        glassThumb?.isHidden = false
        needsLayout = true
        super.mouseDown(with: event)
        glassThumb?.isHidden = true
        needsDisplay = true
    }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func layout() {
        super.layout()
        let fraction = (doubleValue - minValue) / max(1, maxValue - minValue)
        let width: CGFloat = 24
        glassThumb?.frame = NSRect(x: (bounds.width - width) * fraction, y: bounds.midY - 10, width: width, height: 20)
    }
    override func draw(_ dirtyRect: NSRect) { super.draw(dirtyRect); needsLayout = true }
}

struct CCNativeSlider: NSViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let label: String
    let action: (Double) -> Void
    @Environment(\.isEnabled) private var isEnabled
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = CCGlassSlider()
        slider.appearance = NSAppearance(named: .darkAqua)
        slider.cell = CCSliderCell()
        slider.focusRingType = .none
        slider.isContinuous = true
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.isEnabled = isEnabled
        slider.needsLayout = true
        context.coordinator.action = action
    }
    final class Coordinator: NSObject {
        var action: (Double) -> Void
        init(action: @escaping (Double) -> Void) { self.action = action }
        @objc func changed(_ slider: NSSlider) { action(slider.doubleValue.rounded()) }
    }
}

struct ControlCenterDetailSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let action: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) / \(Int(range.upperBound))").monospacedDigit().foregroundColor(.secondary)
            }
            CCNativeSlider(value: value, range: range, label: title, action: action)
                .frame(height: 28)
        }
    }
}

final class ControlCenterPanel: NSPanel {
    private weak var anchorView: NSView?
    private var anchorRect = NSRect.zero
    var isShown: Bool { isVisible }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 518), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        // Each glass surface renders its own shadow. A window shadow outlines
        // transparent space and produces a second border around detail menus.
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    var contentSize: NSSize {
        get { contentView?.frame.size ?? .zero }
        set { setContentSize(newValue) }
    }
    var animates = true
    var behavior: NSPopover.Behavior = .transient
    func show(relativeTo rect: NSRect, of view: NSView, preferredEdge: NSRectEdge) {
        anchorView = view
        anchorRect = rect
        contentView?.layoutSubtreeIfNeeded()
        positionAtAnchor()
        orderFrontRegardless()
    }
    func positionAtAnchor() {
        guard let view = anchorView else { return }
        guard let window = view.window else { return }
        let anchor = window.convertToScreen(view.convert(anchorRect, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) }) ?? window.screen else { return }
        let visible = screen.visibleFrame
        // Anchor visible glass, excluding the transparent 24pt shadow margin.
        let inset: CGFloat = 24
        let contentWidth = frame.width - inset * 2
        let contentRight = min(max(anchor.maxX, visible.minX + contentWidth + 8), visible.maxX - 8)
        setFrameOrigin(NSPoint(x: contentRight - frame.width + inset,
                               y: max(visible.minY - inset, anchor.minY - 6 - frame.height + inset)))
        if CommandLine.arguments.contains("--qc") {
            print("QC_ANCHOR_GAP=\(anchor.minY - (frame.maxY - inset)) QC_GLASS_RIGHT=\(frame.maxX - inset) QC_ICON_RIGHT=\(anchor.maxX)")
            fflush(stdout)
        }
    }
    override func performClose(_ sender: Any?) { orderOut(sender) }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: ControlCenterPanel!
    var mouseEventMonitor: Any?
    var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .notRegistered || SMAppService.mainApp.status == .notFound {
                    try SMAppService.mainApp.register()
                }
                if SMAppService.mainApp.status == .requiresApproval {
                    sharedBrightness.message = "Cho phép Samsung Monitor Control trong Mục đăng nhập để tự khôi phục màn hình sau restart."
                }
            } catch {
                sharedBrightness.message = "Chưa bật được chạy khi đăng nhập: \(error.localizedDescription)"
                NSLog("Login item registration failed: %@", error.localizedDescription)
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Samsung Monitor Control")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = ControlCenterPanel()
        popover.animates = false
        popover.contentSize = NSSize(width: 320, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MonitorPopoverView(model: sharedModel))
        popover.contentView?.appearance = NSAppearance(named: .darkAqua)
        sharedBrightness.samsungAction = { sharedModel.setBrightness(to: $0) }
        sharedBrightness.samsungValue = { sharedModel.brightness }
        sharedBrightness.samsungAvailable = { sharedModel.isConnected && !sharedModel.isPowerBusy && !sharedModel.isLoading }
        sharedBrightness.samsungVolume = { sharedModel.volume }
        sharedBrightness.samsungVolumeAction = { sharedModel.setVolume(to: $0) }
        sharedBrightness.samsungMute = { sharedModel.toggleMute() }
        if UserDefaults.standard.bool(forKey: "brightnessKeysEnabled") { sharedBrightness.enableKeys(prompt: false) }
        if CommandLine.arguments.contains("--qc-keys") {
            sharedBrightness.enableKeys(prompt: false)
            print("KEYS_TRUSTED=\(AXIsProcessTrusted()) KEYS_ENABLED=\(sharedBrightness.keysEnabled)")
            if #available(macOS 13.0, *) { print("LOGIN_ITEM_STATUS=\(SMAppService.mainApp.status.rawValue)") }
            fflush(stdout)
        }
        if CommandLine.arguments.contains("--qc") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.togglePopover()
                if let window = self.popover.contentViewController?.view.window {
                    print("QC_WINDOW_ID=\(window.windowNumber)")
                    fflush(stdout)
                }
            }
        }

        // Monitor click outside to close popover
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.popover.performClose(nil)
            }
        }

        // Local monitor for Mac keyboard when app/popover is active
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.popover.isShown, sharedModel.remoteTabActive, sharedModel.remoteKeyboardEnabled, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }

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

    }

    func dispatchKey(_ keyCode: UInt16) -> Bool {
        guard sharedModel.remoteTabActive, sharedModel.remoteKeyboardEnabled, sharedModel.isConnected, !sharedModel.isLoading, !sharedModel.isPairing, !sharedModel.isPowerBusy, !sharedModel.isRefreshingSharpness else { return false }
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
            sharedModel.remoteTabActive = sharedModel.remoteKeyboardEnabled
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
