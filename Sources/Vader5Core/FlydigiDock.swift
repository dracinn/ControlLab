import Foundation
import IOKit.hid

public enum FlydigiDockError: Error, CustomStringConvertible, Sendable {
    case notFound
    case managerOpen(IOReturn)
    case deviceOpen(IOReturn)
    case reportWrite(index: Int, result: IOReturn)
    case acknowledgementTimeout(command: UInt8)
    case commandRejected(command: UInt8, status: UInt8)

    public var description: String {
        switch self {
        case .notFound:
            "Flydigi Charging Station 2 Pro was not found."
        case .managerOpen(let result):
            "Could not open the dock HID manager (\(hex(result)))."
        case .deviceOpen(let result):
            "Could not open the dock HID interface (\(hex(result)))."
        case .reportWrite(let index, let result):
            "The dock rejected lighting report \(index + 1) (\(hex(result)))."
        case .acknowledgementTimeout(let command):
            "The dock did not acknowledge command 0x\(String(command, radix: 16))."
        case .commandRejected(let command, let status):
            "The dock rejected command 0x\(String(command, radix: 16)) with status \(status)."
        }
    }

    private func hex(_ result: IOReturn) -> String {
        "0x\(String(UInt32(bitPattern: result), radix: 16))"
    }
}

public final class FlydigiDock {
    public init() {}

    public func isConnected() throws -> Bool {
        let manager = try makeOpenManager()
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.isEmpty == false
    }

    public func setSolidLighting(
        color: Vader5RGBColor,
        brightness: UInt8 = 100
    ) throws {
        try send(FlydigiDockProtocol.solidColorReports(
            color: color, brightness: brightness))
    }

    public func setLighting(
        _ configuration: FlydigiDockLightingConfiguration
    ) throws {
        try send(FlydigiDockProtocol.reports(configuration: configuration))
    }

    public func setPixels(
        _ pixels: [Vader5RGBColor],
        brightness: UInt8 = 100
    ) throws {
        try send(FlydigiDockProtocol.reports(
            pixels: pixels, brightness: brightness))
    }

    public func setDeviceSettings(
        _ settings: FlydigiDockDeviceSettings
    ) throws {
        try send([
            FlydigiDockProtocol.deviceSettingReport(
                .sleepWhenCharging, enabled: settings.sleepWhenCharging),
            FlydigiDockProtocol.deviceSettingReport(
                .ledSync, enabled: settings.ledSync),
            FlydigiDockProtocol.deviceSettingReport(
                .closeWithSystem, enabled: settings.closeWithSystem),
            FlydigiDockProtocol.deviceSettingReport(
                .showAnimationWhenCharging,
                enabled: settings.showAnimationWhenCharging),
        ])
    }

    public func readSnapshot(timeout: TimeInterval = 0.8) throws -> FlydigiDockSnapshot {
        try withOpenDevice { device in
            let capture = FlydigiDockReportCapture()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(
                capacity: FlydigiDockProtocol.reportSize)
            buffer.initialize(
                repeating: 0, count: FlydigiDockProtocol.reportSize)
            defer { buffer.deallocate() }

            IOHIDDeviceRegisterInputReportCallback(
                device, buffer, FlydigiDockProtocol.reportSize,
                { context, result, _, _, _, report, length in
                    guard result == kIOReturnSuccess, let context else { return }
                    Unmanaged<FlydigiDockReportCapture>.fromOpaque(context)
                        .takeUnretainedValue()
                        .append(report: report, length: length)
                },
                Unmanaged.passUnretained(capture).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(
                device, CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue)
            defer {
                IOHIDDeviceUnscheduleFromRunLoop(
                    device, CFRunLoopGetCurrent(),
                    CFRunLoopMode.defaultMode.rawValue)
            }

            try write(
                FlydigiDockProtocol.heartbeatReport(),
                to: device, index: 0)
            Thread.sleep(forTimeInterval: 0.005)
            try write(
                FlydigiDockProtocol.readLightingConfigurationReport(),
                to: device, index: 1)

            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                let snapshot = FlydigiDockProtocol.parseSnapshot(capture.reports)
                if snapshot.settings != nil && snapshot.lighting != nil {
                    return snapshot
                }
                RunLoop.current.run(
                    mode: .default,
                    before: min(deadline, Date().addingTimeInterval(0.025)))
            }
            return FlydigiDockProtocol.parseSnapshot(capture.reports)
        }
    }

    private func send(_ reports: [[UInt8]]) throws {
        try withOpenDevice { device in
            let capture = FlydigiDockReportCapture()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(
                capacity: FlydigiDockProtocol.reportSize)
            buffer.initialize(
                repeating: 0, count: FlydigiDockProtocol.reportSize)
            defer { buffer.deallocate() }
            IOHIDDeviceRegisterInputReportCallback(
                device, buffer, FlydigiDockProtocol.reportSize,
                { context, result, _, _, _, report, length in
                    guard result == kIOReturnSuccess, let context else { return }
                    Unmanaged<FlydigiDockReportCapture>.fromOpaque(context)
                        .takeUnretainedValue()
                        .append(report: report, length: length)
                },
                Unmanaged.passUnretained(capture).toOpaque())
            IOHIDDeviceScheduleWithRunLoop(
                device, CFRunLoopGetCurrent(),
                CFRunLoopMode.defaultMode.rawValue)
            defer {
                IOHIDDeviceUnscheduleFromRunLoop(
                    device, CFRunLoopGetCurrent(),
                    CFRunLoopMode.defaultMode.rawValue)
            }

            for (index, report) in reports.enumerated() {
                let captureIndex = capture.reports.count
                try write(report, to: device, index: index)
                let command = report[2]
                let deadline = Date().addingTimeInterval(0.5)
                var acknowledgement: [UInt8]?
                while Date() < deadline {
                    acknowledgement = capture.first(
                        command: command, after: captureIndex)
                    if acknowledgement != nil { break }
                    RunLoop.current.run(
                        mode: .default,
                        before: min(deadline, Date().addingTimeInterval(0.01)))
                }
                guard let acknowledgement else {
                    throw FlydigiDockError.acknowledgementTimeout(
                        command: command)
                }
                if acknowledgement.count > 4, acknowledgement[4] != 0 {
                    throw FlydigiDockError.commandRejected(
                        command: command, status: acknowledgement[4])
                }
            }
        }
    }

    private func write(
        _ report: [UInt8],
        to device: IOHIDDevice,
        index: Int
    ) throws {
        let result = report.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(
                device, kIOHIDReportTypeOutput, 0,
                $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else {
            throw FlydigiDockError.reportWrite(index: index, result: result)
        }
    }

    private func withOpenDevice<T>(
        _ operation: (IOHIDDevice) throws -> T
    ) throws -> T {
        let manager = try makeOpenManager()
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            throw FlydigiDockError.notFound
        }
        let result = IOHIDDeviceOpen(
            device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw FlydigiDockError.deviceOpen(result)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return try operation(device)
    }

    private func makeOpenManager() throws -> IOHIDManager {
        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: FlydigiDockProtocol.vendorID,
            kIOHIDProductIDKey: FlydigiDockProtocol.productID,
            kIOHIDPrimaryUsagePageKey: FlydigiDockProtocol.usagePage,
            kIOHIDPrimaryUsageKey: FlydigiDockProtocol.usage,
        ] as CFDictionary)
        let result = IOHIDManagerOpen(
            manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw FlydigiDockError.managerOpen(result)
        }
        return manager
    }
}

private final class FlydigiDockReportCapture {
    private(set) var reports: [[UInt8]] = []

    func append(report: UnsafePointer<UInt8>, length: Int) {
        guard length > 0 else { return }
        reports.append(Array(UnsafeBufferPointer(start: report, count: length)))
    }

    func first(command: UInt8, after index: Int) -> [UInt8]? {
        guard index < reports.count else { return nil }
        return reports[index...].first {
            $0.count > 4 && $0[0] == 0x5a && $0[1] == 0xa5 &&
                $0[2] == command
        }
    }
}
