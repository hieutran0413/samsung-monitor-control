import Cocoa
guard CommandLine.arguments.contains("--hardware") else {
    print("Pass --hardware to cycle the connected LG display; not a unit test.")
    exit(2)
}
var recovered: DisplayBrightnessController?
let controller = DisplayBrightnessController()
let uuid = "345E8820-588D-4CEF-A9B8-1A0E5523690B"
DispatchQueue.main.asyncAfter(deadline:.now()+3) {
    controller.setConnected(false, uuid:uuid, name:"LG ULTRAFINE")
}
DispatchQueue.main.asyncAfter(deadline:.now()+9) {
    print("disabled",controller.disconnected[uuid] != nil,controller.message)
    if CommandLine.arguments.contains("--startup") {
        recovered = DisplayBrightnessController()
    } else {
        controller.setConnected(true,uuid:uuid,name:"LG ULTRAFINE")
    }
}
DispatchQueue.main.asyncAfter(deadline:.now()+17) {
    let result = recovered ?? controller
    let id = CGDisplayGetDisplayIDFromUUID(CFUUIDCreateFromString(nil, uuid as CFString))
    let passed = result.disconnected[uuid] == nil && id != 0 && CGDisplayIsActive(id) != 0
    print("reconnected", passed, result.message)
    fflush(stdout)
    exit(passed ? 0 : 1)
}
RunLoop.main.run()
