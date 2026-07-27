import Foundation
import IOKit.hid

public enum Vader5UpdateChannelMonitorError: Error, CustomStringConvertible, Sendable {
    case notFound
    case managerOpen(IOReturn)
    case deviceOpen(IOReturn)
    case featureRead(IOReturn)

    public var description: String {
        switch self {
        case .notFound:
            "The Flydigi FFEE update channel was not found. Connect the USB receiver and try again."
        case .managerOpen(let code):
            "Could not open HID manager (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .deviceOpen(let code):
            "Could not open the FFEE update channel (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .featureRead(let code):
            "Could not read FFEE feature report 5 (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        }
    }
}

/// Passively observes unsolicited input reports on Flydigi's FFEE HID channel.
/// This type deliberately contains no output or feature-report operation.
public enum Vader5UpdateChannelMonitor {
    public static func readFeatureReport() throws -> [UInt8] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: Vader5HIDOTAProtocol.moduleUsagePage,
            kIOHIDPrimaryUsageKey: 0,
        ] as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw Vader5UpdateChannelMonitorError.managerOpen(managerResult)
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            throw Vader5UpdateChannelMonitorError.notFound
        }
        let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            throw Vader5UpdateChannelMonitorError.deviceOpen(deviceResult)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        var report = [UInt8](repeating: 0, count: Vader5HIDOTAProtocol.reportLength)
        var reportLength = report.count
        let readResult = report.withUnsafeMutableBufferPointer {
            IOHIDDeviceGetReport(
                device, kIOHIDReportTypeFeature, 5,
                $0.baseAddress!, &reportLength)
        }
        guard readResult == kIOReturnSuccess else {
            throw Vader5UpdateChannelMonitorError.featureRead(readResult)
        }
        return Array(report.prefix(reportLength))
    }

    public static func listen(
        duration: TimeInterval,
        onReport: @escaping ([UInt8]) -> Void
    ) throws -> Int {
        try listenChannel(
            usagePage: Vader5HIDOTAProtocol.moduleUsagePage,
            usage: 0,
            reportLength: Vader5HIDOTAProtocol.reportLength,
            duration: duration,
            onReport: onReport
        )
    }

    public static func listenInputChannel(
        duration: TimeInterval,
        onReport: @escaping ([UInt8]) -> Void
    ) throws -> Int {
        try listenChannel(
            usagePage: Vader5Protocol.usagePage,
            usage: Vader5Protocol.usage,
            reportLength: 32,
            duration: duration,
            onReport: onReport
        )
    }

    private static func listenChannel(
        usagePage: Int,
        usage: Int,
        reportLength: Int,
        duration: TimeInterval,
        onReport: @escaping ([UInt8]) -> Void
    ) throws -> Int {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: usagePage,
            kIOHIDPrimaryUsageKey: usage,
        ] as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw Vader5UpdateChannelMonitorError.managerOpen(managerResult)
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            throw Vader5UpdateChannelMonitorError.notFound
        }
        let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            throw Vader5UpdateChannelMonitorError.deviceOpen(deviceResult)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let context = UpdateChannelMonitorContext(onReport: onReport)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLength)
        buffer.initialize(repeating: 0, count: reportLength)
        defer { buffer.deallocate() }

        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, reportLength,
            { contextPointer, result, _, _, _, report, length in
                guard result == kIOReturnSuccess, let contextPointer else { return }
                let context = Unmanaged<UpdateChannelMonitorContext>
                    .fromOpaque(contextPointer).takeUnretainedValue()
                context.reportCount += 1
                context.onReport(Array(UnsafeBufferPointer(start: report, count: length)))
            },
            Unmanaged.passUnretained(context).toOpaque()
        )
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        }

        let deadline = Date().addingTimeInterval(max(0, duration))
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, min(0.1, deadline.timeIntervalSinceNow), false)
        }
        return context.reportCount
    }
}

private final class UpdateChannelMonitorContext {
    let onReport: ([UInt8]) -> Void
    var reportCount = 0

    init(onReport: @escaping ([UInt8]) -> Void) {
        self.onReport = onReport
    }
}
