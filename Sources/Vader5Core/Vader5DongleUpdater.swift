import Foundation
import IOKit.hid

public enum Vader5DongleUpdateError: Error, CustomStringConvertible, Sendable {
    case notFound(target: Vader5DongleUpdater.Target)
    case managerOpen(IOReturn)
    case deviceOpen(IOReturn)
    case writeFailed(IOReturn)
    case echoTimeout(stage: String)
    case completionTimeout
    case updateRejected(UInt8)
    case unexpectedResponse
    case invalidImage(String)
    case imageTooLarge

    public var description: String {
        switch self {
        case let .notFound(target):
            "The Flydigi \(target.channelName) update channel was not found. \(target.connectionHint)"
        case let .managerOpen(code):
            "Could not open HID manager (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case let .deviceOpen(code):
            "Could not open the update channel (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case let .writeFailed(code):
            "An OTA report write failed (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case let .echoTimeout(stage):
            "The device stopped acknowledging OTA frames during \(stage)."
        case .completionTimeout:
            "The device did not return an OTA completion status."
        case let .updateRejected(status):
            "The device rejected the update (status 0x\(String(status, radix: 16)))."
        case .unexpectedResponse:
            "The device returned an unexpected OTA response."
        case let .invalidImage(reason):
            "Not a valid Telink image: \(reason)."
        case .imageTooLarge:
            "The image exceeds the recovered 16-bit OTA block address space."
        }
    }
}

public enum Vader5DongleUpdatePhase: Sendable, Equatable {
    case starting
    case transferring(sent: Int, total: Int)
    case finishing
    case verifying
    case completed
}

/// Performs a real Telink HID OTA update over the device's update interface:
/// the receiver dongle on usage page 0xFFEE, or the cabled controller's RF
/// chip on 0xFFEF. This is the path verified end-to-end on hardware: start
/// frame, data frames paced by echo acknowledgements, then the finish frame
/// whose completion report carries the commit status.
///
/// Call `update(image:)` from a thread that can block; it runs its own
/// CFRunLoop while transferring. The chip validates the image before
/// swapping, so an interrupted transfer leaves the running firmware intact.
public final class Vader5DongleUpdater: @unchecked Sendable {
    public enum Target: Sendable, Equatable {
        /// Receiver dongle Telink chip, on the receiver's 0xFFEE interface.
        case dongle
        /// Controller RF Telink chip, on the cabled controller's 0xFFEF
        /// interface.
        case controllerRF

        public var usagePage: Int {
            switch self {
            case .dongle: Vader5HIDOTAProtocol.moduleUsagePage
            case .controllerRF: Vader5HIDOTAProtocol.controllerUsagePage
            }
        }

        public var channelName: String {
            switch self {
            case .dongle: "FFEE"
            case .controllerRF: "FFEF"
            }
        }

        public var displayName: String {
            switch self {
            case .dongle: "dongle"
            case .controllerRF: "controller RF"
            }
        }

        var connectionHint: String {
            switch self {
            case .dongle:
                "Connect the USB receiver and try again."
            case .controllerRF:
                "Connect the controller over USB-C and try again."
            }
        }
    }

    public var onEvent: (@Sendable (Vader5DiagnosticEvent) -> Void)?
    public var onPhase: (@Sendable (Vader5DongleUpdatePhase) -> Void)?

    private let target: Target
    private let echoTimeout: TimeInterval
    private let completionTimeout: TimeInterval

    public init(
        target: Target = .dongle,
        echoTimeout: TimeInterval = 1.5,
        completionTimeout: TimeInterval = 15
    ) {
        self.target = target
        self.echoTimeout = echoTimeout
        self.completionTimeout = completionTimeout
    }

    /// Whether the target's update interface is currently enumerated.
    public static func isChannelPresent(target: Target) -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: target.usagePage,
            kIOHIDPrimaryUsageKey: 0,
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return false
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return false
        }
        return !devices.isEmpty
    }

    public static func validate(image: Data) throws {
        guard image.count >= 32 else {
            throw Vader5DongleUpdateError.invalidImage("file is too small")
        }
        guard image.count <= (Int(UInt16.max) + 1) * 16 else {
            throw Vader5DongleUpdateError.imageTooLarge
        }
        let declaredSize = Int(image[24])
            | Int(image[25]) << 8
            | Int(image[26]) << 16
            | Int(image[27]) << 24
        guard declaredSize == image.count else {
            throw Vader5DongleUpdateError.invalidImage(
                "source_bin_size at offset 24 is \(declaredSize), file is \(image.count) bytes")
        }
    }

    public func update(image: Data) throws -> [Vader5DiagnosticEvent] {
        try Self.validate(image: image)

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: target.usagePage,
            kIOHIDPrimaryUsageKey: 0,
        ] as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else {
            throw Vader5DongleUpdateError.managerOpen(managerResult)
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
              let device = devices.first else {
            throw Vader5DongleUpdateError.notFound(target: target)
        }
        let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard deviceResult == kIOReturnSuccess else {
            throw Vader5DongleUpdateError.deviceOpen(deviceResult)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let context = OTAContext()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(
            capacity: Vader5HIDOTAProtocol.reportLength)
        buffer.initialize(repeating: 0, count: Vader5HIDOTAProtocol.reportLength)
        defer { buffer.deallocate() }

        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, Vader5HIDOTAProtocol.reportLength,
            { contextPointer, result, _, _, _, report, length in
                guard result == kIOReturnSuccess, let contextPointer else { return }
                let context = Unmanaged<OTAContext>
                    .fromOpaque(contextPointer).takeUnretainedValue()
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                context.echoCount &+= 1
                let parsed = Vader5HIDOTAProtocol.parseResponse(bytes)
                switch parsed {
                case .completed, .failed:
                    context.completion = parsed
                default:
                    break
                }
                context.lastReport = bytes
            },
            Unmanaged.passUnretained(context).toOpaque()
        )
        let runLoop: CFRunLoop = CFRunLoopGetCurrent()
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        }

        var events: [Vader5DiagnosticEvent] = []
        func record(_ direction: Vader5DiagnosticDirection, _ message: String, _ bytes: [UInt8] = []) {
            let event = Vader5DiagnosticEvent(direction: direction, message: message, bytes: bytes)
            events.append(event)
            onEvent?(event)
        }
        func phase(_ phase: Vader5DongleUpdatePhase) { onPhase?(phase) }

        func send(_ report: [UInt8], stage: String) throws {
            var frame = report
            let writeResult = frame.withUnsafeMutableBufferPointer {
                IOHIDDeviceSetReport(
                    device, kIOHIDReportTypeOutput, 5,
                    $0.baseAddress!, $0.count)
            }
            guard writeResult == kIOReturnSuccess else {
                throw Vader5DongleUpdateError.writeFailed(writeResult)
            }
            record(.transmit, stage, report)
        }

        func waitForEcho(from marker: UInt64, timeout: TimeInterval, stage: String) throws {
            let deadline = Date().addingTimeInterval(timeout)
            while context.echoCount == marker && Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, min(0.05, deadline.timeIntervalSinceNow), false)
            }
            guard context.echoCount > marker else {
                throw Vader5DongleUpdateError.echoTimeout(stage: stage)
            }
        }

        // Start frame.
        phase(.starting)
        let marker = context.echoCount
        try send(Vader5HIDOTAProtocol.startReport(), stage: "SEND START")
        try waitForEcho(from: marker, timeout: echoTimeout, stage: "start")
        record(.receive, "ACK")

        // Data frames, each paced by its echo.
        let blockCount = (image.count + 15) / 16
        var nextBlock: UInt16 = 0
        while Int(nextBlock) * 16 < image.count {
            let packet = Vader5HIDOTAProtocol.dataReport(image: image, startingBlock: nextBlock)
            let frameMarker = context.echoCount
            try send(packet.report, stage: "SEND BLOCKS \(nextBlock)-\(packet.nextBlock - 1)")
            try waitForEcho(from: frameMarker, timeout: echoTimeout, stage: "block \(nextBlock)")
            if let completion = context.completion {
                if case let .failed(status) = completion {
                    throw Vader5DongleUpdateError.updateRejected(status)
                }
                throw Vader5DongleUpdateError.unexpectedResponse
            }
            nextBlock = packet.nextBlock
            record(.receive, "ACK")
            phase(.transferring(sent: Int(nextBlock), total: blockCount))
        }

        // Finish frame commits the image; the receiver validates before swapping.
        phase(.finishing)
        let lastBlock = nextBlock == 0 ? 0 : nextBlock - 1
        try send(Vader5HIDOTAProtocol.finishReport(lastBlock: lastBlock), stage: "SEND FINISH")

        let deadline = Date().addingTimeInterval(completionTimeout)
        while context.completion == nil && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, min(0.1, deadline.timeIntervalSinceNow), false)
        }
        guard let completion = context.completion else {
            throw Vader5DongleUpdateError.completionTimeout
        }
        switch completion {
        case .completed:
            record(.receive, "SUCCESS")
            phase(.completed)
        case let .failed(status):
            record(.receive, "REJECTED status 0x\(String(status, radix: 16))")
            throw Vader5DongleUpdateError.updateRejected(status)
        default:
            throw Vader5DongleUpdateError.unexpectedResponse
        }
        return events
    }
}

private final class OTAContext {
    var echoCount: UInt64 = 0
    var lastReport: [UInt8] = []
    var completion: Vader5HIDOTAProtocol.Response?
}
