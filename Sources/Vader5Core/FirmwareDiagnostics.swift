import CryptoKit
import Foundation

public struct Vader5FirmwarePackageInfo: Sendable, Equatable {
    public let fileName: String
    public let size: Int
    public let sha256: String
    public let magic: String
    public let isKnownContainer: Bool

    public init(fileName: String, size: Int, sha256: String, magic: String, isKnownContainer: Bool) {
        self.fileName = fileName
        self.size = size
        self.sha256 = sha256
        self.magic = magic
        self.isKnownContainer = isKnownContainer
    }
}

public enum Vader5FirmwarePackageInspector {
    public static let nearLinkMagic: [UInt8] = [0x4e, 0x15, 0x8d, 0xcb]

    public static func inspect(data: Data, fileName: String = "firmware.fwpkg") -> Vader5FirmwarePackageInfo {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let prefix = data.prefix(4)
        return Vader5FirmwarePackageInfo(
            fileName: fileName,
            size: data.count,
            sha256: digest,
            magic: prefix.map { String(format: "%02X", $0) }.joined(separator: " "),
            isKnownContainer: Array(prefix) == nearLinkMagic
        )
    }

    public static func inspect(url: URL) throws -> Vader5FirmwarePackageInfo {
        try inspect(data: Data(contentsOf: url), fileName: url.lastPathComponent)
    }
}

public enum Vader5SimulationScenario: Sendable, Equatable {
    case success
    case crcError(block: UInt16)
    case timeout(block: UInt16)
    case invalidBlock(block: UInt16)
    case flashFull(block: UInt16)
}

public enum Vader5DiagnosticDirection: String, Sendable, Equatable {
    case transmit = "TX"
    case receive = "RX"
    case status = "STATUS"
}

public struct Vader5DiagnosticEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let direction: Vader5DiagnosticDirection
    public let message: String
    public let bytes: [UInt8]

    public init(
        id: UUID = UUID(), timestamp: Date = Date(), direction: Vader5DiagnosticDirection,
        message: String, bytes: [UInt8] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.direction = direction
        self.message = message
        self.bytes = bytes
    }
}

public enum Vader5FirmwareTransportError: Error, Sendable, Equatable, CustomStringConvertible {
    case realHardwareWritesDisabled
    case timeout(UInt16)
    case rejected(block: UInt16, status: UInt8)
    case unexpectedResponse

    public var description: String {
        switch self {
        case .realHardwareWritesDisabled:
            "Real-hardware erase and write commands are disabled in Firmware Diagnostics."
        case let .timeout(block): "Simulated timeout at block \(block)."
        case let .rejected(block, status): "Block \(block) rejected with status \(status)."
        case .unexpectedResponse: "The simulated device returned an unexpected response."
        }
    }
}

/// The only transport accepted by the diagnostic updater. It has no HID device handle and
/// cannot send a report to physical hardware.
public final class Vader5DryRunTransport: @unchecked Sendable {
    public private(set) var events: [Vader5DiagnosticEvent] = []
    private let scenario: Vader5SimulationScenario
    private var started = false

    public init(scenario: Vader5SimulationScenario = .success) {
        self.scenario = scenario
    }

    public func exchange(_ report: [UInt8], block: UInt16?) throws -> Vader5HIDOTAProtocol.Response {
        let label: String
        if block == nil && report.prefix(6) == [0x05, 0x02, 0x02, 0x00, 0x01, 0xff] {
            label = "SEND START"
            started = true
        } else if let block {
            label = "SEND BLOCK \(block)"
        } else {
            label = "SEND FINISH"
        }
        events.append(.init(direction: .transmit, message: label, bytes: report))

        guard started else { throw Vader5FirmwareTransportError.unexpectedResponse }
        if let block {
            switch scenario {
            case .timeout(block):
                events.append(.init(direction: .status, message: "TIMEOUT at block \(block)"))
                throw Vader5FirmwareTransportError.timeout(block)
            case .crcError(block): return recordFailure(block: block, status: 1, name: "CRC ERROR")
            case .invalidBlock(block): return recordFailure(block: block, status: 2, name: "INVALID BLOCK")
            case .flashFull(block): return recordFailure(block: block, status: 3, name: "FLASH FULL")
            default: break
            }
        }

        let response: Vader5HIDOTAProtocol.Response = block == nil && label == "SEND FINISH"
            ? .completed : .acknowledgement
        events.append(.init(direction: .receive, message: response == .completed ? "SUCCESS" : "ACK"))
        return response
    }

    private func recordFailure(block: UInt16, status: UInt8, name: String) -> Vader5HIDOTAProtocol.Response {
        events.append(.init(direction: .receive, message: "\(name) at block \(block)"))
        return .failed(status)
    }
}

public struct Vader5DryRunResult: Sendable, Equatable {
    public let blockCount: Int
    public let events: [Vader5DiagnosticEvent]
}

public enum Vader5DiagnosticUpdater {
    /// Builds every recovered OTA report and exchanges it only with an in-memory simulator.
    /// There is deliberately no overload accepting IOHIDDevice or a generic writable transport.
    public static func run(
        image: Data,
        scenario: Vader5SimulationScenario = .success
    ) throws -> Vader5DryRunResult {
        let transport = Vader5DryRunTransport(scenario: scenario)
        guard try transport.exchange(Vader5HIDOTAProtocol.startReport(), block: nil) == .acknowledgement else {
            throw Vader5FirmwareTransportError.unexpectedResponse
        }

        var nextBlock: UInt16 = 0
        while Int(nextBlock) * 16 < image.count {
            let firstBlock = nextBlock
            let packet = Vader5HIDOTAProtocol.dataReport(image: image, startingBlock: nextBlock)
            let response = try transport.exchange(packet.report, block: firstBlock)
            if case let .failed(status) = response {
                throw Vader5FirmwareTransportError.rejected(block: firstBlock, status: status)
            }
            guard response == .acknowledgement else { throw Vader5FirmwareTransportError.unexpectedResponse }
            nextBlock = packet.nextBlock
        }

        let lastBlock = nextBlock == 0 ? 0 : nextBlock - 1
        guard try transport.exchange(Vader5HIDOTAProtocol.finishReport(lastBlock: lastBlock), block: nil) == .completed else {
            throw Vader5FirmwareTransportError.unexpectedResponse
        }
        return Vader5DryRunResult(blockCount: Int(nextBlock), events: transport.events)
    }

    public static func refuseRealHardwareUpdate() throws -> Never {
        throw Vader5FirmwareTransportError.realHardwareWritesDisabled
    }
}
