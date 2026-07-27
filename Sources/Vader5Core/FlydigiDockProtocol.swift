import Foundation

public enum FlydigiDockProtocolError: Error, CustomStringConvertible, Sendable {
    case invalidPixelCount(expected: Int, actual: Int)
    case invalidAnimationPixelCount(frameSize: Int, actual: Int)
    case tooManyFrames(maximum: Int, actual: Int)
    case invalidColorCount(maximum: Int, actual: Int)
    case missingFactoryDefaultFrames

    public var description: String {
        switch self {
        case .invalidPixelCount(let expected, let actual):
            "The dock requires \(expected) pixels, but received \(actual)."
        case .invalidAnimationPixelCount(let frameSize, let actual):
            "Dock animation pixels must contain complete \(frameSize)-pixel frames, but received \(actual) pixels."
        case .tooManyFrames(let maximum, let actual):
            "The dock supports at most \(maximum) animation frames, but received \(actual)."
        case .invalidColorCount(let maximum, let actual):
            "The dock supports at most \(maximum) effect colors, but received \(actual)."
        case .missingFactoryDefaultFrames:
            "Default lighting requires a validated Flydigi factory animation."
        }
    }
}

public enum FlydigiDockLightingMode: UInt8, Codable, CaseIterable, Sendable,
    Equatable
{
    case off = 0
    case solid = 1
    case deviceDefault = 2
    case custom = 3
    case diagonalFlow = 4
    case breathing = 5
    case gradient = 6
    case waveGradient = 7
    case rainbow = 8
    case pulse = 9

    public var title: String {
        switch self {
        case .off: "Off"
        case .solid: "Solid"
        case .deviceDefault: "Default"
        case .custom: "Custom"
        case .diagonalFlow: "Diagonal flow"
        case .breathing: "Breathing"
        case .gradient: "Gradient"
        case .waveGradient: "Wave gradient"
        case .rainbow: "Rainbow"
        case .pulse: "Pulse"
        }
    }

    public var usesColors: Bool {
        switch self {
        case .solid, .custom, .diagonalFlow, .breathing, .waveGradient, .pulse:
            true
        default:
            false
        }
    }

    public var usesDirection: Bool {
        self == .waveGradient || self == .rainbow
    }

    public var isAnimated: Bool {
        switch self {
        case .deviceDefault, .diagonalFlow, .breathing, .gradient,
             .waveGradient, .rainbow, .pulse:
            true
        default:
            false
        }
    }

    public var minimumColorCount: Int {
        switch self {
        case .diagonalFlow, .waveGradient: 2
        case .solid, .custom, .breathing, .pulse: 1
        default: 0
        }
    }

    public var allowsMultipleColors: Bool {
        self == .diagonalFlow || self == .waveGradient
    }

    public var maximumColorCount: Int {
        allowsMultipleColors ? 2 : minimumColorCount
    }

    public var defaultPeriod: UInt8 {
        switch self {
        case .breathing: 3
        case .gradient: 5
        case .diagonalFlow, .waveGradient, .rainbow, .pulse: 2
        default: 1
        }
    }

    public var periodRange: ClosedRange<Double> {
        switch self {
        case .gradient: 1...10
        case .diagonalFlow, .breathing, .waveGradient, .rainbow, .pulse: 1...5
        default: 1...1
        }
    }
}

public enum FlydigiDockLightingDirection: UInt8, Codable, CaseIterable,
    Sendable, Equatable
{
    case none = 0
    case right = 1
    case left = 2
    case down = 3
    case up = 4
    case downRight = 5
    case upRight = 6
    case downLeft = 7
    case upLeft = 8

    public var title: String {
        switch self {
        case .none: "None"
        case .right: "Right"
        case .left: "Left"
        case .down: "Down"
        case .up: "Up"
        case .downRight: "Down-right"
        case .upRight: "Up-right"
        case .downLeft: "Down-left"
        case .upLeft: "Up-left"
        }
    }
}

public struct FlydigiDockLightingConfiguration: Sendable, Equatable {
    public var mode: FlydigiDockLightingMode
    public var period: UInt8
    public var brightness: UInt8
    public var colors: [Vader5RGBColor]
    public var direction: FlydigiDockLightingDirection
    public var pixels: [Vader5RGBColor]

    /// `pixels` contains zero or more flattened 162-pixel frames in display order.
    public init(
        mode: FlydigiDockLightingMode = .solid,
        period: UInt8 = 50,
        brightness: UInt8 = 100,
        colors: [Vader5RGBColor] = [.init(red: 0, green: 96, blue: 255)],
        direction: FlydigiDockLightingDirection = .right,
        pixels: [Vader5RGBColor] = []
    ) {
        self.mode = mode
        self.period = max(1, min(period, 100))
        self.brightness = min(brightness, 100)
        self.colors = colors
        self.direction = direction
        self.pixels = pixels
    }
}

public enum FlydigiDockDeviceSetting: UInt8, CaseIterable, Sendable {
    case sleepWhenCharging = 0x11
    case ledSync = 0x12
    case closeWithSystem = 0x13
    case showAnimationWhenCharging = 0x19
}

public struct FlydigiDockDeviceSettings: Sendable, Equatable {
    public var sleepWhenCharging: Bool
    public var ledSync: Bool
    public var closeWithSystem: Bool
    public var showAnimationWhenCharging: Bool

    public init(
        sleepWhenCharging: Bool = false,
        ledSync: Bool = false,
        closeWithSystem: Bool = false,
        showAnimationWhenCharging: Bool = false
    ) {
        self.sleepWhenCharging = sleepWhenCharging
        self.ledSync = ledSync
        self.closeWithSystem = closeWithSystem
        self.showAnimationWhenCharging = showAnimationWhenCharging
    }
}

public struct FlydigiDockSnapshot: Sendable, Equatable {
    public var deviceType: UInt8?
    public var firmwareVersion: String?
    public var settings: FlydigiDockDeviceSettings?
    public var lighting: FlydigiDockLightingConfiguration?

    public init(
        deviceType: UInt8? = nil,
        firmwareVersion: String? = nil,
        settings: FlydigiDockDeviceSettings? = nil,
        lighting: FlydigiDockLightingConfiguration? = nil
    ) {
        self.deviceType = deviceType
        self.firmwareVersion = firmwareVersion
        self.settings = settings
        self.lighting = lighting
    }
}

public enum FlydigiDockProtocol {
    public static let vendorID = 0x37d7
    public static let productID = 0x6001
    public static let usagePage = 0xffa0
    public static let usage = 1
    public static let pixelCount = 162
    public static let columns = 18
    public static let rows = 9
    public static let reportSize = 64

    private static let chunkSize = 50
    private static let maximumColorCount = 9

    public static func reports(
        pixels: [Vader5RGBColor],
        brightness: UInt8 = 100
    ) throws -> [[UInt8]] {
        guard pixels.count == pixelCount else {
            throw FlydigiDockProtocolError.invalidPixelCount(
                expected: pixelCount, actual: pixels.count)
        }

        return try reports(configuration: .init(
            mode: .custom,
            period: 1,
            brightness: brightness,
            colors: [],
            direction: .none,
            pixels: pixels))
    }

    public static func reports(
        configuration: FlydigiDockLightingConfiguration
    ) throws -> [[UInt8]] {
        guard configuration.colors.count <= maximumColorCount else {
            throw FlydigiDockProtocolError.invalidColorCount(
                maximum: maximumColorCount, actual: configuration.colors.count)
        }
        if configuration.mode == .custom && configuration.pixels.isEmpty {
            throw FlydigiDockProtocolError.invalidPixelCount(
                expected: pixelCount, actual: configuration.pixels.count)
        }
        if configuration.mode == .deviceDefault &&
            configuration.pixels.isEmpty {
            throw FlydigiDockProtocolError.missingFactoryDefaultFrames
        }
        if !configuration.pixels.isEmpty &&
            !configuration.pixels.count.isMultiple(of: pixelCount) {
            throw FlydigiDockProtocolError.invalidAnimationPixelCount(
                frameSize: pixelCount, actual: configuration.pixels.count)
        }
        let frameCount = configuration.pixels.count / pixelCount
        guard frameCount <= Int(UInt8.max) else {
            throw FlydigiDockProtocolError.tooManyFrames(
                maximum: Int(UInt8.max), actual: frameCount)
        }

        let payload = configurationPayload(configuration)
        let packetCount = (payload.count + chunkSize - 1) / chunkSize
        var result = [initializationReport(packetCount: packetCount)]
        result.reserveCapacity(packetCount + 1)
        for index in 0..<packetCount {
            let start = index * chunkSize
            let end = min(start + chunkSize, payload.count)
            result.append(dataReport(
                index: index,
                packetCount: packetCount,
                data: payload[start..<end]))
        }
        return result
    }

    public static func solidColorReports(
        color: Vader5RGBColor,
        brightness: UInt8 = 100
    ) -> [[UInt8]] {
        // The pixel count is fixed here, so construction cannot fail.
        try! reports(
            pixels: Array(repeating: color, count: pixelCount),
            brightness: brightness)
    }

    public static func heartbeatReport() -> [UInt8] {
        simpleReport(command: 0x01, payload: [])
    }

    public static func readLightingConfigurationReport() -> [UInt8] {
        simpleReport(command: 0x14, payload: [])
    }

    public static func deviceSettingReport(
        _ setting: FlydigiDockDeviceSetting,
        enabled: Bool
    ) -> [UInt8] {
        simpleReport(command: setting.rawValue, payload: [enabled ? 1 : 0])
    }

    public static func parseSnapshot(_ reports: [[UInt8]]) -> FlydigiDockSnapshot {
        var deviceType: UInt8?
        var firmwareVersion: String?
        var settings: FlydigiDockDeviceSettings?
        var lighting: FlydigiDockLightingConfiguration?
        for report in reports where report.count >= 6 &&
            report[0] == 0x5a && report[1] == 0xa5 {
            switch report[2] {
            case 0x01 where report.count > 21:
                deviceType = report[6]
                let version = [
                    report[16] >> 4,
                    report[16] & 0x0f,
                    report[17] >> 4,
                    report[17] & 0x0f,
                ]
                if version.contains(where: { $0 != 0 }) {
                    firmwareVersion = version.map(String.init).joined(separator: ".")
                }
                settings = .init(
                    sleepWhenCharging: report[18] == 1,
                    ledSync: report[19] == 1,
                    closeWithSystem: report[20] == 1,
                    showAnimationWhenCharging: report[21] == 1)
            case 0x14 where report.count > 8:
                lighting = parseLightingConfiguration(report)
            default:
                break
            }
        }
        return .init(
            deviceType: deviceType,
            firmwareVersion: firmwareVersion,
            settings: settings,
            lighting: lighting)
    }

    private static func configurationPayload(
        _ configuration: FlydigiDockLightingConfiguration
    ) -> [UInt8] {
        let frameCount = configuration.pixels.count / pixelCount
        var payload: [UInt8] = [
            UInt8(frameCount),
            configuration.period,
            configuration.brightness,
            configuration.mode.rawValue,
            configuration.direction.rawValue,
            UInt8(configuration.colors.count),
        ]
        payload.reserveCapacity(
            6 + configuration.colors.count * 3 +
            configuration.pixels.count * 3)
        for color in configuration.colors {
            payload.append(color.red)
            payload.append(color.green)
            payload.append(color.blue)
        }
        for pixel in configuration.pixels {
            payload.append(pixel.red)
            payload.append(pixel.green)
            payload.append(pixel.blue)
        }
        return payload
    }

    private static func initializationReport(packetCount: Int) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportSize)
        report.replaceSubrange(0..<9, with: [
            0x5a, 0xa5, 0x61, 0x07, 0x0a, 0x00, 0x00, 0x00,
            UInt8(packetCount & 0xff),
        ])
        report[7] = UInt8((packetCount >> 8) & 0xff)
        report[9] = checksum(report, end: 9)
        return report
    }

    private static func dataReport(
        index: Int,
        packetCount: Int,
        data: ArraySlice<UInt8>
    ) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = 0x5a
        report[1] = 0xa5
        report[2] = 0x62
        report[3] = UInt8(data.count + 7)
        report[4] = UInt8((packetCount >> 8) & 0xff)
        report[5] = UInt8(packetCount & 0xff)
        report[6] = UInt8((index >> 8) & 0xff)
        report[7] = UInt8(index & 0xff)
        report[8] = UInt8(data.count)
        for (offset, byte) in data.enumerated() {
            report[9 + offset] = byte
        }

        let checksumOffset = 9 + data.count
        report[checksumOffset] = checksum(report, end: checksumOffset)
        return report
    }

    private static func simpleReport(command: UInt8, payload: [UInt8]) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: reportSize)
        report[0] = 0x5a
        report[1] = 0xa5
        report[2] = command
        report[3] = UInt8(payload.count + 2)
        for (index, byte) in payload.enumerated() {
            report[4 + index] = byte
        }
        let checksumOffset = 4 + payload.count
        report[checksumOffset] = checksum(report, end: checksumOffset)
        return report
    }

    private static func checksum(_ report: [UInt8], end: Int) -> UInt8 {
        report[2..<end].reduce(0) { $0 &+ $1 }
    }

    private static func parseLightingConfiguration(
        _ report: [UInt8]
    ) -> FlydigiDockLightingConfiguration? {
        guard let mode = FlydigiDockLightingMode(rawValue: report[4]),
              let direction = FlydigiDockLightingDirection(rawValue: report[7])
        else { return nil }
        let colorCount = min(Int(report[8]), maximumColorCount)
        guard 9 + colorCount * 3 <= report.count else { return nil }
        var colors: [Vader5RGBColor] = []
        colors.reserveCapacity(colorCount)
        for index in 0..<colorCount {
            let offset = 9 + index * 3
            colors.append(.init(
                red: report[offset],
                green: report[offset + 1],
                blue: report[offset + 2]))
        }
        return .init(
            mode: mode,
            period: report[6],
            brightness: report[5],
            colors: colors,
            direction: direction)
    }
}
