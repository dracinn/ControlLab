import Foundation

/// Read-only codec recovered from the BS2X (`BurnTypeSixChip`) implementation
/// in Flydigi's updater. This type only transforms in-memory bytes and has no
/// device I/O.
public enum Vader5BS2XProtocol {
    public static let frameStart: [UInt8] = [0x5c, 0x73]
    public static let frameEnd: [UInt8] = [0x5c, 0x65]

    public enum Acknowledgement: Sendable, Equatable {
        case success(sequence: UInt8)
        case rejected(sequence: UInt8, returnCode: UInt8)
    }

    public enum CodecError: Error, Sendable, Equatable {
        case incompleteFrame
        case malformedEscape
        case invalidCRC
        case invalidAcknowledgement
    }

    /// Wraps a complete body, including its existing trailing XOR CRC.
    public static func frame(body: [UInt8]) -> [UInt8] {
        var result = frameStart
        result.reserveCapacity(body.count + 4)
        for byte in body {
            result.append(byte)
            if byte == 0x5c {
                result.append(byte)
            }
        }
        result.append(contentsOf: frameEnd)
        return result
    }

    /// Adds the sequence, command, payload, and recovered one-byte XOR CRC.
    public static func commandBody(
        sequence: UInt8,
        command: UInt8,
        payload: [UInt8] = []
    ) -> [UInt8] {
        var body = [sequence, command]
        body.append(contentsOf: payload)
        body.append(xorCRC(body))
        return body
    }

    public static func unframe(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count >= 4,
              bytes.starts(with: frameStart),
              bytes.suffix(frameEnd.count).elementsEqual(frameEnd) else {
            throw CodecError.incompleteFrame
        }

        let end = bytes.count - frameEnd.count
        var decoded: [UInt8] = []
        var index = frameStart.count
        while index < end {
            let byte = bytes[index]
            decoded.append(byte)
            if byte == 0x5c {
                guard index + 1 < end, bytes[index + 1] == 0x5c else {
                    throw CodecError.malformedEscape
                }
                index += 1
            }
            index += 1
        }
        return decoded
    }

    /// Parses the acknowledgement layout checked by `CheckRecvData`:
    /// sequence, type (0x02), reserved, return code, XOR CRC.
    public static func parseAcknowledgement(_ frame: [UInt8]) throws -> Acknowledgement {
        let body = try unframe(frame)
        guard body.count >= 5, body[1] == 0x02 else {
            throw CodecError.invalidAcknowledgement
        }
        guard xorCRC(Array(body.dropLast())) == body.last else {
            throw CodecError.invalidCRC
        }
        return body[3] == 0x01
            ? .success(sequence: body[0])
            : .rejected(sequence: body[0], returnCode: body[3])
    }

    /// Builds a device-to-host reply for in-memory simulator tests.
    public static func acknowledgementFrame(
        sequence: UInt8,
        reserved: UInt8 = 0,
        returnCode: UInt8 = 1
    ) -> [UInt8] {
        var body = [sequence, 0x02, reserved, returnCode]
        body.append(xorCRC(body))
        return frame(body: body)
    }

    public static func xorCRC<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0, ^)
    }
}

public struct Vader5BS2XRetryWindow: Sendable, Equatable {
    public let acknowledgementMilliseconds: Int
    public let totalMilliseconds: Int

    public init(acknowledgementMilliseconds: Int, totalMilliseconds: Int) {
        self.acknowledgementMilliseconds = max(1, acknowledgementMilliseconds)
        self.totalMilliseconds = max(0, totalMilliseconds)
    }

    /// Upper bound when each attempt consumes the complete acknowledgement
    /// window. Actual updater attempts can be fewer due to transfer overhead.
    public var maximumAttempts: Int {
        guard totalMilliseconds > 0 else { return 0 }
        return (totalMilliseconds + acknowledgementMilliseconds - 1)
            / acknowledgementMilliseconds
    }

    public static let ssb = Self(acknowledgementMilliseconds: 200, totalMilliseconds: 30_000)
    public static let partition = Self(acknowledgementMilliseconds: 500, totalMilliseconds: 30_000)
}
