import Foundation
import IOKit.hid
import Vader5CoreC

final class VirtualGamepad {
    private var device: UnsafeMutableRawPointer?

    private static let descriptor: [UInt8] = [
        0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01,
        0x05, 0x09, 0x19, 0x01, 0x29, 0x12, 0x15, 0x00,
        0x25, 0x01, 0x75, 0x01, 0x95, 0x12, 0x81, 0x02,
        0x75, 0x01, 0x95, 0x06, 0x81, 0x03,
        0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07,
        0x35, 0x00, 0x46, 0x3B, 0x01, 0x65, 0x14, 0x75,
        0x04, 0x95, 0x01, 0x81, 0x42, 0x75, 0x04, 0x95,
        0x01, 0x81, 0x03, 0x09, 0x30, 0x09, 0x31, 0x09,
        0x33, 0x09, 0x34, 0x16, 0x01, 0x80, 0x26, 0xFF,
        0x7F, 0x75, 0x10, 0x95, 0x04, 0x81, 0x02, 0x09,
        0x32, 0x09, 0x35, 0x15, 0x00, 0x26, 0xFF, 0x00,
        0x75, 0x08, 0x95, 0x02, 0x81, 0x02, 0xC0,
    ]

    func start() throws {
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey: Data(Self.descriptor),
            kIOHIDTransportKey: "Virtual",
            kIOHIDManufacturerKey: "Vader5 macOS",
            kIOHIDProductKey: "Vader 5 Pro Virtual Gamepad",
            kIOHIDVendorIDKey: Vader5Protocol.vendorID,
            kIOHIDProductIDKey: Vader5Protocol.productID,
            kIOHIDVersionNumberKey: 1,
            kIOHIDSerialNumberKey: "VADER5-MACOS",
        ]
        device = V5VirtualHIDCreate(properties as CFDictionary)
        guard device != nil else { throw Vader5Error.virtualDeviceCreation }
    }

    func send(_ state: Vader5State) {
        guard let device else { return }
        let report = Vader5Protocol.virtualReport(for: state)
        report.withUnsafeBufferPointer {
            _ = V5VirtualHIDHandleReport(device, $0.baseAddress!, $0.count)
        }
    }

    func stop() {
        if let device { V5VirtualHIDRelease(device) }
        device = nil
    }

    deinit { stop() }
}
