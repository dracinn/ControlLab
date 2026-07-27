import AppKit
import SwiftUI
import Vader5Core

@MainActor
final class RGBPreviewProcess: ObservableObject {
    @Published private(set) var isRunning = false
    private var process: Process?

    func update(_ configuration: FlydigiDockPreviewConfiguration) {
        do {
            try configuration.write()
        } catch {
            NSLog("ControlLab could not update RGB preview: %@", "\(error)")
        }
    }

    func show(_ configuration: FlydigiDockPreviewConfiguration) {
        update(configuration)
        if let process, process.isRunning {
            NSRunningApplication(processIdentifier: process.processIdentifier)?
                .activate(options: [.activateAllWindows])
            return
        }

        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/ControlLabRGBPreview")
        let development = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/ControlLabRGBPreview")
        let executable = FileManager.default.isExecutableFile(
            atPath: bundled.path) ? bundled : development
        let child = Process()
        child.executableURL = executable
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.process = nil
                self?.isRunning = false
            }
        }
        do {
            try child.run()
            process = child
            isRunning = true
        } catch {
            NSLog("ControlLab could not launch RGB preview: %@", "\(error)")
        }
    }
}

struct RGBPreviewProcessControl: View {
    let mode: FlydigiDockLightingMode
    let colors: [Color]
    let brightness: Double
    let period: Double
    let direction: FlydigiDockLightingDirection
    let deviceType: UInt8

    @StateObject private var process = RGBPreviewProcess()

    private var configuration: FlydigiDockPreviewConfiguration {
        .init(
            mode: mode,
            colors: colors.map(rgbColor),
            brightness: brightness,
            period: period,
            direction: direction,
            deviceType: deviceType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(SpaceStationTheme.accent)
            Text("RGB preview runs separately")
                .font(.headline)
            Text(
                "Animation rendering is isolated from controller and dock communication. If the preview hangs, ControlLab stays responsive.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                process.show(configuration)
            } label: {
                Label(
                    process.isRunning ? "Show preview" : "Launch preview",
                    systemImage: "eye")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
        .background(SpaceStationTheme.darkest)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
        .onAppear { process.update(configuration) }
        .onChange(of: configuration) { process.update($0) }
    }

    private func rgbColor(_ color: Color) -> Vader5RGBColor {
        let native = NSColor(color)
        let converted = native.usingColorSpace(.deviceRGB) ?? native
        return .init(
            red: UInt8(clamping: Int((converted.redComponent * 255).rounded())),
            green: UInt8(clamping: Int((converted.greenComponent * 255).rounded())),
            blue: UInt8(clamping: Int((converted.blueComponent * 255).rounded())))
    }
}
