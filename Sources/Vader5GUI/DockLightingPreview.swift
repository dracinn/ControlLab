import AppKit
import SwiftUI
import Vader5Core

struct DockLightingPreview: View {
    let mode: FlydigiDockLightingMode
    let colors: [Color]
    let brightness: Double
    let period: Double
    let direction: FlydigiDockLightingDirection

    private static let animationFrameCount = 12

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1 / 12,
            paused: !mode.isAnimated
        )) { context in
            GeometryReader { proxy in
                ZStack {
                    if let image = officialDockImage {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                    }

                    DockDisplayFace()
                        .fill(Color.black.opacity(0.94))

                    let pixels = previewPixels(at: context.date)
                    ForEach(DockPixelGeometry.positions.indices, id: \.self) { index in
                        let point = DockPixelGeometry.positions[index]
                        let color = index < pixels.count ? pixels[index] : .black
                        Circle()
                            .fill(color.opacity(max(0.06, brightness / 100)))
                            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.45))
                            .shadow(
                                color: color.opacity(0.72 * brightness / 100),
                                radius: 4)
                            .frame(
                                width: DockPixelGeometry.dotDiameter * proxy.size.width,
                                height: DockPixelGeometry.dotDiameter * proxy.size.width)
                            .position(
                                x: point.x * proxy.size.width,
                                y: point.y * proxy.size.height)
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(red: 0.055, green: 0.058, blue: 0.063))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Animated Charging Station 2 Pro lighting preview")
    }

    private func previewPixels(at date: Date) -> [Color] {
        if mode == .off {
            return Array(repeating: .black, count: FlydigiDockProtocol.pixelCount)
        }

        let previewMode: FlydigiDockLightingMode =
            mode == .deviceDefault ? .rainbow : mode
        let generated = FlydigiDockFrameGenerator.pixels(
            mode: previewMode,
            colors: colors.map(rgbColor),
            direction: direction,
            animationFrameCount: Self.animationFrameCount)
        guard !generated.isEmpty else {
            return Array(repeating: .black, count: FlydigiDockProtocol.pixelCount)
        }

        let frameCount = max(1, generated.count / FlydigiDockProtocol.pixelCount)
        let frameIndex: Int
        if previewMode.isAnimated && frameCount > 1 {
            let duration = max(0.6, period / 14)
            let elapsed = date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration)
            frameIndex = min(
                frameCount - 1,
                Int((elapsed / duration) * Double(frameCount)))
        } else {
            frameIndex = 0
        }
        let start = frameIndex * FlydigiDockProtocol.pixelCount
        return generated[start..<(start + FlydigiDockProtocol.pixelCount)].map {
            Color(
                red: Double($0.red) / 255,
                green: Double($0.green) / 255,
                blue: Double($0.blue) / 255)
        }
    }

    private func rgbColor(_ color: Color) -> Vader5RGBColor {
        let native = NSColor(color)
        let converted = native.usingColorSpace(.deviceRGB) ?? native
        return .init(
            red: UInt8(clamping: Int((converted.redComponent * 255).rounded())),
            green: UInt8(clamping: Int((converted.greenComponent * 255).rounded())),
            blue: UInt8(clamping: Int((converted.blueComponent * 255).rounded())))
    }

    private var officialDockImage: NSImage? {
        if let packaged = Bundle.main.url(
            forResource: "FlydigiDock2Pro-Front", withExtension: "png") {
            return NSImage(contentsOf: packaged)
        }
        let sourceResource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FlydigiDock2Pro-Front.png")
        return NSImage(contentsOf: sourceResource)
    }
}

private enum DockPixelGeometry {
    static let dotDiameter = 0.014

    static let positions: [CGPoint] = {
        let outerVertices = [
            CGPoint(x: 0.305, y: 0.490),
            CGPoint(x: 0.675, y: 0.490),
            CGPoint(x: 0.463, y: 0.840),
        ]
        let center = CGPoint(
            x: outerVertices.map(\.x).reduce(0, +) / 3,
            y: outerVertices.map(\.y).reduce(0, +) / 3)
        var result: [CGPoint] = []
        result.reserveCapacity(FlydigiDockProtocol.pixelCount)

        // Three nested 54-pixel rings reproduce the dock's three-dot corner
        // clusters and its fourteen-dot straight runs, while retaining every
        // one of the protocol's 162 independently addressable RGB pixels.
        for ring in 0..<3 {
            let inset = 0.018 + CGFloat(ring) * 0.045
            let vertices = outerVertices.map {
                interpolate($0, center, amount: inset)
            }
            for side in 0..<3 {
                let start = vertices[side]
                let end = vertices[(side + 1) % 3]
                for position in 0..<18 {
                    result.append(interpolate(
                        start,
                        end,
                        amount: CGFloat(position) / 18))
                }
            }
        }
        assert(result.count == FlydigiDockProtocol.pixelCount)
        return result
    }()

    private static func interpolate(
        _ start: CGPoint,
        _ end: CGPoint,
        amount: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount)
    }
}

private struct DockDisplayFace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.220, y: rect.height * 0.428))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.735, y: rect.height * 0.430),
            control: CGPoint(x: rect.width * 0.490, y: rect.height * 0.410))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.460, y: rect.height * 0.915),
            control: CGPoint(x: rect.width * 0.650, y: rect.height * 0.705))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.220, y: rect.height * 0.428),
            control: CGPoint(x: rect.width * 0.270, y: rect.height * 0.720))
        path.closeSubpath()
        return path
    }
}
