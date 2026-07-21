import Foundation
import IOKit.hid

public enum Vader5FirmwareReadError: Error, CustomStringConvertible, Sendable {
    case notFound
    case managerOpen(IOReturn)
    case deviceOpen(IOReturn)
    case requestFailed(IOReturn)
    case timeout

    public var description: String {
        switch self {
        case .notFound:
            "Vader 5 Pro controller interface not found. Connect and wake the controller, then try again."
        case .managerOpen(let code):
            "Could not open HID manager (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .deviceOpen(let code):
            "Could not open the controller interface (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .requestFailed(let code):
            "The firmware version request failed (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .timeout:
            "The controller did not return firmware versions. Make sure it is awake and connected through the USB dongle."
        }
    }
}

/// Performs a single, read-only firmware metadata query over the configuration
/// HID interface. It never switches the device into update mode.
public enum Vader5FirmwareReader {
    public static func read(timeout: TimeInterval = 1.5) throws -> Vader5FirmwareVersions {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: Vader5Protocol.usagePage,
            kIOHIDPrimaryUsageKey: Vader5Protocol.usage,
        ] as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw Vader5FirmwareReadError.managerOpen(managerResult)
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            throw Vader5FirmwareReadError.notFound
        }
        let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            throw Vader5FirmwareReadError.deviceOpen(deviceResult)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let context = FirmwareReadContext(runLoop: CFRunLoopGetCurrent())
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffer.initialize(repeating: 0, count: 64)
        defer { buffer.deallocate() }

        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, 64,
            { contextPointer, result, _, _, _, report, length in
                guard result == kIOReturnSuccess, let contextPointer else { return }
                let context = Unmanaged<FirmwareReadContext>
                    .fromOpaque(contextPointer).takeUnretainedValue()
                guard let versions = Vader5Protocol.parseFirmwareVersions(
                    UnsafeBufferPointer(start: report, count: length)) else { return }
                context.versions = versions
                CFRunLoopStop(context.runLoop)
            },
            Unmanaged.passUnretained(context).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(
            device, context.runLoop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(
                device, context.runLoop, CFRunLoopMode.defaultMode.rawValue)
        }

        var packet = [UInt8](repeating: 0, count: 32)
        packet.replaceSubrange(
            0..<Vader5Protocol.firmwareQueryCommand.count,
            with: Vader5Protocol.firmwareQueryCommand)
        let requestResult = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
        guard requestResult == kIOReturnSuccess else {
            throw Vader5FirmwareReadError.requestFailed(requestResult)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while context.versions == nil && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, min(0.1, deadline.timeIntervalSinceNow), false)
        }
        guard let versions = context.versions else { throw Vader5FirmwareReadError.timeout }
        return versions
    }
}

private final class FirmwareReadContext {
    let runLoop: CFRunLoop
    var versions: Vader5FirmwareVersions?

    init(runLoop: CFRunLoop) {
        self.runLoop = runLoop
    }
}
