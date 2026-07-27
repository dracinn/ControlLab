import Foundation

public struct Vader5RGBColor: Codable, Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum Vader5LightingMode: UInt8, CaseIterable, Sendable, Equatable {
    case flow = 1
    case breathing = 2
    case gradient = 3
    case feedback = 4
    case steady = 5
    case off = 6
    case deviceDefault = 7

    public var title: String {
        switch self {
        case .deviceDefault: "Default"
        case .flow: "Flow"
        case .breathing: "Breathing"
        case .feedback: "Feedback"
        case .gradient: "Gradient"
        case .steady: "Steady"
        case .off: "Off"
        }
    }

    public var usesColors: Bool {
        self == .breathing || self == .gradient || self == .feedback || self == .steady
    }

    public var allowsMultipleColors: Bool {
        self == .breathing || self == .gradient
    }

    public var minimumColorCount: Int { self == .gradient ? 2 : 1 }
    public var isAnimated: Bool { self != .steady && self != .off }
}

public struct Vader5LightingConfiguration: Sendable, Equatable {
    public var mode: Vader5LightingMode
    public var colors: [Vader5RGBColor]
    public var brightness: UInt8
    public var period: UInt8

    public init(
        mode: Vader5LightingMode = .steady,
        colors: [Vader5RGBColor] = [.init(red: 0, green: 116, blue: 255)],
        brightness: UInt8 = 100,
        period: UInt8 = 50
    ) {
        self.mode = mode
        self.colors = colors
        self.brightness = min(brightness, 100)
        self.period = max(1, min(period, 100))
    }
}

public enum Vader5LightingBackend: String, Sendable, Equatable {
    case usb = "Vader USB lighting"
    case sdl = "SDL gamepad lighting"
}

public enum Vader5LightingStatus: Sendable, Equatable {
    case checking
    case ready(Vader5LightingBackend)
    case unavailable(String)
}
