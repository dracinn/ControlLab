import AppKit
import SwiftUI
import Vader5Core

private struct SavedDockPoint: Codable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
}

private struct SavedDockLayout: Codable {
    var points: [SavedDockPoint]
    var anchors: [SavedDockPoint]
    var imageOpacity: Double
    var dotScale: Double
}

@MainActor
private final class DockRGBLayout: ObservableObject {
    @Published var positions: [CGPoint]
    @Published var anchors: [CGPoint]
    @Published var imageOpacity: Double
    @Published var dotScale: Double

    private static let storageKey = "ControlLab.dockRGBLayout.v3"
    private var undoStack: [SavedDockLayout] = []

    static let defaultAnchors = [
        CGPoint(x: 0.468, y: 0.490),
        CGPoint(x: 0.806, y: 0.418),
        CGPoint(x: 0.711, y: 0.798),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(SavedDockLayout.self, from: data),
           saved.points.count == FlydigiDockProtocol.pixelCount,
           saved.anchors.count == 3 {
            positions = saved.points.map(\.point)
            anchors = saved.anchors.map(\.point)
            imageOpacity = saved.imageOpacity
            dotScale = saved.dotScale
        } else {
            positions = Self.makeDefaultPositions(anchors: Self.defaultAnchors)
            anchors = Self.defaultAnchors
            imageOpacity = 0.72
            dotScale = 1
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }

    func beginEdit() {
        undoStack.append(snapshot)
        if undoStack.count > 30 {
            undoStack.removeFirst()
        }
    }

    func movePixel(_ index: Int, to point: CGPoint) {
        guard positions.indices.contains(index) else { return }
        positions[index] = clamp(point)
    }

    func moveBand(_ band: Int, translation: CGSize, from original: [CGPoint]) {
        guard original.count == positions.count else { return }
        for index in Self.indices(forBand: band) {
            positions[index] = clamp(CGPoint(
                x: original[index].x + translation.width,
                y: original[index].y + translation.height))
        }
    }

    func moveAnchor(
        _ index: Int,
        to point: CGPoint,
        from originalAnchors: [CGPoint],
        originalPositions: [CGPoint]
    ) {
        guard anchors.indices.contains(index),
              originalAnchors.count == 3,
              originalPositions.count == positions.count else { return }
        var updated = originalAnchors
        updated[index] = clamp(point)
        anchors = updated
        positions = originalPositions.map {
            clamp(Self.map(
                $0,
                from: originalAnchors,
                to: updated))
        }
    }

    func transformBand(_ band: Int, scale: CGFloat = 1, rotation: CGFloat = 0) {
        beginEdit()
        let indices = Self.indices(forBand: band)
        let center = average(indices.map { positions[$0] })
        let sine = sin(rotation)
        let cosine = cos(rotation)
        for index in indices {
            let relative = CGPoint(
                x: (positions[index].x - center.x) * scale,
                y: (positions[index].y - center.y) * scale)
            positions[index] = clamp(CGPoint(
                x: center.x + relative.x * cosine - relative.y * sine,
                y: center.y + relative.x * sine + relative.y * cosine))
        }
        save()
    }

    func bandCenter(_ band: Int) -> CGPoint {
        average(Self.indices(forBand: band).map { positions[$0] })
    }

    func restoreDefaults() {
        beginEdit()
        anchors = Self.defaultAnchors
        positions = Self.makeDefaultPositions(anchors: anchors)
        imageOpacity = 0.72
        dotScale = 1
        save()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        apply(previous)
        save()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func copyJSON() {
        guard let data = try? JSONEncoder().encode(snapshot),
              let string = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    static func indices(forBand band: Int) -> [Int] {
        guard (0..<3).contains(band) else { return [] }
        let rowRanges = [0..<5, 5..<11, 11..<16]
        let rows = rowRanges[band]
        let start = FlydigiDockFrameGenerator.rowPixelCounts[..<rows.lowerBound]
            .reduce(0, +)
        let count = FlydigiDockFrameGenerator.rowPixelCounts[rows]
            .reduce(0, +)
        return Array(start..<(start + count))
    }

    private var snapshot: SavedDockLayout {
        SavedDockLayout(
            points: positions.map(SavedDockPoint.init),
            anchors: anchors.map(SavedDockPoint.init),
            imageOpacity: imageOpacity,
            dotScale: dotScale)
    }

    private func apply(_ saved: SavedDockLayout) {
        positions = saved.points.map(\.point)
        anchors = saved.anchors.map(\.point)
        imageOpacity = saved.imageOpacity
        dotScale = saved.dotScale
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0.015), 0.985),
            y: min(max(point.y, 0.015), 0.985))
    }

    private func average(_ points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        return CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }

    private static func makeDefaultPositions(anchors: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(FlydigiDockProtocol.pixelCount)
        let sourceAnchors = [
            CGPoint(x: 0.1333, y: 0.1429),
            CGPoint(x: 0.8667, y: 0.1429),
            CGPoint(x: 0.5000, y: 0.8214),
        ]
        let spacing = CGFloat(0.0489)
        for row in FlydigiDockFrameGenerator.rowPixelCounts.indices {
            let count = FlydigiDockFrameGenerator.rowPixelCounts[row]
            let y = CGFloat(0.1429) +
                CGFloat(row) / 15 * CGFloat(0.8214 - 0.1429)
            let startX = CGFloat(0.5) - CGFloat(count - 1) * spacing / 2
            for column in 0..<count {
                let source = CGPoint(
                    x: startX + CGFloat(column) * spacing,
                    y: y)
                result.append(map(
                    source,
                    from: sourceAnchors,
                    to: anchors))
            }
        }
        return result
    }

    private static func map(
        _ point: CGPoint,
        from source: [CGPoint],
        to destination: [CGPoint]
    ) -> CGPoint {
        let denominator =
            (source[1].y - source[2].y) * (source[0].x - source[2].x) +
            (source[2].x - source[1].x) * (source[0].y - source[2].y)
        guard abs(denominator) > 0.000_001 else { return point }
        let first =
            ((source[1].y - source[2].y) * (point.x - source[2].x) +
             (source[2].x - source[1].x) * (point.y - source[2].y)) /
            denominator
        let second =
            ((source[2].y - source[0].y) * (point.x - source[2].x) +
             (source[0].x - source[2].x) * (point.y - source[2].y)) /
            denominator
        let third = 1 - first - second
        return CGPoint(
            x: first * destination[0].x +
                second * destination[1].x +
                third * destination[2].x,
            y: first * destination[0].y +
                second * destination[1].y +
                third * destination[2].y)
    }

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

struct DockLightingPreview: View {
    let mode: FlydigiDockLightingMode
    let colors: [Color]
    let brightness: Double
    let period: Double
    let direction: FlydigiDockLightingDirection
    let factoryDefault: FlydigiDockLightingConfiguration?

    @StateObject private var layout = DockRGBLayout()
    @State private var isEditing = false
    @State private var activePixel: Int?
    @State private var dragOrigin: CGPoint?
    @State private var dragPositions: [CGPoint]?
    @State private var dragAnchors: [CGPoint]?
    @State private var selectedBand = 0
    @State private var isPreviewEnabled = true
    @State private var cachedPixels: [Color] = []
    @State private var cachedPeriod: UInt8 = 1

    private static let animationFrameCount =
        FlydigiDockFrameGenerator.defaultAnimationFrameCount

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(
                minimumInterval: 1 / 50,
                paused: !isPreviewEnabled || !mode.isAnimated
            )) { context in
                GeometryReader { proxy in
                    ZStack {
                        if let image = officialDockImage {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFit()
                                .opacity(layout.imageOpacity)
                        }

                        OfficialDockDisplayFace()
                            .fill(Color.black)

                        Color.black.opacity(isEditing ? 0.08 : 0.24)

                        if isPreviewEnabled {
                            let pixels = previewPixels(at: context.date)
                            ForEach(layout.positions.indices, id: \.self) { index in
                                pixel(
                                    index: index,
                                    color: index < pixels.count
                                        ? pixels[index] : .black,
                                    size: proxy.size)
                            }
                        }

                        if isEditing {
                            alignmentHandles(size: proxy.size)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .background(DockPreviewTheme.darkest)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isEditing ? DockPreviewTheme.accent : Color.white.opacity(0.10),
                            lineWidth: isEditing ? 1.5 : 1)
            }

            alignmentControls
        }
        .onAppear { rebuildPreviewFrames() }
        .onChange(of: mode) { _ in rebuildPreviewFrames() }
        .onChange(of: colors) { _ in rebuildPreviewFrames() }
        .onChange(of: direction) { _ in rebuildPreviewFrames() }
        .onChange(of: period) { _ in rebuildPreviewFrames() }
        .onChange(of: factoryDefault) { _ in rebuildPreviewFrames() }
        .accessibilityElement(children: isEditing ? .contain : .ignore)
        .accessibilityLabel("Animated Charging Station 2 Pro lighting preview")
    }

    private func pixel(index: Int, color: Color, size: CGSize) -> some View {
        let point = layout.positions[index]
        let diameter = CGFloat(max(
            5,
            7.5 * layout.dotScale + (isEditing ? 3 : 0)))
        return Circle()
            .fill(color.opacity(max(isEditing ? 0.34 : 0.08, brightness / 100)))
            .overlay {
                Circle().stroke(
                    isEditing && activePixel == index ? Color.white : Color.white.opacity(0.28),
                    lineWidth: isEditing ? 1 : 0.45)
            }
            .overlay {
                if isEditing {
                    Text("\(index + 1)")
                        .font(.system(size: max(4, diameter * 0.34), weight: .bold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.35)
                }
            }
            .shadow(
                color: color.opacity(0.72 * brightness / 100),
                radius: isEditing ? 2 : 4)
            .frame(width: diameter, height: diameter)
            .position(x: point.x * size.width, y: point.y * size.height)
            .gesture(pixelDrag(index: index, size: size),
                     including: isEditing ? .all : .none)
            .help(isEditing ? "Pixel \(index + 1)" : "")
    }

    private func alignmentHandles(size: CGSize) -> some View {
        ZStack {
            ForEach(layout.anchors.indices, id: \.self) { index in
                let point = layout.anchors[index]
                Circle()
                    .fill(Color.orange)
                    .overlay(Text("A\(index + 1)")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.black))
                    .overlay(Circle().stroke(.white, lineWidth: 1))
                    .frame(width: 22, height: 22)
                    .position(x: point.x * size.width, y: point.y * size.height)
                    .gesture(anchorDrag(index: index, size: size))
                    .help("Drag anchor \(index + 1) to reshape the complete layout")
            }

            ForEach(0..<3, id: \.self) { band in
                let point = layout.bandCenter(band)
                RoundedRectangle(cornerRadius: 4)
                    .fill(band == selectedBand
                          ? DockPreviewTheme.accent
                          : Color.black.opacity(0.82))
                    .overlay(Text("B\(band + 1)")
                        .font(.system(size: 7, weight: .black)))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.85), lineWidth: 1))
                    .frame(width: 25, height: 18)
                    .position(x: point.x * size.width, y: point.y * size.height)
                    .gesture(bandDrag(band: band, size: size))
                    .onTapGesture { selectedBand = band }
                    .help("Drag pixel band \(band + 1) as a group")
            }
        }
    }

    private var alignmentControls: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Button {
                    isPreviewEnabled.toggle()
                } label: {
                    Label(
                        isPreviewEnabled ? "Hide preview" : "Show preview",
                        systemImage: isPreviewEnabled ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)

                Button {
                    isEditing.toggle()
                    activePixel = nil
                } label: {
                    Label(isEditing ? "Done" : "Edit RGB alignment",
                          systemImage: isEditing ? "checkmark" : "scope")
                }
                .buttonStyle(.borderedProminent)

                if isEditing {
                    Button { layout.undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!layout.canUndo)
                    .help("Undo the last alignment change")
                    Button { layout.restoreDefaults() } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help("Restore the default alignment")
                    Button { layout.copyJSON() } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy the normalized RGB layout as JSON")
                }
            }
            .font(.caption)
            .controlSize(.small)

            if isEditing {
                HStack(spacing: 8) {
                    DockFieldLabel("IMAGE")
                    Slider(value: Binding(
                        get: { layout.imageOpacity },
                        set: {
                            layout.imageOpacity = $0
                            layout.save()
                        }), in: 0.15...1)
                    DockFieldLabel("DOT SIZE")
                    Slider(value: Binding(
                        get: { layout.dotScale },
                        set: {
                            layout.dotScale = $0
                            layout.save()
                        }), in: 0.6...2)
                }

                HStack(spacing: 7) {
                    Picker("Band", selection: $selectedBand) {
                        Text("Top").tag(0)
                        Text("Middle").tag(1)
                        Text("Lower").tag(2)
                    }
                    .labelsHidden()
                    .frame(width: 82)
                    Button { layout.transformBand(selectedBand, scale: 0.97) } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .help("Shrink selected band")
                    Button { layout.transformBand(selectedBand, scale: 1.03) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Grow selected band")
                    Button {
                        layout.transformBand(selectedBand, rotation: -.pi / 180)
                    } label: {
                        Image(systemName: "rotate.left")
                    }
                    .help("Rotate selected band left")
                    Button {
                        layout.transformBand(selectedBand, rotation: .pi / 180)
                    } label: {
                        Image(systemName: "rotate.right")
                    }
                    .help("Rotate selected band right")
                    Text("Blue B handles move row bands · Orange A handles reshape all")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }

    private func pixelDrag(index: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isEditing else { return }
                if activePixel != index {
                    layout.beginEdit()
                    activePixel = index
                    dragOrigin = layout.positions[index]
                }
                guard let origin = dragOrigin else { return }
                layout.movePixel(index, to: CGPoint(
                    x: origin.x + value.translation.width / size.width,
                    y: origin.y + value.translation.height / size.height))
            }
            .onEnded { _ in
                guard isEditing else { return }
                layout.save()
                activePixel = nil
                dragOrigin = nil
            }
    }

    private func bandDrag(band: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragPositions == nil {
                    layout.beginEdit()
                    dragPositions = layout.positions
                    selectedBand = band
                }
                guard let original = dragPositions else { return }
                layout.moveBand(
                    band,
                    translation: CGSize(
                        width: value.translation.width / size.width,
                        height: value.translation.height / size.height),
                    from: original)
            }
            .onEnded { _ in
                layout.save()
                dragPositions = nil
            }
    }

    private func anchorDrag(index: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragPositions == nil || dragAnchors == nil {
                    layout.beginEdit()
                    dragPositions = layout.positions
                    dragAnchors = layout.anchors
                }
                guard let originalPositions = dragPositions,
                      let originalAnchors = dragAnchors else { return }
                let original = originalAnchors[index]
                layout.moveAnchor(
                    index,
                    to: CGPoint(
                        x: original.x + value.translation.width / size.width,
                        y: original.y + value.translation.height / size.height),
                    from: originalAnchors,
                    originalPositions: originalPositions)
            }
            .onEnded { _ in
                layout.save()
                dragPositions = nil
                dragAnchors = nil
            }
    }

    private func previewPixels(at date: Date) -> [Color] {
        guard !cachedPixels.isEmpty else {
            return Array(repeating: .black, count: FlydigiDockProtocol.pixelCount)
        }

        let frameCount = max(
            1, cachedPixels.count / FlydigiDockProtocol.pixelCount)
        let frameIndex: Int
        if mode.isAnimated && frameCount > 1 {
            let frameInterval = FlydigiDockFrameGenerator.frameInterval(
                period: cachedPeriod)
            let duration = frameInterval * Double(frameCount)
            let elapsed = date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration)
            frameIndex = min(
                frameCount - 1,
                Int(elapsed / frameInterval))
        } else {
            frameIndex = 0
        }
        let start = frameIndex * FlydigiDockProtocol.pixelCount
        return Array(cachedPixels[
            start..<(start + FlydigiDockProtocol.pixelCount)])
    }

    private func rebuildPreviewFrames() {
        let generated: [Vader5RGBColor]
        if mode == .deviceDefault, let factoryDefault {
            generated = factoryDefault.pixels
            cachedPeriod = factoryDefault.period
        } else {
            generated = FlydigiDockFrameGenerator.pixels(
                mode: mode,
                colors: colors.map(rgbColor),
                direction: direction,
                animationFrameCount: Self.animationFrameCount)
            cachedPeriod = UInt8(clamping: Int(period.rounded()))
        }
        cachedPixels = generated.map {
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
            forResource: "FlydigiDock2Pro-Official", withExtension: "jpg") {
            return NSImage(contentsOf: packaged)
        }
        let sourceResource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FlydigiDock2Pro-Official.jpg")
        return NSImage(contentsOf: sourceResource)
    }
}

private struct DockFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

private enum DockPreviewTheme {
    static let darkest = Color(
        red: 0x18 / 255, green: 0x18 / 255, blue: 0x18 / 255)
    static let accent = Color(
        red: 0x3E / 255, green: 0x95 / 255, blue: 1)
}

private struct OfficialDockDisplayFace: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(
            x: rect.width * 0.402,
            y: rect.height * 0.465))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.width * 0.836,
                y: rect.height * 0.407),
            control: CGPoint(
                x: rect.width * 0.650,
                y: rect.height * 0.382))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.width * 0.716,
                y: rect.height * 0.858),
            control: CGPoint(
                x: rect.width * 0.820,
                y: rect.height * 0.675))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.width * 0.402,
                y: rect.height * 0.465),
            control: CGPoint(
                x: rect.width * 0.430,
                y: rect.height * 0.715))
        path.closeSubpath()
        return path
    }
}
