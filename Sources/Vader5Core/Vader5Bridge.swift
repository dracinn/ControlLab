import Foundation
import IOKit.hid

public enum Vader5BridgeMode: String, CaseIterable, Sendable {
    case monitor = "Monitor only"
    case virtualGamepad = "Virtual gamepad"
}

public enum Vader5BridgeStatus: Sendable, Equatable {
    case stopped
    case connecting
    case running(Vader5BridgeMode)
    case failed(String)
}

public enum Vader5Error: Error, CustomStringConvertible {
    case notFound, configInterfaceMissing, virtualDeviceCreation, handshake
    case managerOpen(IOReturn), deviceOpen(IOReturn)

    public var description: String {
        switch self {
        case .notFound: "Vader 5 Pro receiver not found."
        case .configInterfaceMissing: "Vader 5 Pro controller interface not found."
        case .virtualDeviceCreation: "Virtual gamepad permission is unavailable. Sign with Apple's com.apple.developer.hid.virtual.device entitlement or use Monitor only."
        case .handshake: "Controller initialization handshake failed."
        case .managerOpen(let code): "Could not open HID manager (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .deviceOpen(let code): "Could not open receiver (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        }
    }
}

public final class Vader5Bridge {
    public var onState: (@Sendable (Vader5State) -> Void)?
    public var onStatus: (@Sendable (Vader5BridgeStatus) -> Void)?

    private var manager: IOHIDManager?
    private var configDevice: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var virtualGamepad: VirtualGamepad?
    private var isRunning = false

    public init() {}

    public func start(mode: Vader5BridgeMode) throws {
        guard !isRunning else { return }
        onStatus?(.connecting)

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: Vader5Protocol.usagePage,
            kIOHIDPrimaryUsageKey: Vader5Protocol.usage,
        ] as CFDictionary)

        do {
            let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard managerResult == kIOReturnSuccess else { throw Vader5Error.managerOpen(managerResult) }
            guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
                  let device = devices.first else { throw Vader5Error.notFound }
            configDevice = device
            let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard deviceResult == kIOReturnSuccess else { throw Vader5Error.deviceOpen(deviceResult) }

            if mode == .virtualGamepad {
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
            onStatus?(.running(mode))
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
        configDevice = nil
        manager = nil
        isRunning = false
        onStatus?(.stopped)
    }

    private func initializeController() throws {
        for command in Vader5Protocol.initCommands {
            guard send(command) == kIOReturnSuccess else { throw Vader5Error.handshake }
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
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
        guard let state = Vader5Protocol.parse(
            UnsafeBufferPointer(start: report, count: length)) else { return }
        virtualGamepad?.send(state)
        onState?(state)
    }

    deinit { stop() }
}
