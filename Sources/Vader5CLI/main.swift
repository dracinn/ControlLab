import Foundation
import AppKit
import Vader5Core

func parseRGBHex(_ input: String) -> Vader5RGBColor? {
    let value = input.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
    return Vader5RGBColor(
        red: UInt8((number >> 16) & 0xff),
        green: UInt8((number >> 8) & 0xff),
        blue: UInt8(number & 0xff))
}

if CommandLine.arguments.contains("--dock-status") {
    do {
        print(try FlydigiDock().isConnected()
              ? "Flydigi Charging Station 2 Pro is connected."
              : "Flydigi Charging Station 2 Pro is not connected.")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if CommandLine.arguments.contains("--dock-config") {
    do {
        let snapshot = try FlydigiDock().readSnapshot()
        if let lighting = snapshot.lighting {
            print("Mode:       \(lighting.mode.title)")
            print("Brightness: \(lighting.brightness)%")
            print("Cycle time: \(lighting.period)")
            print("Direction:  \(lighting.direction.title)")
            print("Colors:     \(lighting.colors.count)")
        } else {
            print("Lighting configuration was not returned.")
        }
        if let settings = snapshot.settings {
            print("Sleep while charging:      \(settings.sleepWhenCharging)")
            print("Show charging animation:   \(settings.showAnimationWhenCharging)")
            print("LED sync:                  \(settings.ledSync)")
            print("Turn off with system:      \(settings.closeWithSystem)")
        } else {
            print("Device behavior was not returned.")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let optionIndex = CommandLine.arguments.firstIndex(of: "--dock-mode") {
    guard CommandLine.arguments.indices.contains(optionIndex + 1) else {
        FileHandle.standardError.write(
            "Error: --dock-mode requires a mode name.\n".data(using: .utf8)!)
        exit(2)
    }
    let modeName = CommandLine.arguments[optionIndex + 1].lowercased()
    let modes: [String: FlydigiDockLightingMode] = [
        "off": .off,
        "solid": .solid,
        "default": .deviceDefault,
        "custom": .custom,
        "diagonal-flow": .diagonalFlow,
        "breathing": .breathing,
        "gradient": .gradient,
        "wave-gradient": .waveGradient,
        "rainbow": .rainbow,
        "pulse": .pulse,
    ]
    guard let mode = modes[modeName] else {
        FileHandle.standardError.write(
            "Error: unknown dock mode '\(modeName)'.\n".data(using: .utf8)!)
        exit(2)
    }
    let colors: [Vader5RGBColor] = [
        .init(red: 0, green: 160, blue: 128),
        .init(red: 128, green: 32, blue: 220),
    ]
    let configuration = FlydigiDockLightingConfiguration(
        mode: mode,
        period: 50,
        brightness: 40,
        colors: mode == .custom ? [] : colors,
        direction: .downRight,
        pixels: FlydigiDockFrameGenerator.pixels(
            mode: mode,
            colors: colors,
            direction: .downRight))
    do {
        try FlydigiDock().setLighting(configuration)
        print("Applied \(mode.title) at 40% brightness.")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if CommandLine.arguments.contains("--dock-off") {
    do {
        try FlydigiDock().setSolidLighting(
            color: .init(red: 0, green: 0, blue: 0))
        print("Turned off all 162 dock pixels.")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let optionIndex = CommandLine.arguments.firstIndex(of: "--dock-color") {
    guard CommandLine.arguments.indices.contains(optionIndex + 1),
          let color = parseRGBHex(CommandLine.arguments[optionIndex + 1]) else {
        FileHandle.standardError.write(
            "Error: --dock-color requires a six-digit RGB value such as 0060FF.\n"
                .data(using: .utf8)!)
        exit(2)
    }
    let brightness: UInt8
    if CommandLine.arguments.indices.contains(optionIndex + 2),
       let requested = Int(CommandLine.arguments[optionIndex + 2]) {
        brightness = UInt8(clamping: min(max(requested, 0), 100))
    } else {
        brightness = 100
    }
    do {
        try FlydigiDock().setSolidLighting(
            color: color, brightness: brightness)
        print("Applied dock color at \(brightness)% brightness to all 162 pixels.")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if CommandLine.arguments.contains("--read-update-status") {
    do {
        print("Reading FFEE feature report 5. No output or feature report will be sent.")
        let report = try Vader5UpdateChannelMonitor.readFeatureReport()
        let bytes = report.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("Received \(report.count) bytes: \(bytes)")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let optionIndex = CommandLine.arguments.firstIndex(of: "--listen-update-channel") {
    let duration: TimeInterval
    if CommandLine.arguments.indices.contains(optionIndex + 1) {
        duration = TimeInterval(CommandLine.arguments[optionIndex + 1]) ?? 10
    } else {
        duration = 10
    }
    do {
        let start = ProcessInfo.processInfo.systemUptime
        print("Passively listening on FFEE for \(duration) seconds. No reports will be sent.")
        let count = try Vader5UpdateChannelMonitor.listen(duration: duration) { report in
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let bytes = report.map { String(format: "%02X", $0) }.joined(separator: " ")
            print(String(format: "+%.3fs [%d] %@", elapsed, report.count, bytes))
        }
        print("Observed \(count) unsolicited report\(count == 1 ? "" : "s").")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let optionIndex = CommandLine.arguments.firstIndex(of: "--listen-input-channel") {
    let duration: TimeInterval
    if CommandLine.arguments.indices.contains(optionIndex + 1) {
        duration = TimeInterval(CommandLine.arguments[optionIndex + 1]) ?? 5
    } else {
        duration = 5
    }
    do {
        let start = ProcessInfo.processInfo.systemUptime
        var displayed = 0
        print("Passively listening on FFA0 for \(duration) seconds. No reports will be sent.")
        let count = try Vader5UpdateChannelMonitor.listenInputChannel(duration: duration) { report in
            guard displayed < 20 else { return }
            displayed += 1
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            let bytes = report.map { String(format: "%02X", $0) }.joined(separator: " ")
            print(String(format: "+%.3fs [%d] %@", elapsed, report.count, bytes))
        }
        if count > displayed {
            print("Suppressed \(count - displayed) additional reports.")
        }
        print("Observed \(count) unsolicited report\(count == 1 ? "" : "s").")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let optionIndex = CommandLine.arguments.firstIndex(of: "--inspect-firmware") {
    guard CommandLine.arguments.indices.contains(optionIndex + 1) else {
        FileHandle.standardError.write("Error: --inspect-firmware requires a file path.\n".data(using: .utf8)!)
        exit(2)
    }
    do {
        let url = URL(fileURLWithPath: CommandLine.arguments[optionIndex + 1])
        let info = try Vader5FirmwarePackageInspector.inspect(url: url)
        print("File:       \(info.fileName)")
        print("Size:       \(info.size) bytes")
        print("SHA-256:    \(info.sha256)")
        print("Container:  \(info.isKnownContainer ? "NearLink .fwpkg" : "unknown")")
        if let layout = info.nearLinkLayout {
            print("Headers:    outer \(layout.outerHeaderSize), inner \(layout.innerHeaderSize) bytes")
            print("Descriptor: 0x\(String(layout.descriptorOffset, radix: 16))")
            print("Subpackage: \(layout.subpackageMagic) at 0x\(String(layout.subpackageOffset, radix: 16)), \(layout.subpackageLength) bytes")
            print("Payload:    0x\(String(layout.payloadOffset, radix: 16)), \(layout.payloadLength) bytes")
            print("Image head: \(layout.payloadHeader)")
            print("Payload sum: \(layout.payloadSHA256Matches ? "verified" : "MISMATCH") \(layout.payloadSHA256)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if let optionIndex = CommandLine.arguments.firstIndex(of: "--simulate-firmware") {
    guard CommandLine.arguments.indices.contains(optionIndex + 1) else {
        FileHandle.standardError.write("Error: --simulate-firmware requires a file path.\n".data(using: .utf8)!)
        exit(2)
    }
    do {
        let url = URL(fileURLWithPath: CommandLine.arguments[optionIndex + 1])
        let image = try Data(contentsOf: url)
        let scenarios: [(String, Vader5SimulationScenario, Vader5DryRunPolicy)] = [
            ("clean transfer", .success, .init()),
            ("corruption retry", .corruptedPacketOnce(block: 0), .init(maxPacketRetries: 1)),
            ("disconnect recovery", .disconnectOnce(block: 0), .init(maxRecoveryRestarts: 1)),
            ("interruption recovery", .interrupted(block: 0), .init(maxRecoveryRestarts: 1)),
        ]
        for (name, scenario, policy) in scenarios {
            let result = try Vader5DiagnosticUpdater.run(image: image, scenario: scenario, policy: policy)
            print("PASS \(name): \(result.blockCount) blocks, \(result.events.count) events")
        }
        print("Simulation only; no HID device was opened and no firmware was written.")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

if CommandLine.arguments.contains("--firmware") {
    do {
        let versions = try Vader5FirmwareReader.read()
        print("Controller: \(versions.main ?? "unknown")")
        print("RF:         \(versions.rf ?? "unknown")")
        print("SI:         \(versions.si ?? "unknown")")
        print("Dongle:     \(versions.dongle ?? "unknown")")
        exit(0)
    } catch {
        FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let transport: Vader5Transport = CommandLine.arguments.contains("--bluetooth")
    ? .bluetooth : .usbReceiver
if transport == .bluetooth {
    // Apple's GameController discovery, used by SDL for this profile, needs a
    // Cocoa application object even though this client has no windows.
    NSApplication.shared.finishLaunching()
}
let mode: Vader5BridgeMode = transport == .bluetooth || CommandLine.arguments.contains("--monitor")
    ? .monitor : .virtualGamepad
let bridge = Vader5Bridge()
bridge.onStatus = { print("Status: \($0)") }
bridge.onLightingStatus = { print("Lighting: \($0)") }
bridge.onLightingConfiguration = { print("Lighting configuration: \($0)") }
bridge.onState = { state in
    if CommandLine.arguments.contains("--verbose") {
        print("LX \(state.leftX) LY \(state.leftY) RX \(state.rightX) RY \(state.rightY) buttons 0x\(String(state.buttons.rawValue, radix: 16))")
    }
}
signal(SIGINT) { _ in CFRunLoopStop(CFRunLoopGetMain()) }
signal(SIGTERM) { _ in CFRunLoopStop(CFRunLoopGetMain()) }

do {
    try bridge.start(mode: mode, transport: transport)
    print("ControlLab bridge active over \(transport.rawValue) in \(mode.rawValue) mode. Press Control-C to stop.")
    CFRunLoopRun()
    bridge.stop()
} catch {
    FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
