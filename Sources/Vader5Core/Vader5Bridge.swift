import Foundation
import IOKit.hid
import SDLGamepadC

public enum Vader5BridgeMode: String, CaseIterable, Sendable {
    case monitor = "Monitor only"
    case virtualGamepad = "Virtual gamepad"
}

public enum Vader5Transport: String, CaseIterable, Sendable {
    case usbReceiver = "USB receiver"
    case bluetooth = "Bluetooth"
}

public enum Vader5BridgeStatus: Sendable, Equatable {
    case stopped
    case connecting
    case running(Vader5BridgeMode)
    case failed(String)
}

public enum Vader5Error: Error, CustomStringConvertible {
    case notFound(Vader5Transport), configInterfaceMissing, virtualDeviceCreation, handshake
    case managerOpen(IOReturn), deviceOpen(IOReturn)
    case sdl(String), lightingUnavailable(String), lightingWrite

    public var description: String {
        switch self {
        case .notFound(.usbReceiver): "Vader 5 Pro USB receiver not found."
        case .notFound(.bluetooth): "Bluetooth controller not found. Pair the Vader 5 Pro in Xbox-compatible mode and wake it, then try again."
        case .configInterfaceMissing: "Vader 5 Pro controller interface not found."
        case .virtualDeviceCreation: "Virtual gamepad permission is unavailable. Sign with Apple's com.apple.developer.hid.virtual.device entitlement or use Monitor only."
        case .handshake: "Controller initialization handshake failed."
        case .managerOpen(let code): "Could not open HID manager (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .deviceOpen(let code): "Could not open receiver (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .sdl(let message): "SDL Bluetooth gamepad error: \(message)"
        case .lightingUnavailable(let message): message
        case .lightingWrite: "The controller did not accept the lighting command."
        }
    }
}

public final class Vader5Bridge {
    public var onState: (@Sendable (Vader5State) -> Void)?
    public var onStatus: (@Sendable (Vader5BridgeStatus) -> Void)?
    public var onLightingStatus: (@Sendable (Vader5LightingStatus) -> Void)?
    public var onLightingConfiguration: (@Sendable (Vader5LightingConfiguration) -> Void)?

    private var manager: IOHIDManager?
    private var configDevice: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var virtualGamepad: VirtualGamepad?
    private var sdlGamepad: OpaquePointer?
    private var sdlTimer: CFRunLoopTimer?
    private var lastBluetoothState: Vader5State?
    private var ledConfigChunks: [[UInt8]?] = []
    private var ledConfig: [UInt8]?
    private var ledConfigsByMode: [Vader5LightingMode: [UInt8]] = [:]
    private var isRunning = false

    public init() {}

    public func start(
        mode: Vader5BridgeMode,
        transport: Vader5Transport = .usbReceiver
    ) throws {
        guard !isRunning else { return }
        onStatus?(.connecting)
        let effectiveMode: Vader5BridgeMode = transport == .bluetooth ? .monitor : mode

        if transport == .bluetooth {
            do {
                try startBluetooth()
                isRunning = true
                if CLSDLGamepadHasRGBLED(sdlGamepad) {
                    onLightingStatus?(.ready(.sdl))
                } else {
                    onLightingStatus?(.unavailable(
                        "This Bluetooth profile does not expose lighting controls through SDL."))
                }
                onStatus?(.running(.monitor))
                return
            } catch {
                stop()
                onStatus?(.failed(String(describing: error)))
                throw error
            }
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, usbMatchingDictionary())

        do {
            let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard managerResult == kIOReturnSuccess else { throw Vader5Error.managerOpen(managerResult) }
            guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
                  let device = devices.first else { throw Vader5Error.notFound(transport) }
            configDevice = device
            let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard deviceResult == kIOReturnSuccess else { throw Vader5Error.deviceOpen(deviceResult) }

            if effectiveMode == .virtualGamepad {
                let output = VirtualGamepad()
                try output.start()
                virtualGamepad = output
            }

            reportBuffer = .allocate(capacity: 64)
            reportBuffer!.initialize(repeating: 0, count: 64)
            IOHIDDeviceRegisterInputReportCallback(
                device, reportBuffer!, 64,
                { context, result, _, _, _, report, length in
                    guard result == kIOReturnSuccess, let context else { return }
                    Unmanaged<Vader5Bridge>.fromOpaque(context)
                        .takeUnretainedValue().handle(report, length: length)
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            IOHIDDeviceScheduleWithRunLoop(
                device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            try initializeController()
            isRunning = true
            onStatus?(.running(effectiveMode))
            onLightingStatus?(.checking)
            _ = send(Vader5Protocol.ledConfigReadCommand())
        } catch {
            stop()
            onStatus?(.failed(String(describing: error)))
            throw error
        }
    }

    public func stop() {
        if let configDevice {
            _ = send(Vader5Protocol.stopCommand)
            IOHIDDeviceUnscheduleFromRunLoop(
                configDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(configDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        reportBuffer?.deallocate()
        reportBuffer = nil
        virtualGamepad?.stop()
        virtualGamepad = nil
        if let sdlTimer {
            CFRunLoopTimerInvalidate(sdlTimer)
            self.sdlTimer = nil
        }
        if let sdlGamepad {
            CLSDLGamepadClose(sdlGamepad)
            self.sdlGamepad = nil
        }
        lastBluetoothState = nil
        ledConfigChunks = []
        ledConfig = nil
        ledConfigsByMode = [:]
        configDevice = nil
        manager = nil
        isRunning = false
        onStatus?(.stopped)
        onLightingStatus?(.checking)
    }

    public func setSolidLighting(color: Vader5RGBColor, brightness: UInt8 = 100) throws {
        try setLighting(.init(mode: .steady, colors: [color], brightness: brightness))
    }

    public func refreshLightingConfiguration() throws {
        guard configDevice != nil else {
            throw Vader5Error.lightingUnavailable(
                "Connect the controller over USB before reading lighting.")
        }
        ledConfigChunks = []
        guard send(Vader5Protocol.ledConfigReadCommand()) == kIOReturnSuccess else {
            throw Vader5Error.lightingWrite
        }
    }

    public func setLighting(_ configuration: Vader5LightingConfiguration) throws {
        if let sdlGamepad {
            guard configuration.mode == .steady, let color = configuration.colors.first else {
                throw Vader5Error.lightingUnavailable(
                    "SDL exposes only steady-color lighting for this gamepad.")
            }
            guard CLSDLGamepadHasRGBLED(sdlGamepad) else {
                throw Vader5Error.lightingUnavailable(
                    "This Bluetooth profile does not expose lighting controls through SDL.")
            }
            guard CLSDLGamepadSetRGBLED(sdlGamepad, color.red, color.green, color.blue) else {
                throw Vader5Error.sdl(String(cString: CLSDLGamepadError()))
            }
            return
        }

        guard let ledConfig else {
            throw Vader5Error.lightingUnavailable(
                "Lighting is available after ControlLab reads the controller's current USB configuration.")
        }
        let baseConfig = ledConfigsByMode[configuration.mode] ?? ledConfig
        guard
              let packets = Vader5Protocol.lightingPackets(
                basedOn: baseConfig, configuration: configuration)
        else {
            throw Vader5Error.lightingUnavailable(
                "Lighting is available after ControlLab reads the controller's current USB configuration.")
        }
        for packet in packets {
            guard send(packet) == kIOReturnSuccess else { throw Vader5Error.lightingWrite }
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
        let updated = updatedLEDConfig(baseConfig, configuration: configuration)
        self.ledConfig = updated
        ledConfigsByMode[configuration.mode] = updated
        onLightingConfiguration?(configuration)
    }

    /// Writes controller lighting without blocking the caller's executor
    /// during the inter-packet delay required by the receiver.
    @MainActor public func setLightingAsync(
        _ configuration: Vader5LightingConfiguration
    ) async throws {
        if sdlGamepad != nil {
            try setLighting(configuration)
            return
        }

        guard let ledConfig else {
            throw Vader5Error.lightingUnavailable(
                "Lighting is available after ControlLab reads the controller's current USB configuration.")
        }
        let baseConfig = ledConfigsByMode[configuration.mode] ?? ledConfig
        guard let packets = Vader5Protocol.lightingPackets(
            basedOn: baseConfig, configuration: configuration)
        else {
            throw Vader5Error.lightingUnavailable(
                "Lighting is available after ControlLab reads the controller's current USB configuration.")
        }
        for packet in packets {
            guard send(packet) == kIOReturnSuccess else {
                throw Vader5Error.lightingWrite
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        let updated = updatedLEDConfig(
            baseConfig, configuration: configuration)
        self.ledConfig = updated
        ledConfigsByMode[configuration.mode] = updated
        onLightingConfiguration?(configuration)
    }

    private func initializeController() throws {
        for command in Vader5Protocol.initCommands {
            guard send(command) == kIOReturnSuccess else { throw Vader5Error.handshake }
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
    }

    private func usbMatchingDictionary() -> CFDictionary {
        [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: Vader5Protocol.usagePage,
            kIOHIDPrimaryUsageKey: Vader5Protocol.usage,
        ] as CFDictionary
    }

    @discardableResult
    private func send(_ prefix: [UInt8]) -> IOReturn {
        guard let configDevice else { return kIOReturnNotOpen }
        var packet = [UInt8](repeating: 0, count: 32)
        for (index, byte) in prefix.enumerated() { packet[index] = byte }
        return packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(configDevice, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
    }

    private func handle(_ report: UnsafePointer<UInt8>, length: Int) {
        let data = UnsafeBufferPointer(start: report, count: length)
        if let chunk = Vader5Protocol.parseLEDConfigChunk(data) {
            handleLEDConfigChunk(chunk)
            return
        }
        guard let parsed = Vader5Protocol.parse(data) else { return }
        publish(parsed)
    }

    private func handleLEDConfigChunk(_ chunk: (total: Int, index: Int, bytes: [UInt8])) {
        if ledConfigChunks.count != chunk.total {
            ledConfigChunks = Array(repeating: nil, count: chunk.total)
        }
        ledConfigChunks[chunk.index] = chunk.bytes
        guard ledConfigChunks.allSatisfy({ $0 != nil }) else { return }
        let config = ledConfigChunks.compactMap { $0 }.flatMap { $0 }
        guard config.count >= 20, config[0] == 0, config[1] == 2 || config[1] == 3 else {
            onLightingStatus?(.unavailable("The controller returned an unsupported lighting format."))
            return
        }
        ledConfig = config
        onLightingStatus?(.ready(.usb))
        if let configuration = Vader5Protocol.parseLightingConfiguration(config) {
            ledConfigsByMode[configuration.mode] = config
            onLightingConfiguration?(configuration)
        }
    }

    private func updatedLEDConfig(
        _ current: [UInt8], configuration: Vader5LightingConfiguration
    ) -> [UInt8] {
        guard let packets = Vader5Protocol.lightingPackets(
            basedOn: current, configuration: configuration)
        else { return current }
        // Reconstruct the payload from A9 packets so a second color change can
        // preserve the just-written version and LED count without another read.
        return packets.dropFirst().flatMap { packet in
            let count = max(0, Int(packet[3]) - 3)
            return Array(packet[5..<(5 + count)])
        }
    }

    private func startBluetooth() throws {
        guard let gamepad = CLSDLGamepadOpen() else {
            let message = String(cString: CLSDLGamepadError())
            throw Vader5Error.sdl(message)
        }
        sdlGamepad = gamepad

        var context = CFRunLoopTimerContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let timer = CFRunLoopTimerCreate(
            kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(), 1.0 / 120.0, 0, 0,
            { _, context in
                guard let context else { return }
                Unmanaged<Vader5Bridge>.fromOpaque(context)
                    .takeUnretainedValue().pollBluetooth()
            },
            &context)
        sdlTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
        pollBluetooth()
    }

    private func pollBluetooth() {
        guard let sdlGamepad else { return }
        var snapshot = CLSDLGamepadState()
        guard CLSDLGamepadRead(sdlGamepad, &snapshot) else {
            if !CLSDLGamepadConnected(sdlGamepad) {
                if let sdlTimer { CFRunLoopTimerInvalidate(sdlTimer) }
                sdlTimer = nil
                CLSDLGamepadClose(sdlGamepad)
                self.sdlGamepad = nil
                lastBluetoothState = nil
                isRunning = false
                onStatus?(.failed("Bluetooth controller disconnected."))
            }
            return
        }
        let state = Vader5State(
            leftX: snapshot.left_x, leftY: snapshot.left_y,
            rightX: snapshot.right_x, rightY: snapshot.right_y,
            leftTrigger: snapshot.left_trigger, rightTrigger: snapshot.right_trigger,
            dpad: snapshot.dpad,
            buttons: Vader5Buttons(rawValue: snapshot.buttons),
            extraButtons: 0,
            gyro: .init(x: 0, y: 0, z: 0),
            accelerometer: .init(x: 0, y: 0, z: 0))
        guard state != lastBluetoothState else { return }
        lastBluetoothState = state
        publish(state)
    }

    private func publish(_ state: Vader5State) {
        virtualGamepad?.send(state)
        onState?(state)
    }

    deinit { stop() }
}
