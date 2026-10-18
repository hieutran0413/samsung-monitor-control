import SwiftUI
import Darwin

/// Local, explicitly requested experiment. This ABI is not an Apple-supported API.
/// Revalidate in an isolated probe before extending the OS build allowlist.
@available(macOS 26.0, *)
enum PrivateControlCenterGlass {
    static let material: Glass = resolve() ?? .regular

    private static func resolve() -> Glass? {
        guard ProcessInfo.processInfo.environment["SMC_PUBLIC_GLASS"] != "1" else { return nil }
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &bytes, &size, nil, 0) == 0,
              String(cString: bytes) == "26B5112a",
              MemoryLayout<Glass>.size == 40,
              MemoryLayout<Glass>.alignment == 8,
              Mirror(reflecting: Glass.regular).children.first?.label == "base",
              let handle = dlopen("/System/Library/Frameworks/SwiftUI.framework/SwiftUI", RTLD_LAZY) else { return nil }
        // Keep the framework loaded for the lifetime of the returned Swift value.
        // On this pinned build, public Glass is a single _Glass base, with identical
        // indirect-return ABI. The isolated probe checks regular equivalence first.
        typealias Getter = @convention(thin) () -> Glass
        guard let regular = dlsym(handle, "$s7SwiftUI6_GlassV7regularACvgZ"),
              let controlCenter = dlsym(handle, "$s7SwiftUI6_GlassV13controlCenterACvgZ") else { return nil }
        let baseline = unsafeBitCast(regular, to: Getter.self)()
        guard baseline == Glass.regular else { return nil }
        let value = unsafeBitCast(controlCenter, to: Getter.self)()
        guard String(reflecting: Mirror(reflecting: value).children.first?.value as Any).contains("controlCenter") else { return nil }
        if CommandLine.arguments.contains("--qc") { print("QC_GLASS=private.controlCenter"); fflush(stdout) }
        return value
    }
}
