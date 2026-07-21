import Foundation
import Vader5Core

let mode: Vader5BridgeMode = CommandLine.arguments.contains("--monitor")
    ? .monitor : .virtualGamepad
let bridge = Vader5Bridge()
bridge.onStatus = { print("Status: \($0)") }
bridge.onState = { state in
    if CommandLine.arguments.contains("--verbose") {
        print("LX \(state.leftX) LY \(state.leftY) RX \(state.rightX) RY \(state.rightY) buttons 0x\(String(state.buttons.rawValue, radix: 16))")
    }
}
signal(SIGINT) { _ in CFRunLoopStop(CFRunLoopGetMain()) }
signal(SIGTERM) { _ in CFRunLoopStop(CFRunLoopGetMain()) }

do {
    try bridge.start(mode: mode)
    print("Vader 5 Pro bridge active in \(mode.rawValue) mode. Press Control-C to stop.")
    CFRunLoopRun()
    bridge.stop()
} catch {
    FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
