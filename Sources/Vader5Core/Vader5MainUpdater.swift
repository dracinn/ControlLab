import Foundation
import IOKit
import IOKit.hid
import IOKit.usb.IOUSBLib

public enum Vader5MainUpdateError: Error, CustomStringConvertible, Sendable {
    case controllerNotFound
    case deviceOpen(IOReturn)
    case bootSwitchFailed(IOReturn)
    case bootDeviceTimeout
    case usbPluginFailed
    case commandFailed(stage: String)
    case verifyMismatch(offset: Int)
    case invalidImage(String)

    public var description: String {
        switch self {
        case .controllerNotFound:
            "The controller command interface (FF a0) was not found. Connect the controller over USB-C."
        case let .deviceOpen(code):
            "Could not open the controller (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case let .bootSwitchFailed(code):
            "The firmware-upgrade-mode command failed (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .bootDeviceTimeout:
            "The controller did not re-enumerate as the Megahunt boot device (0483:5720)."
        case .usbPluginFailed:
            "Could not acquire the Megahunt boot device via IOUSBLib."
        case let .commandFailed(stage):
            "The bootloader rejected or dropped a command during \(stage)."
        case let .verifyMismatch(offset):
            "Flash verification failed at offset \(offset)."
        case let .invalidImage(reason):
            "Not a valid Megahunt image: \(reason)."
        }
    }
}

public enum Vader5MainUpdatePhase: Sendable, Equatable {
    case enteringBootMode
    case waitingForBootDevice
    case erasing
    case programming(sent: Int, total: Int)
    case writingFlag
    case verifying(read: Int, total: Int)
    case committing
    case completed
}

/// Updates the controller's Megahunt main chip. The flow, recovered from the
/// official `hid_boot_command.exe` and verified end-to-end on hardware:
///
///   1. The 32-byte SwitchToFirmwareUpgradeMode command (endpoint 0x06,
///      `5a a5 1f 03 <module=0> <crc>`) is sent over the controller's FFA0
///      command interface.
///   2. The controller re-enumerates as `0483:5720` "MH Offline Downloader".
///      macOS cannot parse its report descriptor, so it never appears through
///      IOHIDManager — the updater talks to it directly with EP0 class
///      requests (SET_REPORT/GET_REPORT, report type "feature").
///   3. Erase/session reset:    SET feat01 `[01][00000000][00000000]` (9 B)
///      Declare image size:     SET feat04 `[04][size32]`              (5 B)
///      Program:                SET feat02 `[02][len][00][data≤60]`    (63 B)
///      Write validity flag:    SET feat03 `[03][a5a5a5a5][crc32][size]` (13 B)
///      Read-back reset:        SET feat01 again
///      Verify:                 GET feat02 per chunk, compared in memory
///      Flag check:             GET feat03
///      Commit/run:             SET feat05 `[05 a5a5a5a5]`             (5 B)
///
/// The commit step only runs after every programmed byte verifies, so an
/// interrupted update leaves the device in the ISP loader (recoverable by
/// simply running the update again) rather than booting a partial image.
public final class Vader5MainUpdater: @unchecked Sendable {
    public static let bootVendorID = 0x0483
    public static let bootProductID = 0x5720

    public var onEvent: (@Sendable (Vader5DiagnosticEvent) -> Void)?
    public var onPhase: (@Sendable (Vader5MainUpdatePhase) -> Void)?

    private let bootDeviceTimeout: TimeInterval

    public init(bootDeviceTimeout: TimeInterval = 15) {
        self.bootDeviceTimeout = bootDeviceTimeout
    }

    /// Whether the controller's FFA0 command interface is currently present.
    public static func isChannelPresent() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: Vader5Protocol.usagePage,
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

    /// Whether the Megahunt boot device is currently enumerated.
    public static func isBootDevicePresent() -> Bool {
        bootDeviceService() != 0
    }

    /// Minimal sanity check: the image must look like an ARM Cortex-M flash
    /// image (word-aligned stack pointer in SRAM, reset vector in flash).
    public static func validate(image: Data) throws {
        guard image.count >= 16 else {
            throw Vader5MainUpdateError.invalidImage("file is too small")
        }
        let sp = image.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
        let reset = image.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).littleEndian }
        guard (sp & 0x2FFC_0000) == 0x2000_0000 else {
            throw Vader5MainUpdateError.invalidImage("missing ARM stack pointer (0x\(String(sp, radix: 16)))")
        }
        guard (reset & 0xFF00_0000) == 0x0800_0000 else {
            throw Vader5MainUpdateError.invalidImage("missing ARM reset vector (0x\(String(reset, radix: 16)))")
        }
    }

    // MARK: - Update

    /// Sends the firmware-upgrade-mode command to the controller's main chip
    /// (ChipModule.ChipMain = 0) over the FFA0 interface, then performs the
    /// full program/verify/commit sequence once the boot device enumerates.
    public func update(image: Data) throws {
        try Self.validate(image: image)

        onPhase?(.enteringBootMode)
        try sendBootSwitch()
        emit(direction: .transmit, message: "Switch main chip to boot mode")

        onPhase?(.waitingForBootDevice)
        let transport = try waitForBootDevice()
        defer { transport.close() }
        emit(direction: .receive, message: "Boot device 0483:5720 present")

        try program(image: image, transport: transport)
        try verify(image: image, transport: transport)

        onPhase?(.committing)
        var commit: [UInt8] = [0x05, 0xa5, 0xa5, 0xa5, 0xa5]
        try transport.setFeature(id: 5, bytes: &commit, length: 5, stage: "commit")
        emit(direction: .transmit, message: "Commit/run command sent")

        onPhase?(.completed)
        emit(direction: .receive, message: "Main chip update committed")
    }

    // MARK: - Boot-mode trigger

    private func sendBootSwitch() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDPrimaryUsagePageKey: Vader5Protocol.usagePage,
        ] as CFDictionary)
        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw Vader5MainUpdateError.controllerNotFound
        }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let device = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>)?.first else {
            throw Vader5MainUpdateError.controllerNotFound
        }
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            throw Vader5MainUpdateError.deviceOpen(kIOReturnError)
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        // NewXInput SwitchToFirmwareUpgradeMode: 32-byte report,
        // [0]=0x06 endpoint, [1..2]=5a a5, [3]=0x1f, [4]=0x03 len,
        // [5]=ChipMain(0), [6]=crc = 0x1f+0x03+0x00.
        var report = [UInt8](repeating: 0, count: 32)
        report[0] = 0x06
        report[1] = 0x5a
        report[2] = 0xa5
        report[3] = 0x1f
        report[4] = 0x03
        report[5] = 0x00
        report[6] = 0x22
        let result = report.withUnsafeBytes {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, report.count)
        }
        guard result == kIOReturnSuccess else {
            throw Vader5MainUpdateError.bootSwitchFailed(result)
        }
    }

    private func waitForBootDevice() throws -> BootTransport {
        let deadline = Date().addingTimeInterval(bootDeviceTimeout)
        while Date() < deadline {
            if let transport = BootTransport() {
                return transport
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        throw Vader5MainUpdateError.bootDeviceTimeout
    }

    private static func bootDeviceService() -> io_service_t {
        let match = NSMutableDictionary(dictionary: [
            "IOProviderClass": "IOUSBHostDevice",
            "idVendor": bootVendorID,
            "idProduct": bootProductID,
        ])
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else {
            return 0
        }
        let service = IOIteratorNext(iter)
        IOObjectRelease(iter)
        return service
    }

    // MARK: - Program / verify

    private func program(image: Data, transport: BootTransport) throws {
        onPhase?(.erasing)

        // Session reset / erase: SET feat01 [01][00000000][00000000]
        var reset = [UInt8](repeating: 0, count: 9)
        reset[0] = 0x01
        try transport.setFeature(id: 1, bytes: &reset, length: 9, stage: "erase")
        emit(direction: .transmit, message: "Erase/begin command")
        Thread.sleep(forTimeInterval: 0.3)

        // Declare size: SET feat04 [04][size32 LE]
        var sizeReport: [UInt8] = [
            0x04,
            UInt8(image.count & 0xff),
            UInt8((image.count >> 8) & 0xff),
            UInt8((image.count >> 16) & 0xff),
            UInt8((image.count >> 24) & 0xff),
        ]
        try transport.setFeature(id: 4, bytes: &sizeReport, length: 5, stage: "set-size")
        emit(direction: .transmit, message: "Image size \(image.count) declared")
        Thread.sleep(forTimeInterval: 0.3)

        // Program: 60-byte chunks via SET feat02 [02][len][00][data]
        var offset = 0
        while offset < image.count {
            let n = min(60, image.count - offset)
            var chunk = [UInt8](repeating: 0, count: 63)
            chunk[0] = 0x02
            chunk[1] = UInt8(n)
            chunk.replaceSubrange(3..<(3 + n), with: image[offset..<(offset + n)])
            try transport.setFeature(id: 2, bytes: &chunk, length: 63, stage: "program")
            offset += n
            onPhase?(.programming(sent: offset, total: image.count))
            if offset % 6000 < 60 {
                emit(direction: .transmit, message: "program \(offset)/\(image.count)")
            }
        }

        onPhase?(.writingFlag)

        // Validity flag: SET feat03 [03][a5a5a5a5][crc32-MPEG2][size32]
        let crc = Self.crc32Mpeg2(image)
        var flag: [UInt8] = [
            0x03, 0xa5, 0xa5, 0xa5, 0xa5,
            UInt8(crc & 0xff), UInt8((crc >> 8) & 0xff),
            UInt8((crc >> 16) & 0xff), UInt8((crc >> 24) & 0xff),
            UInt8(image.count & 0xff), UInt8((image.count >> 8) & 0xff),
            UInt8((image.count >> 16) & 0xff), UInt8((image.count >> 24) & 0xff),
        ]
        try transport.setFeature(id: 3, bytes: &flag, length: 13, stage: "flag")
        emit(direction: .transmit, message: "Validity flag written (crc 0x\(String(crc, radix: 16)))")
    }

    private func verify(image: Data, transport: BootTransport) throws {
        // Reset read pointer.
        var reset = [UInt8](repeating: 0, count: 9)
        reset[0] = 0x01
        try transport.setFeature(id: 1, bytes: &reset, length: 9, stage: "verify-reset")
        Thread.sleep(forTimeInterval: 0.3)

        var offset = 0
        while offset < image.count {
            let n = min(60, image.count - offset)
            var buf = [UInt8](repeating: 0, count: 63)
            try transport.getFeature(id: 2, bytes: &buf, length: 63, stage: "verify")
            if !image[offset..<(offset + n)].elementsEqual(buf[3..<(3 + n)]) {
                throw Vader5MainUpdateError.verifyMismatch(offset: offset)
            }
            offset += n
            onPhase?(.verifying(read: offset, total: image.count))
        }

        var flag = [UInt8](repeating: 0, count: 13)
        try transport.getFeature(id: 3, bytes: &flag, length: 13, stage: "flag-read")
        emit(
            direction: .receive,
            message: "flag readback \(flag.map { String(format: "%02x", $0) }.joined(separator: " "))"
        )
    }

    // MARK: - CRC-32 (Megahunt: poly 0x04C11DB7, MSB-first, init 0xFFFFFFFF)

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i) << 24
            for _ in 0..<8 {
                c = (c & 0x8000_0000) != 0 ? (c << 1) ^ 0x04C1_1DB7 : (c << 1)
            }
            return c
        }
    }()

    public static func crc32Mpeg2(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc << 8) ^ crcTable[Int(((crc >> 24) ^ UInt32(byte)) & 0xff)]
        }
        return crc
    }

    private func emit(direction: Vader5DiagnosticDirection, message: String) {
        onEvent?(Vader5DiagnosticEvent(direction: direction, message: message))
    }
}

// MARK: - EP0 transport for the Megahunt boot device

/// The "MH Offline Downloader" boot interface advertises bInterfaceClass 3 but
/// macOS never creates an IOHIDDevice for it (unparseable report descriptor),
/// so feature reports must go straight to EP0 as class requests — exactly what
/// hid_send_feature_report/hid_get_feature_report resolve to on any OS.
private final class BootTransport {
    private var device: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?

    init?() {
        let match = NSMutableDictionary(dictionary: [
            "IOProviderClass": "IOUSBHostDevice",
            "idVendor": Vader5MainUpdater.bootVendorID,
            "idProduct": Vader5MainUpdater.bootProductID,
        ])
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iter) == KERN_SUCCESS else {
            return nil
        }
        let service = IOIteratorNext(iter)
        IOObjectRelease(iter)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var pluginPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        let pluginID = CFUUIDGetConstantUUIDWithBytes(
            nil,
            0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
            0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F
        )
        let usbDeviceUCID = CFUUIDGetConstantUUIDWithBytes(
            nil,
            0x9D, 0xC7, 0xB7, 0x80, 0x9E, 0xC0, 0x11, 0xD4,
            0xA5, 0x4F, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
        )
        guard IOCreatePlugInInterfaceForService(service, usbDeviceUCID, pluginID, &pluginPtr, &score) == kIOReturnSuccess,
              let plugin = pluginPtr
        else { return nil }
        defer { _ = plugin.pointee?.pointee.Release(pluginPtr) }

        let deviceInterfaceID = CFUUIDGetConstantUUIDWithBytes(
            nil,
            0x5C, 0x81, 0x87, 0xD0, 0x9E, 0xF3, 0x11, 0xD4,
            0x8B, 0x45, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61
        )
        var raw: LPVOID?
        guard plugin.pointee?.pointee.QueryInterface(
            pluginPtr, CFUUIDGetUUIDBytes(deviceInterfaceID), &raw
        ) == S_OK, let raw else { return nil }

        device = raw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface>?.self)
        guard device?.pointee?.pointee.USBDeviceOpen(device) == kIOReturnSuccess else {
            return nil
        }
    }

    func close() {
        _ = device?.pointee?.pointee.USBDeviceClose(device)
        if let device { _ = device.pointee?.pointee.Release(device) }
    }

    /// SET_REPORT (feature): bmRequestType 0x21, bRequest 0x09,
    /// wValue 0x03xx, wIndex 0 — three retries, matching the official tool.
    func setFeature(id: Int, bytes: inout [UInt8], length: Int, stage: String) throws {
        bytes[0] = UInt8(id)
        var last = kIOReturnSuccess
        for _ in 0..<3 {
            let result = bytes.withUnsafeMutableBytes { ptr -> IOReturn in
                var req = IOUSBDevRequest(
                    bmRequestType: 0x21, bRequest: 0x09,
                    wValue: UInt16(0x0300 | id), wIndex: 0,
                    wLength: UInt16(length), pData: ptr.baseAddress, wLenDone: 0
                )
                return device!.pointee!.pointee.DeviceRequest(device, &req)
            }
            if result == kIOReturnSuccess { return }
            last = result
        }
        throw Vader5MainUpdateError.commandFailed(stage: "\(stage) (0x\(String(UInt32(bitPattern: last), radix: 16)))")
    }

    /// GET_REPORT (feature): bmRequestType 0xa1, bRequest 0x01,
    /// wValue 0x03xx, wIndex 0 — three retries.
    func getFeature(id: Int, bytes: inout [UInt8], length: Int, stage: String) throws {
        var last = kIOReturnSuccess
        for _ in 0..<3 {
            bytes[0] = UInt8(id)
            let result = bytes.withUnsafeMutableBytes { ptr -> IOReturn in
                var req = IOUSBDevRequest(
                    bmRequestType: 0xa1, bRequest: 0x01,
                    wValue: UInt16(0x0300 | id), wIndex: 0,
                    wLength: UInt16(length), pData: ptr.baseAddress, wLenDone: 0
                )
                return device!.pointee!.pointee.DeviceRequest(device, &req)
            }
            if result == kIOReturnSuccess { return }
            last = result
        }
        throw Vader5MainUpdateError.commandFailed(stage: "\(stage) (0x\(String(UInt32(bitPattern: last), radix: 16)))")
    }
}
