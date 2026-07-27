import CryptoKit
import Foundation

public struct Vader5FirmwarePackageInfo: Sendable, Equatable {
    public let fileName: String
    public let size: Int
    public let sha256: String
    public let magic: String
    public let isKnownContainer: Bool
    public let nearLinkLayout: Vader5NearLinkPackageLayout?

    public init(
        fileName: String, size: Int, sha256: String, magic: String,
        isKnownContainer: Bool, nearLinkLayout: Vader5NearLinkPackageLayout? = nil
    ) {
        self.fileName = fileName
        self.size = size
        self.sha256 = sha256
        self.magic = magic
        self.isKnownContainer = isKnownContainer
        self.nearLinkLayout = nearLinkLayout
    }
}

public struct Vader5NearLinkPackageLayout: Sendable, Equatable {
    public let outerHeaderSize: Int
    public let innerHeaderSize: Int
    public let descriptorOffset: Int
    public let subpackageOffset: Int
    public let subpackageLength: Int
    public let subpackageMagic: String
    public let payloadOffset: Int
    public let payloadLength: Int
    public let payloadHeader: String
    public let payloadSHA256: String
    public let payloadSHA256Matches: Bool
}

public enum Vader5FirmwarePackageInspector {
    public static let nearLinkMagic: [UInt8] = [0x4e, 0x15, 0x8d, 0xcb]

    public static func inspect(data: Data, fileName: String = "firmware.fwpkg") -> Vader5FirmwarePackageInfo {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let prefix = data.prefix(4)
        let isKnownContainer = Array(prefix) == nearLinkMagic
        return Vader5FirmwarePackageInfo(
            fileName: fileName,
            size: data.count,
            sha256: digest,
            magic: prefix.map { String(format: "%02X", $0) }.joined(separator: " "),
            isKnownContainer: isKnownContainer,
            nearLinkLayout: isKnownContainer ? parseNearLinkLayout(data) : nil
        )
    }

    public static func inspect(url: URL) throws -> Vader5FirmwarePackageInfo {
        try inspect(data: Data(contentsOf: url), fileName: url.lastPathComponent)
    }

    /// Parses only the bounds and descriptors observed in official BS20 packages.
    /// The protected firmware payload is never decrypted, extracted, or executed.
    public static func parseNearLinkLayout(_ data: Data) -> Vader5NearLinkPackageLayout? {
        guard hasMagic(data, at: 0),
              let outerHeaderSize = uint32(data, at: 8).map(Int.init),
              outerHeaderSize >= 16,
              hasMagic(data, at: outerHeaderSize),
              let innerHeaderSize = uint32(data, at: outerHeaderSize + 8).map(Int.init),
              innerHeaderSize >= 16 else { return nil }

        let descriptorOffset = outerHeaderSize + innerHeaderSize
        guard let subpackageOffset = uint32(data, at: descriptorOffset + 4).map(Int.init),
              let subpackageLength = uint32(data, at: descriptorOffset + 8).map(Int.init),
              validRange(offset: subpackageOffset, length: subpackageLength, count: data.count),
              subpackageOffset + 16 <= data.count else { return nil }

        let subpackageMagicBytes = data[subpackageOffset..<subpackageOffset + 4]
        let payloadDescriptor = subpackageOffset + 4
        guard let payloadOffset = uint32(data, at: payloadDescriptor + 4).map(Int.init),
              let payloadLength = uint32(data, at: payloadDescriptor + 8).map(Int.init),
              payloadDescriptor + 44 <= data.count,
              validRange(offset: payloadOffset, length: payloadLength, count: data.count),
              payloadOffset >= subpackageOffset,
              payloadOffset + payloadLength == subpackageOffset + subpackageLength,
              payloadOffset + 4 <= data.count else { return nil }

        let declaredDigest = data[payloadDescriptor + 12..<payloadDescriptor + 44]
        let calculatedDigest = SHA256.hash(data: data[payloadOffset..<payloadOffset + payloadLength])
        let declaredDigestHex = declaredDigest.map { String(format: "%02x", $0) }.joined()

        return Vader5NearLinkPackageLayout(
            outerHeaderSize: outerHeaderSize,
            innerHeaderSize: innerHeaderSize,
            descriptorOffset: descriptorOffset,
            subpackageOffset: subpackageOffset,
            subpackageLength: subpackageLength,
            subpackageMagic: asciiOrHex(subpackageMagicBytes),
            payloadOffset: payloadOffset,
            payloadLength: payloadLength,
            payloadHeader: data[payloadOffset..<payloadOffset + 4]
                .map { String(format: "%02X", $0) }.joined(separator: " "),
            payloadSHA256: declaredDigestHex,
            payloadSHA256Matches: Array(declaredDigest) == Array(calculatedDigest)
        )
    }

    private static func hasMagic(_ data: Data, at offset: Int) -> Bool {
        guard validRange(offset: offset, length: nearLinkMagic.count, count: data.count) else { return false }
        return Array(data[offset..<offset + nearLinkMagic.count]) == nearLinkMagic
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32? {
        guard validRange(offset: offset, length: 4, count: data.count) else { return nil }
        return UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func validRange(offset: Int, length: Int, count: Int) -> Bool {
        offset >= 0 && length >= 0 && offset <= count && length <= count - offset
    }

    private static func asciiOrHex(_ bytes: Data.SubSequence) -> String {
        let values = Array(bytes)
        if values.allSatisfy({ 0x20...0x7e ~= $0 }) {
            return String(bytes: values, encoding: .ascii) ?? ""
        }
        return values.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

public enum Vader5SimulationScenario: Sendable, Equatable {
    case success
    case crcError(block: UInt16)
    case timeout(block: UInt16)
    case invalidBlock(block: UInt16)
    case flashFull(block: UInt16)
    case disconnectOnce(block: UInt16)
    case corruptedPacketOnce(block: UInt16)
    case interrupted(block: UInt16)
    case unexpectedAcknowledgement(block: UInt16)
}

public struct Vader5DryRunPolicy: Sendable, Equatable {
    public var maxPacketRetries: Int
    public var maxRecoveryRestarts: Int

    public init(maxPacketRetries: Int = 0, maxRecoveryRestarts: Int = 0) {
        self.maxPacketRetries = max(0, maxPacketRetries)
        self.maxRecoveryRestarts = max(0, maxRecoveryRestarts)
    }
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
    case disconnected(UInt16)
    case interrupted(UInt16)
    case invalidReport(String)
    case imageTooLarge

    public var description: String {
        switch self {
        case .realHardwareWritesDisabled:
            "Real-hardware erase and write commands are disabled in Firmware Diagnostics."
        case let .timeout(block): "Simulated timeout at block \(block)."
        case let .rejected(block, status): "Block \(block) rejected with status \(status)."
        case .unexpectedResponse: "The simulated device returned an unexpected response."
        case let .disconnected(block): "Simulated disconnect at block \(block)."
        case let .interrupted(block): "Simulated interrupted update at block \(block)."
        case let .invalidReport(message): "Invalid simulated OTA report: \(message)."
        case .imageTooLarge: "The image exceeds the recovered 16-bit OTA block address space."
        }
    }
}

/// The only transport accepted by the diagnostic updater. It has no HID device handle and
/// cannot send a report to physical hardware.
public final class Vader5DryRunTransport: @unchecked Sendable {
    public private(set) var events: [Vader5DiagnosticEvent] = []
    private let scenario: Vader5SimulationScenario
    private var started = false
    private var expectedBlock: UInt16 = 0
    private var injectedOneShotFaults: Set<UInt16> = []

    public init(scenario: Vader5SimulationScenario = .success) {
        self.scenario = scenario
    }

    public func exchange(_ report: [UInt8], block: UInt16?) throws -> Vader5HIDOTAProtocol.Response {
        let isStart = block == nil && report.prefix(6) == [0x05, 0x02, 0x02, 0x00, 0x01, 0xff]
        let label: String
        if isStart {
            label = "SEND START"
            started = true
            expectedBlock = 0
        } else if let block {
            label = "SEND BLOCK \(block)"
        } else {
            label = "SEND FINISH"
        }
        events.append(.init(direction: .transmit, message: label, bytes: report))

        guard started else { throw Vader5FirmwareTransportError.unexpectedResponse }
        if let block {
            switch scenario {
            case .timeout(let target) where target == block:
                events.append(.init(direction: .status, message: "TIMEOUT at block \(block)"))
                throw Vader5FirmwareTransportError.timeout(block)
            case .crcError(let target) where target == block:
                return recordFailure(block: block, status: 1, name: "CRC ERROR")
            case .invalidBlock(let target) where target == block:
                return recordFailure(block: block, status: 2, name: "INVALID BLOCK")
            case .flashFull(let target) where target == block:
                return recordFailure(block: block, status: 3, name: "FLASH FULL")
            case .disconnectOnce(let target) where target == block && injectedOneShotFaults.insert(block).inserted:
                started = false
                events.append(.init(direction: .status, message: "DISCONNECTED at block \(block)"))
                throw Vader5FirmwareTransportError.disconnected(block)
            case .corruptedPacketOnce(let target) where target == block && injectedOneShotFaults.insert(block).inserted:
                return recordFailure(block: block, status: 1, name: "CORRUPTED PACKET")
            case .interrupted(let target) where target == block && injectedOneShotFaults.insert(block).inserted:
                started = false
                events.append(.init(direction: .status, message: "INTERRUPTED at block \(block)"))
                throw Vader5FirmwareTransportError.interrupted(block)
            case .unexpectedAcknowledgement(let target) where target == block:
                events.append(.init(direction: .receive, message: "UNEXPECTED COMPLETION"))
                return .completed
            default: break
            }
            let nextBlock = try validateDataReport(report, expectedBlock: expectedBlock)
            guard block == expectedBlock else {
                return recordFailure(block: block, status: 2, name: "OUT OF ORDER")
            }
            expectedBlock = nextBlock
        } else if !isStart {
            let reportedLastBlock = UInt16(report[safe: 6] ?? 0) | UInt16(report[safe: 7] ?? 0) << 8
            let expectedLastBlock = expectedBlock == 0 ? 0 : expectedBlock - 1
            guard report.prefix(6) == [0x05, 0x02, 0x06, 0x00, 0x02, 0xff],
                  reportedLastBlock == expectedLastBlock else {
                throw Vader5FirmwareTransportError.invalidReport("finish block does not match accepted data")
            }
        }

        let response: Vader5HIDOTAProtocol.Response = block == nil && label == "SEND FINISH"
            ? .completed : .acknowledgement
        events.append(.init(direction: .receive, message: response == .completed ? "SUCCESS" : "ACK"))
        return response
    }

    public func restartForRecovery() {
        started = false
        expectedBlock = 0
        events.append(.init(direction: .status, message: "RECOVERY RESTART FROM BLOCK 0"))
    }

    private func validateDataReport(_ report: [UInt8], expectedBlock: UInt16) throws -> UInt16 {
        guard report.count == Vader5HIDOTAProtocol.reportLength,
              report[0] == 0x05, report[1] == 0x02, report[3] == 0 else {
            throw Vader5FirmwareTransportError.invalidReport("bad report header or length")
        }
        let payloadLength = Int(report[2])
        guard payloadLength > 0, payloadLength <= 60, payloadLength.isMultiple(of: 20) else {
            throw Vader5FirmwareTransportError.invalidReport("invalid record payload length")
        }
        var next = expectedBlock
        for offset in stride(from: 4, to: 4 + payloadLength, by: 20) {
            let block = UInt16(report[offset]) | UInt16(report[offset + 1]) << 8
            guard block == next else {
                throw Vader5FirmwareTransportError.invalidReport("non-sequential block \(block), expected \(next)")
            }
            let crcOffset = offset + 18
            let reportedCRC = UInt16(report[crcOffset]) | UInt16(report[crcOffset + 1]) << 8
            let calculatedCRC = Vader5HIDOTAProtocol.crc16(Array(report[offset..<crcOffset]))
            guard reportedCRC == calculatedCRC else {
                throw Vader5FirmwareTransportError.invalidReport("CRC mismatch at block \(block)")
            }
            next &+= 1
        }
        return next
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
        scenario: Vader5SimulationScenario = .success,
        policy: Vader5DryRunPolicy = .init()
    ) throws -> Vader5DryRunResult {
        guard image.count <= (Int(UInt16.max) + 1) * 16 else {
            throw Vader5FirmwareTransportError.imageTooLarge
        }
        let transport = Vader5DryRunTransport(scenario: scenario)
        var recoveryRestarts = 0

        while true {
            do {
                let blockCount = try runOnce(image: image, transport: transport, policy: policy)
                return Vader5DryRunResult(blockCount: blockCount, events: transport.events)
            } catch let failure as Vader5FirmwareTransportError {
                switch failure {
                case .disconnected, .interrupted: break
                default: throw failure
                }
                guard recoveryRestarts < policy.maxRecoveryRestarts else { throw failure }
                recoveryRestarts += 1
                transport.restartForRecovery()
            }
        }
    }

    private static func runOnce(
        image: Data, transport: Vader5DryRunTransport, policy: Vader5DryRunPolicy
    ) throws -> Int {
        guard try transport.exchange(Vader5HIDOTAProtocol.startReport(), block: nil) == .acknowledgement else {
            throw Vader5FirmwareTransportError.unexpectedResponse
        }

        var nextBlock: UInt16 = 0
        while Int(nextBlock) * 16 < image.count {
            let firstBlock = nextBlock
            let packet = Vader5HIDOTAProtocol.dataReport(image: image, startingBlock: nextBlock)
            var retries = 0
            while true {
                do {
                    let response = try transport.exchange(packet.report, block: firstBlock)
                    if case let .failed(status) = response {
                        guard retries < policy.maxPacketRetries, status == 1 || status == 2 else {
                            throw Vader5FirmwareTransportError.rejected(block: firstBlock, status: status)
                        }
                        retries += 1
                        transport.recordRetry(block: firstBlock, attempt: retries)
                        continue
                    }
                    guard response == .acknowledgement else {
                        throw Vader5FirmwareTransportError.unexpectedResponse
                    }
                    break
                } catch let failure as Vader5FirmwareTransportError {
                    guard case .timeout = failure else { throw failure }
                    guard retries < policy.maxPacketRetries else { throw failure }
                    retries += 1
                    transport.recordRetry(block: firstBlock, attempt: retries)
                }
            }
            nextBlock = packet.nextBlock
        }

        let lastBlock = nextBlock == 0 ? 0 : nextBlock - 1
        guard try transport.exchange(Vader5HIDOTAProtocol.finishReport(lastBlock: lastBlock), block: nil) == .completed else {
            throw Vader5FirmwareTransportError.unexpectedResponse
        }
        return Int(nextBlock)
    }

    public static func refuseRealHardwareUpdate() throws -> Never {
        throw Vader5FirmwareTransportError.realHardwareWritesDisabled
    }
}

private extension Vader5DryRunTransport {
    func recordRetry(block: UInt16, attempt: Int) {
        events.append(.init(direction: .status, message: "RETRY BLOCK \(block), ATTEMPT \(attempt)"))
    }
}

private extension Collection where Index == Int {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
