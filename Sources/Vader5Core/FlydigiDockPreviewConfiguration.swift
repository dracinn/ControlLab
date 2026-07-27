import Foundation

public struct FlydigiDockPreviewConfiguration: Codable, Equatable, Sendable {
    public var mode: FlydigiDockLightingMode
    public var colors: [Vader5RGBColor]
    public var brightness: Double
    public var period: Double
    public var direction: FlydigiDockLightingDirection
    public var deviceType: UInt8

    public init(
        mode: FlydigiDockLightingMode,
        colors: [Vader5RGBColor],
        brightness: Double,
        period: Double,
        direction: FlydigiDockLightingDirection,
        deviceType: UInt8
    ) {
        self.mode = mode
        self.colors = colors
        self.brightness = brightness
        self.period = period
        self.direction = direction
        self.deviceType = deviceType
    }

    public static let fallback = Self(
        mode: .deviceDefault,
        colors: [],
        brightness: 100,
        period: 2,
        direction: .none,
        deviceType: 0)

    public static var fileURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first!
            .appendingPathComponent("ControlLab", isDirectory: true)
        return directory.appendingPathComponent("rgb-preview.json")
    }

    public func write() throws {
        let url = Self.fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    public static func read() throws -> Self {
        try JSONDecoder().decode(
            Self.self, from: Data(contentsOf: fileURL))
    }
}
