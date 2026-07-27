import SwiftUI
import Vader5Core

@main
struct ControlLabRGBPreviewApp: App {
    @StateObject private var model = RGBPreviewModel()

    var body: some Scene {
        WindowGroup("ControlLab RGB Preview") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CHARGING STATION RGB")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                        Text(model.configuration.mode.title)
                            .font(.title2.bold())
                    }
                    Spacer()
                    Label("Separate process", systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DockLightingPreview(
                    mode: model.configuration.mode,
                    colors: model.configuration.colors.map {
                        Color(
                            red: Double($0.red) / 255,
                            green: Double($0.green) / 255,
                            blue: Double($0.blue) / 255)
                    },
                    brightness: model.configuration.brightness,
                    period: model.configuration.period,
                    direction: model.configuration.direction,
                    factoryDefault: model.factoryDefault)
            }
            .padding(18)
            .frame(minWidth: 520, minHeight: 650)
            .background(Color(red: 10 / 255, green: 12 / 255, blue: 16 / 255))
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class RGBPreviewModel: ObservableObject {
    @Published var configuration =
        (try? FlydigiDockPreviewConfiguration.read()) ?? .fallback
    @Published var factoryDefault: FlydigiDockLightingConfiguration?

    private var timer: Timer?

    init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    private func reload() {
        guard let latest = try? FlydigiDockPreviewConfiguration.read()
        else { return }
        if latest != configuration {
            configuration = latest
        }
        if latest.mode == .deviceDefault {
            factoryDefault = try? Self.loadFactoryDefault(
                deviceType: latest.deviceType)
        }
    }

    private static func loadFactoryDefault(
        deviceType: UInt8
    ) throws -> FlydigiDockLightingConfiguration {
        let name = "default_mapping_\(deviceType)"
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "dat",
            subdirectory: "FlydigiDockDefaults")
        else {
            throw FlydigiDockFactoryLightingError.missingLightingConfiguration
        }
        return try FlydigiDockFactoryLighting.decode(Data(contentsOf: url))
    }
}
