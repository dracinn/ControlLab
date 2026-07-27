import Foundation

public enum FlydigiDockFrameGenerator {
    public static let defaultAnimationFrameCount = 12

    /// Returns flattened 18×9 RGB frames ready for a dock lighting configuration.
    public static func pixels(
        mode: FlydigiDockLightingMode,
        colors requestedColors: [Vader5RGBColor],
        direction: FlydigiDockLightingDirection,
        animationFrameCount: Int = defaultAnimationFrameCount
    ) -> [Vader5RGBColor] {
        guard mode != .off && mode != .deviceDefault else { return [] }

        let fallback = Vader5RGBColor(red: 0, green: 96, blue: 255)
        let colors = requestedColors.isEmpty ? [fallback] : requestedColors
        let frameCount = mode.isAnimated ? max(2, animationFrameCount) : 1
        var result: [Vader5RGBColor] = []
        result.reserveCapacity(frameCount * FlydigiDockProtocol.pixelCount)

        for frameIndex in 0..<frameCount {
            let phase = Double(frameIndex) / Double(frameCount)
            for pixelIndex in 0..<FlydigiDockProtocol.pixelCount {
                let progress = directionalProgress(
                    pixelIndex: pixelIndex, direction: direction)
                result.append(color(
                    mode: mode,
                    colors: colors,
                    progress: progress,
                    phase: phase))
            }
        }
        return result
    }

    private static func color(
        mode: FlydigiDockLightingMode,
        colors: [Vader5RGBColor],
        progress: Double,
        phase: Double
    ) -> Vader5RGBColor {
        switch mode {
        case .rainbow:
            return hsv(hue: wrapped(progress + phase), saturation: 0.9, value: 1)
        case .gradient:
            return paletteColor(colors, progress: wrapped(progress + phase))
        case .diagonalFlow:
            return paletteColor(
                colors, progress: wrapped(progress * 1.5 + phase))
        case .waveGradient:
            let wave = (sin((progress + phase) * .pi * 2) + 1) / 2
            return interpolate(
                colors[0], colors.count > 1 ? colors[1] : .init(red: 0, green: 0, blue: 0),
                progress: wave)
        case .breathing:
            let level = 0.12 + 0.88 * ((sin(phase * .pi * 2 - .pi / 2) + 1) / 2)
            return scale(colors[0], by: level)
        case .pulse:
            let sine = (sin(phase * .pi * 2 - .pi / 2) + 1) / 2
            return scale(colors[0], by: 0.08 + 0.92 * pow(sine, 3))
        default:
            return colors[0]
        }
    }

    private static func directionalProgress(
        pixelIndex: Int,
        direction: FlydigiDockLightingDirection
    ) -> Double {
        let x = Double(pixelIndex % FlydigiDockProtocol.columns) /
            Double(FlydigiDockProtocol.columns - 1)
        let y = Double(pixelIndex / FlydigiDockProtocol.columns) /
            Double(FlydigiDockProtocol.rows - 1)
        return switch direction {
        case .none, .right: x
        case .left: 1 - x
        case .down: y
        case .up: 1 - y
        case .downRight: (x + y) / 2
        case .upRight: (x + (1 - y)) / 2
        case .downLeft: ((1 - x) + y) / 2
        case .upLeft: ((1 - x) + (1 - y)) / 2
        }
    }

    private static func paletteColor(
        _ colors: [Vader5RGBColor],
        progress: Double
    ) -> Vader5RGBColor {
        guard colors.count > 1 else { return colors[0] }
        let scaled = wrapped(progress) * Double(colors.count)
        let startIndex = Int(floor(scaled)) % colors.count
        let endIndex = (startIndex + 1) % colors.count
        return interpolate(
            colors[startIndex],
            colors[endIndex],
            progress: scaled - floor(scaled))
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
