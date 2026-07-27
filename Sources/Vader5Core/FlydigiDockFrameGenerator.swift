import Foundation

public enum FlydigiDockFrameGenerator {
    public static let defaultAnimationFrameCount = 50

    /// Physical row lengths used by Space Station's Charging Station 2 Pro
    /// renderer. Their sum is the protocol's 162 RGB pixels.
    public static let rowPixelCounts = [
        14, 15, 16, 15, 14, 13, 12, 11,
        10, 9, 8, 7, 6, 5, 4, 3,
    ]

    /// Returns flattened RGB frames using the effect equations recovered from
    /// Space Station 4.2.0.9. Its production effects use 50-frame loops.
    public static func pixels(
        mode: FlydigiDockLightingMode,
        colors requestedColors: [Vader5RGBColor],
        direction: FlydigiDockLightingDirection,
        animationFrameCount: Int = defaultAnimationFrameCount
    ) -> [Vader5RGBColor] {
        guard mode != .off && mode != .deviceDefault else { return [] }

        let fallback = Vader5RGBColor(red: 0, green: 96, blue: 255)
        let colors = requestedColors.isEmpty ? [fallback] : requestedColors
        let frameCount = max(2, animationFrameCount)

        return switch mode {
        case .solid, .custom:
            Array(repeating: colors[0], count: FlydigiDockProtocol.pixelCount)
        case .breathing:
            breathing(color: colors[0])
        case .gradient:
            hueGradient(frameCount: frameCount)
        case .waveGradient:
            waveGradient(
                first: colors[0],
                second: colors.count > 1 ? colors[1] : .init(red: 0, green: 0, blue: 255),
                direction: direction,
                frameCount: frameCount)
        case .diagonalFlow:
            diagonalFlow(
                first: colors[0],
                second: colors.count > 1 ? colors[1] : .init(red: 0, green: 0, blue: 255),
                frameCount: frameCount)
        case .rainbow:
            rainbow(direction: direction, frameCount: frameCount)
        case .pulse:
            pulse(color: colors[0], frameCount: frameCount)
        case .off, .deviceDefault:
            []
        }
    }

    /// The renderer advances one uploaded frame every `20 × period` ms.
    public static func frameInterval(period: UInt8) -> TimeInterval {
        Double(max(1, period)) * 0.020
    }

    private static func breathing(color: Vader5RGBColor) -> [Vader5RGBColor] {
        var current = color
        var frames = [solidFrame(current)]
        var step = 1
        while current != .init(red: 0, green: 0, blue: 0) {
            current = .init(
                red: fadeComponent(current.red, step: step),
                green: fadeComponent(current.green, step: step),
                blue: fadeComponent(current.blue, step: step))
            frames.append(solidFrame(current))
            step += 1
        }

        // Space Station mirrors the fade without repeating the fully lit or
        // fully dark endpoint.
        var returnFrames = Array(frames.reversed())
        _ = returnFrames.popLast()
        if !returnFrames.isEmpty {
            returnFrames.removeFirst()
        }
        frames.append(contentsOf: returnFrames)
        return frames.flatMap { $0 }
    }

    private static func fadeComponent(
        _ component: UInt8,
        step: Int
    ) -> UInt8 {
        let change = (0 - Double(component)) * Double(step) /
            50
        return UInt8(clamping: Int(floor(
            min(max(Double(component) + change, 0), 255))))
    }

    private static func hueGradient(frameCount: Int) -> [Vader5RGBColor] {
        var result: [Vader5RGBColor] = []
        result.reserveCapacity(frameCount * FlydigiDockProtocol.pixelCount)
        for frame in 0..<frameCount {
            let color = hsv(
                hue: Double(frame) / Double(frameCount),
                saturation: 1,
                value: 1)
            result.append(contentsOf: solidFrame(color))
        }
        return result
    }

    private static func waveGradient(
        first: Vader5RGBColor,
        second: Vader5RGBColor,
        direction: FlydigiDockLightingDirection,
        frameCount: Int
    ) -> [Vader5RGBColor] {
        var result: [Vader5RGBColor] = []
        result.reserveCapacity(frameCount * FlydigiDockProtocol.pixelCount)
        let rowCount = rowPixelCounts.count

        for frame in 0..<frameCount {
            let phase = Double(frame) / Double(frameCount) * .pi * 2
            var output = blackFrame()
            var offset = 0
            for row in rowPixelCounts.indices {
                let count = rowPixelCounts[row]
                for column in 0..<count {
                    let motion: Int
                    let colorProgress: Double
                    if direction == .down || direction == .up {
                        motion = direction == .up ? row : rowCount - 1 - row
                        colorProgress = Double(row) / Double(rowCount - 1)
                    } else {
                        motion = direction == .left ? column : count - 1 - column
                        colorProgress = count > 1
                            ? Double(column) / Double(count - 1)
                            : 0
                    }
                    let adjustedProgress =
                        direction == .up || direction == .left
                        ? 1 - colorProgress
                        : colorProgress
                    let intensity = (sin(phase + Double(motion) * 0.3) + 1) / 2
                    output[offset + column] = scale(
                        interpolate(first, second, progress: adjustedProgress),
                        by: intensity)
                }
                offset += count
            }
            result.append(contentsOf: output)
        }
        return result
    }

    private static func diagonalFlow(
        first: Vader5RGBColor,
        second: Vader5RGBColor,
        frameCount: Int
    ) -> [Vader5RGBColor] {
        let points = rendererPoints
        let center = rendererCenterPoint
        var result: [Vader5RGBColor] = []
        result.reserveCapacity(frameCount * FlydigiDockProtocol.pixelCount)

        for frame in 0..<frameCount {
            let phase = Double(frame) / Double(frameCount) * .pi * 2
            var output = blackFrame()
            for index in points.indices {
                let horizontal = points[index].x - center.x
                let vertical = points[index].y - center.y
                let angle = atan2(vertical, horizontal) + phase
                var progress = (angle + .pi) / (.pi * 2)
                progress.formTruncatingRemainder(dividingBy: 1)
                if progress < 0 { progress += 1 }
                let triangle = progress < 0.5
                    ? progress * 2
                    : 2 - progress * 2
                output[index] = interpolate(first, second, progress: triangle)
            }
            result.append(contentsOf: output)
        }
        return result
    }

    private static func rainbow(
        direction: FlydigiDockLightingDirection,
        frameCount: Int
    ) -> [Vader5RGBColor] {
        var result: [Vader5RGBColor] = []
        result.reserveCapacity(frameCount * FlydigiDockProtocol.pixelCount)
        let rows = rowPixelCounts.count

        for frame in 0..<frameCount {
            let phase = Double(frame) / Double(frameCount)
            var output = blackFrame()
            var offset = 0
            for row in rowPixelCounts.indices {
                let count = rowPixelCounts[row]
                for column in 0..<count {
                    let position = switch direction {
                    case .down: 1 - Double(row) / Double(rows)
                    case .up: Double(row) / Double(rows)
                    case .right: 1 - Double(column) / Double(count)
                    default: Double(column) / Double(count)
                    }
                    output[offset + column] = hsv(
                        hue: wrapped(phase + position),
                        saturation: 1,
                        value: 1)
                }
                offset += count
            }
            result.append(contentsOf: output)
        }
        return result
    }

    private static func pulse(
        color: Vader5RGBColor,
        frameCount: Int
    ) -> [Vader5RGBColor] {
        let points = rendererPoints
        let center = rendererCenterPoint
        let maximumRadius = points.map {
            hypot($0.x - center.x, $0.y - center.y)
        }.max() ?? 1
        var result: [Vader5RGBColor] = []
        result.reserveCapacity(frameCount * FlydigiDockProtocol.pixelCount)

        for frame in 0..<frameCount {
            let phase = Double(frame) / Double(frameCount) * .pi * 2
            var output = blackFrame()
            for index in points.indices {
                let radius = hypot(
                    points[index].x - center.x,
                    points[index].y - center.y) / maximumRadius * 10
                let intensity = (sin(phase - radius) + 1) / 2
                output[index] = scale(color, by: intensity)
            }
            result.append(contentsOf: output)
        }
        return result
    }

    private static var rendererPoints: [CGPoint] {
        let horizontalSpacing = 450.0 / 20.0
        let verticalSpacing = horizontalSpacing * sqrt(3) / 2
        let center = rendererCenterPoint
        var result: [CGPoint] = []
        result.reserveCapacity(FlydigiDockProtocol.pixelCount)
        for row in rowPixelCounts.indices {
            let count = rowPixelCounts[row]
            let width = Double(count - 1) * horizontalSpacing
            let start = center.x - width / 2
            for column in 0..<count {
                result.append(CGPoint(
                    x: start + Double(column) * horizontalSpacing,
                    y: center.y +
                        (Double(row) - Double(rowPixelCounts.count) / 2) *
                        verticalSpacing))
            }
        }
        return result
    }

    private static var rendererCenterPoint: CGPoint {
        // This is the first closest SVG LED to the 450×420 viewBox center,
        // matching Space Station's querySelectorAll traversal.
        CGPoint(x: 0.4756 * 450, y: 0.5048 * 420)
    }

    private static func solidFrame(_ color: Vader5RGBColor) -> [Vader5RGBColor] {
        Array(repeating: color, count: FlydigiDockProtocol.pixelCount)
    }

    private static func blackFrame() -> [Vader5RGBColor] {
        solidFrame(.init(red: 0, green: 0, blue: 0))
    }

    private static func interpolate(
        _ first: Vader5RGBColor,
        _ second: Vader5RGBColor,
        progress: Double
    ) -> Vader5RGBColor {
        let amount = min(max(progress, 0), 1)
        func component(_ start: UInt8, _ end: UInt8) -> UInt8 {
            UInt8(clamping: Int(
                (Double(start) + (Double(end) - Double(start)) * amount)
                    .rounded()))
        }
        return .init(
            red: component(first.red, second.red),
            green: component(first.green, second.green),
            blue: component(first.blue, second.blue))
    }

    private static func scale(
        _ color: Vader5RGBColor,
        by amount: Double
    ) -> Vader5RGBColor {
        .init(
            red: UInt8(clamping: Int((Double(color.red) * amount).rounded())),
            green: UInt8(clamping: Int((Double(color.green) * amount).rounded())),
            blue: UInt8(clamping: Int((Double(color.blue) * amount).rounded())))
    }

    private static func hsv(
        hue: Double,
        saturation: Double,
        value: Double
    ) -> Vader5RGBColor {
        let sector = wrapped(hue) * 6
        let index = Int(floor(sector))
        let fraction = sector - floor(sector)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * fraction)
        let t = value * (1 - saturation * (1 - fraction))
        let rgb: (Double, Double, Double) = switch index % 6 {
        case 0: (value, t, p)
        case 1: (q, value, p)
        case 2: (p, value, t)
        case 3: (p, q, value)
        case 4: (t, p, value)
        default: (value, p, q)
        }
        return .init(
            red: UInt8(clamping: Int((rgb.0 * 255).rounded())),
            green: UInt8(clamping: Int((rgb.1 * 255).rounded())),
            blue: UInt8(clamping: Int((rgb.2 * 255).rounded())))
    }

    private static func wrapped(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder < 0 ? remainder + 1 : remainder
    }
}
