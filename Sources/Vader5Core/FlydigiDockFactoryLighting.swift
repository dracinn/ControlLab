import Foundation

public enum FlydigiDockFactoryLightingError: Error, CustomStringConvertible,
    Sendable
{
    case malformedProtobuf
    case missingLightingConfiguration
    case unsupportedMode(Int)
    case unsupportedDirection(Int)
    case invalidFramePixelCount(expected: Int, actual: Int)
    case missingFrames

    public var description: String {
        switch self {
        case .malformedProtobuf:
            "The Flydigi factory lighting file is malformed."
        case .missingLightingConfiguration:
            "The Flydigi factory lighting file has no current LED configuration."
        case .unsupportedMode(let value):
            "The factory lighting file uses unsupported mode \(value)."
        case .unsupportedDirection(let value):
            "The factory lighting file uses unsupported direction \(value)."
        case .invalidFramePixelCount(let expected, let actual):
            "A factory lighting frame requires \(expected) pixels, but contains \(actual)."
        case .missingFrames:
            "The factory Default effect does not contain any animation frames."
        }
    }
}

/// Decodes the `currentLedConfig` stored in Space Station's packaged
/// `default_mapping_<deviceType>.dat` protobuf.
public enum FlydigiDockFactoryLighting {
    public static func decode(
        _ data: Data
    ) throws -> FlydigiDockLightingConfiguration {
        var root = ProtobufReader(bytes: Array(data))
        var encodedConfiguration: [UInt8]?
        while let field = try root.nextField() {
            if field.number == 7, case .bytes(let bytes) = field.value {
                encodedConfiguration = bytes
            }
        }
        guard let encodedConfiguration else {
            throw FlydigiDockFactoryLightingError.missingLightingConfiguration
        }
        return try decodeConfiguration(encodedConfiguration)
    }

    private static func decodeConfiguration(
        _ bytes: [UInt8]
    ) throws -> FlydigiDockLightingConfiguration {
        var reader = ProtobufReader(bytes: bytes)
        var modeValue = 0
        var period = 1
        var brightness = 100
        var colors: [Vader5RGBColor] = []
        var directionValue = 0
        var frames: [[Vader5RGBColor]] = []

        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, .varint(let value)):
                modeValue = Int(value)
            case (2, .varint(let value)):
                period = Int(value)
            case (3, .varint(let value)):
                brightness = Int(value)
            case (4, .bytes(let value)):
                colors.append(try decodeColor(value))
            case (6, .varint(let value)):
                directionValue = Int(value)
            case (7, .bytes(let value)):
                frames.append(try decodeFrame(value))
            default:
                break
            }
        }

        guard let mode = FlydigiDockLightingMode(
            rawValue: UInt8(clamping: modeValue))
        else {
            throw FlydigiDockFactoryLightingError.unsupportedMode(modeValue)
        }
        guard let direction = FlydigiDockLightingDirection(
            rawValue: UInt8(clamping: directionValue))
        else {
            throw FlydigiDockFactoryLightingError.unsupportedDirection(
                directionValue)
        }
        guard !frames.isEmpty else {
            throw FlydigiDockFactoryLightingError.missingFrames
        }
        for frame in frames where frame.count != FlydigiDockProtocol.pixelCount {
            throw FlydigiDockFactoryLightingError.invalidFramePixelCount(
                expected: FlydigiDockProtocol.pixelCount,
                actual: frame.count)
        }

        return .init(
            mode: mode,
            period: UInt8(clamping: period),
            brightness: UInt8(clamping: brightness),
            colors: colors,
            direction: direction,
            pixels: frames.flatMap { $0 })
    }

    private static func decodeFrame(
        _ bytes: [UInt8]
    ) throws -> [Vader5RGBColor] {
        var reader = ProtobufReader(bytes: bytes)
        var colors: [Vader5RGBColor] = []
        while let field = try reader.nextField() {
            if field.number == 2, case .bytes(let value) = field.value {
                colors.append(try decodeColor(value))
            }
        }
        return colors
    }

    private static func decodeColor(
        _ bytes: [UInt8]
    ) throws -> Vader5RGBColor {
        var reader = ProtobufReader(bytes: bytes)
        var red = 0
        var green = 0
        var blue = 0
        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, .varint(let value)): red = Int(value)
            case (2, .varint(let value)): green = Int(value)
            case (3, .varint(let value)): blue = Int(value)
            default: break
            }
        }
        return .init(
            red: UInt8(clamping: red),
            green: UInt8(clamping: green),
            blue: UInt8(clamping: blue))
    }
}

private struct ProtobufReader {
    enum Value {
        case varint(UInt64)
        case bytes([UInt8])
    }

    struct Field {
        let number: Int
        let value: Value
    }

    let bytes: [UInt8]
    var offset = 0

    mutating func nextField() throws -> Field? {
        guard offset < bytes.count else { return nil }
        let key = try readVarint()
        let number = Int(key >> 3)
        guard number > 0 else {
            throw FlydigiDockFactoryLightingError.malformedProtobuf
        }
        switch key & 0x07 {
        case 0:
            return .init(number: number, value: .varint(try readVarint()))
        case 1:
            try skip(8)
            return try nextField()
        case 2:
            let count = try readVarint()
            guard count <= UInt64(Int.max) else {
                throw FlydigiDockFactoryLightingError.malformedProtobuf
            }
            return .init(
                number: number,
                value: .bytes(try readBytes(count: Int(count))))
        case 5:
            try skip(4)
            return try nextField()
        default:
            throw FlydigiDockFactoryLightingError.malformedProtobuf
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard offset < bytes.count else {
                throw FlydigiDockFactoryLightingError.malformedProtobuf
            }
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << UInt64(shift)
            if byte & 0x80 == 0 { return result }
        }
        throw FlydigiDockFactoryLightingError.malformedProtobuf
    }

    private mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset <= bytes.count - count else {
            throw FlydigiDockFactoryLightingError.malformedProtobuf
        }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }

    private mutating func skip(_ count: Int) throws {
        guard count >= 0, offset <= bytes.count - count else {
            throw FlydigiDockFactoryLightingError.malformedProtobuf
        }
        offset += count
    }
}
