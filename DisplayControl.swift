import Cocoa
import ApplicationServices

struct DDCDisplay: Identifiable {
    let id: String
    let name: String
    var brightness: Double?
    var maximum: Double?
    var error: String?
    var volume: Double? = nil
    var maximumVolume: Double? = nil
}

enum DDCOutput {
    static func displays(_ output: String) -> [(id: String, name: String)] {
        let pattern = #"^\[\d+\] (.+) \(([A-Fa-f0-9-]{36})\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else { return [] }
        let string = output as NSString
        return regex.matches(in: output, range: NSRange(location: 0, length: string.length)).map {
            (string.substring(with: $0.range(at: 2)), string.substring(with: $0.range(at: 1)))
        }
    }
    static func number(_ output: String) -> Double? {
        guard let number = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite, number >= 0 else { return nil }
        return number
    }
}

final class DisplayBrightnessController: ObservableObject {
    @Published var displays: [DDCDisplay] = []
    @Published var scanning = false
    @Published var message = ""
    @Published var disconnected = UserDefaults.standard.dictionary(forKey: "disconnectedDisplays") as? [String: String] ?? [:]
    @Published var selectedID: String = UserDefaults.standard.string(forKey: "brightnessTarget") ?? "samsung" {
        didSet { UserDefaults.standard.set(selectedID, forKey: "brightnessTarget") }
    }
    @Published var keysEnabled = false
    @Published var keysRequested = UserDefaults.standard.bool(forKey: "brightnessKeysEnabled")
    private let queue = DispatchQueue(label: "com.hieutran.monitor.ddc", qos: .userInitiated)
    private var pendingWrites: [String: DispatchWorkItem] = [:]
    private var eventTap: CFMachPort?
    private var eventSource: CFRunLoopSource?
    private var screenObserver: NSObjectProtocol?
    private var permissionTimer: Timer?
    private var didPromptForKeys = false
    private var connectionChanges = Set<String>()
    private var recoveryPending = Set<String>()

    private func identity(_ id: UInt32) -> [String: UInt32] {
        ["vendor": CGDisplayVendorNumber(id), "model": CGDisplayModelNumber(id), "serial": CGDisplaySerialNumber(id)]
    }

    private func rememberIdentity(_ id: UInt32, uuid: String) {
        UserDefaults.standard.set(identity(id), forKey: "displayIdentity.\(uuid)")
    }

    private func recoverDisconnected() {
        for uuid in recoveryPending where !connectionChanges.contains(uuid) {
            guard let name = disconnected[uuid] else { recoveryPending.remove(uuid); continue }
            setConnected(true, uuid: uuid, name: name)
        }
    }
    var samsungAction: ((Double) -> Void)?
    var samsungValue: (() -> Double)?
    var samsungAvailable: (() -> Bool)?
    var samsungVolume: (() -> Double)?
    var samsungVolumeAction: ((Double) -> Void)?
    var samsungMute: (() -> Void)?

    func targetAtPointer() -> String? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        let id = CFUUIDCreateString(nil, uuid) as String
        if CGDisplayVendorNumber(number.uint32Value) == 19501 && CGDisplayModelNumber(number.uint32Value) == 29589 { return "samsung" }
        return displays.contains(where: { $0.id == id }) ? id : nil
    }

    // Prototypes corroborated by MacDisplay / DisplayDeck; resolved dynamically.
    // This is a private macOS API, so absence is an ordinary unsupported result.
    func setConnected(_ connected: Bool, uuid: String, name: String) {
        guard !connectionChanges.contains(uuid) else { return }
        typealias List = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> CGError
        typealias Enable = @convention(c) (CGDisplayConfigRef?, UInt32, Bool) -> CGError
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let listSymbol = dlsym(handle, "CGSGetDisplayList"),
              let enableSymbol = dlsym(handle, "CGSConfigureDisplayEnabled") else {
            message = "macOS hiện tại không hỗ trợ ngắt/kết nối màn hình bằng app."
            return
        }
        defer { dlclose(handle) }
        let list = unsafeBitCast(listSymbol, to: List.self)
        let enable = unsafeBitCast(enableSymbol, to: Enable.self)
        var ids = [UInt32](repeating: 0, count: 64)
        var count: UInt32 = 0
        guard list(64, &ids, &count) == .success else { message = "Không đọc được danh sách màn hình."; return }
        let current = Array(ids.prefix(Int(count)))
        let exact = current.first(where: { id in
            guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return false }
            return (CFUUIDCreateString(nil, value) as String) == uuid
        })
        // A disabled display remains in CGSGetDisplayList, but loses its UUID.
        // Hardware metadata survives; only use an unambiguous match, never a stale display ID.
        let saved = UserDefaults.standard.dictionary(forKey: "displayIdentity.\(uuid)") as? [String: UInt32]
        let matches = current.filter { saved != nil && identity($0) == saved! && CGDisplayVendorNumber($0) != 0 }
        guard let target = exact ?? (connected && matches.count == 1 ? matches[0] : nil) else {
            message = "Không nhận diện được \(name). Giữ cáp cắm và bật nguồn để thử lại."
            return
        }
        rememberIdentity(target, uuid: uuid)
        guard connected || current.contains(where: { $0 != target && CGDisplayIsActive($0) != 0 }) else {
            message = "Không thể ngắt màn hình đang hoạt động cuối cùng."
            return
        }
        // Persist recovery before changing WindowServer state, including if the app exits mid-transaction.
        if !connected {
            disconnected[uuid] = name
            UserDefaults.standard.set(disconnected, forKey: "disconnectedDisplays")
        }
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success, let configuration else { message = "Không bắt đầu được thay đổi màn hình."; return }
        guard enable(configuration, target, connected) == .success else {
            CGCancelDisplayConfiguration(configuration)
            message = "macOS từ chối thay đổi kết nối màn hình."
            return
        }
        guard CGCompleteDisplayConfiguration(configuration, .forSession) == .success else { message = "Không áp dụng được thay đổi kết nối."; return }
        connectionChanges.insert(uuid)
        message = connected ? "Đang kết nối lại \(name)…" : "Đang ngắt \(name)…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.connectionChanges.remove(uuid)
            let actualUUID = CGDisplayCreateUUIDFromDisplayID(target).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            let active = CGDisplayIsActive(target) != 0 && actualUUID == uuid
            if connected && active {
                self.disconnected.removeValue(forKey: uuid)
                self.recoveryPending.remove(uuid)
                UserDefaults.standard.set(self.disconnected, forKey: "disconnectedDisplays")
                self.message = "Đã kết nối lại \(name)."
            } else if !connected && CGDisplayIsActive(target) == 0 {
                self.message = "Đã ngắt \(name). App sẽ tự kết nối lại khi khởi chạy lần sau."
            } else {
                self.message = "macOS chưa xác nhận thay đổi kết nối \(name). Bấm Kết nối lại để thử lại."
            }
            self.refresh()
        }
    }

    init() {
        var online = [UInt32](repeating: 0, count: 64)
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(64, &online, &count) == .success {
            for id in online.prefix(Int(count)) {
                if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                    rememberIdentity(id, uuid: CFUUIDCreateString(nil, uuid) as String)
                }
            }
        }
        recoveryPending = Set(disconnected.keys)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        for delay in [1.0, 4, 10, 25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.recoverDisconnected() }
        }
        refresh()
    }

    var selectedDisplay: DDCDisplay? { displays.first { $0.id == selectedID } }
    var targetAvailable: Bool {
        selectedID == "samsung" ? (samsungAvailable?() ?? false) : selectedDisplay?.brightness != nil
    }
    var targetName: String { selectedID == "samsung" ? "Samsung S9 · Mạng" : selectedDisplay?.name ?? "Màn hình đã ngắt kết nối" }

    private func command(_ args: [String]) -> String {
        let executable = Bundle.main.url(forResource: "m1ddc", withExtension: nil)
            ?? URL(fileURLWithPath: "/Volumes/My Data/Development/samsung-monitor-control/vendor/m1ddc/m1ddc")
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            // Output is tiny; drain before waiting so neither pipe can deadlock.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch { return error.localizedDescription }
    }

    func refresh() {
        guard !scanning else { return }
        scanning = true
        queue.async { [weak self] in
            guard let self else { return }
            let listed = DDCOutput.displays(self.command(["display", "list"]))
            let result = listed.map { display -> DDCDisplay in
                let current = DDCOutput.number(self.command(["display", display.id, "get", "luminance"]))
                let maximum = current == nil ? nil : DDCOutput.number(self.command(["display", display.id, "max", "luminance"]))
                let valid = current != nil && maximum != nil && maximum! > 0 && current! <= maximum!
                let volume = DDCOutput.number(self.command(["display", display.id, "get", "volume"]))
                let maxVolume = volume == nil ? nil : DDCOutput.number(self.command(["display", display.id, "max", "volume"]))
                return DDCDisplay(id: display.id, name: display.name, brightness: valid ? current : nil, maximum: valid ? maximum : nil, error: valid ? nil : "Không đọc được DDC/CI. Kiểm tra DDC trong menu màn hình, cáp hoặc adapter.", volume: (maxVolume ?? 0) > 0 ? volume : nil, maximumVolume: (maxVolume ?? 0) > 0 ? maxVolume : nil)
            }
            DispatchQueue.main.async {
                self.displays = result
                self.scanning = false
            }
        }
    }

    func setBrightness(_ value: Double, for id: String) {
        guard let index = displays.firstIndex(where: { $0.id == id }), let maximum = displays[index].maximum else { return }
        let target = min(maximum, max(0, value.rounded()))
        displays[index].brightness = target
        pendingWrites[id]?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let write = self.command(["display", id, "set", "luminance", String(Int(target))])
            let readback = DDCOutput.number(self.command(["display", id, "get", "luminance"]))
            DispatchQueue.main.async {
                guard let index = self.displays.firstIndex(where: { $0.id == id }) else { return }
                if let readback {
                    self.displays[index].brightness = readback
                    self.message = readback == target ? "" : "Màn hình chưa xác nhận độ sáng \(Int(target)). Đã đọc: \(Int(readback))."
                } else {
                    self.displays[index].brightness = nil
                    self.displays[index].error = "Mất kết nối DDC. Bấm Quét lại để thử."
                    self.message = write.isEmpty ? "Không đọc lại được độ sáng DDC." : write
                }
            }
        }
        pendingWrites[id] = task
        queue.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    func changeBrightness(direction: Double) {
        guard let target = targetAtPointer() else { return }
        if target == "samsung", samsungAvailable?() == true {
            let value = min(50, max(0, (samsungValue?() ?? 0) + direction * 3))
            samsungAction?(value)
        } else if let display = displays.first(where: { $0.id == target }), let value = display.brightness, let maximum = display.maximum {
            setBrightness(value + direction * max(1, (maximum / 16).rounded()), for: display.id)
        }
    }

    func setVolume(_ value: Double, for id: String) {
        guard let index = displays.firstIndex(where: { $0.id == id }), let maximum = displays[index].maximumVolume else { return }
        let target = min(maximum, max(0, value.rounded()))
        displays[index].volume = target
        let key = "volume:\(id)"
        pendingWrites[key]?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = self.command(["display", id, "set", "volume", String(Int(target))])
            let actual = DDCOutput.number(self.command(["display", id, "get", "volume"]))
            DispatchQueue.main.async {
                if let index = self.displays.firstIndex(where: { $0.id == id }) {
                    self.displays[index].volume = actual
                    if actual != target { self.message = "Chưa xác nhận được âm lượng \(Int(target))." }
                }
            }
        }
        pendingWrites[key] = task
        queue.asyncAfter(deadline: .now() + 0.15, execute: task)
    }

    func changeVolume(direction: Double, mute: Bool = false) {
        guard let target = targetAtPointer() else { return }
        if target == "samsung", samsungAvailable?() == true {
            if mute { samsungMute?() }
            else { samsungVolumeAction?(min(100, max(0, (samsungVolume?() ?? 0) + direction * 6))) }
        } else if let display = displays.first(where: { $0.id == target }), let volume = display.volume, let maximum = display.maximumVolume {
            setVolume(mute ? (volume == 0 ? maximum / 4 : 0) : volume + direction * max(1, (maximum / 16).rounded()), for: target)
        }
    }

    func enableKeys(prompt: Bool = true) {
        keysRequested = true
        UserDefaults.standard.set(true, forKey: "brightnessKeysEnabled")
        guard eventTap == nil else { keysEnabled = true; return }
        let shouldPrompt = prompt && !didPromptForKeys
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: shouldPrompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            if shouldPrompt { didPromptForKeys = true }
            message = "Đang chờ quyền Trợ năng. App sẽ tự bật phím khi macOS xác nhận quyền."
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    if AXIsProcessTrusted() { self.enableKeys(prompt: false) }
                }
            }
            return
        }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << 14)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let owner = Unmanaged<DisplayBrightnessController>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = owner.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard owner.keysEnabled, let target = owner.targetAtPointer(),
                  event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else { return Unmanaged.passUnretained(event) }
            var direction: Double?
            var volumeKey = false
            var muteKey = false
            if type == .keyDown {
                let key = event.getIntegerValueField(.keyboardEventKeycode)
                if key == 122 { direction = -1 }
                if key == 120 { direction = 1 }
                if key == 103 { direction = 0; volumeKey = true; muteKey = true }
                if key == 111 { direction = -1; volumeKey = true }
                if key == 113 { direction = 1; volumeKey = true }
            } else if type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
                let key = (nsEvent.data1 >> 16) & 0xffff
                let state = (nsEvent.data1 >> 8) & 0xff
                if (key == 2 || key == 3), state == 0x0a { direction = key == 2 ? 1 : -1 }
                else if key == 2 || key == 3 { return nil }
                if [0, 1, 7].contains(key) {
                    volumeKey = true
                    muteKey = key == 7
                    if state == 0x0a { direction = key == 0 ? 1 : -1 }
                    else { return nil }
                }
            }
            guard let direction else { return Unmanaged.passUnretained(event) }
            let display = owner.displays.first { $0.id == target }
            guard target == "samsung" ? owner.samsungAvailable?() == true : (volumeKey ? display?.volume != nil : display?.brightness != nil) else { return Unmanaged.passUnretained(event) }
            // The tap is scheduled on the main run loop, like the observable model.
            if volumeKey { owner.changeVolume(direction: direction, mute: muteKey) }
            else { owner.changeBrightness(direction: direction) }
            return nil
        }, userInfo: pointer)
        guard let eventTap else {
            message = "Trợ năng đã được cấp nhưng macOS chưa cho tạo bộ bắt phím. App sẽ thử lại tự động."
            if permissionTimer == nil {
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.enableKeys(prompt: false) }
            }
            return
        }
        eventSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), eventSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        keysEnabled = true
        permissionTimer?.invalidate()
        permissionTimer = nil
        UserDefaults.standard.set(true, forKey: "brightnessKeysEnabled")
        message = "F1/F2: độ sáng · F10–F12: âm lượng. Điều khiển màn hình dưới con trỏ."
    }

    func disableKeys() {
        keysRequested = false
        permissionTimer?.invalidate()
        permissionTimer = nil
        keysEnabled = false
        UserDefaults.standard.set(false, forKey: "brightnessKeysEnabled")
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false); CFMachPortInvalidate(eventTap) }
        if let eventSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventSource, .commonModes) }
        eventTap = nil
        eventSource = nil
    }
}
