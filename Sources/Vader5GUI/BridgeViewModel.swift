import Foundation
import AppKit
import SwiftUI
import Vader5Core

enum FlydigiDockLightingStatus: Equatable {
    case checking
    case ready
    case unavailable(String)
}

@MainActor
final class BridgeViewModel: ObservableObject {
    @Published var mode: Vader5BridgeMode = .monitor
    @Published var transport: Vader5Transport = .usbReceiver {
        didSet {
            if transport == .bluetooth { mode = .monitor }
        }
    }
    @Published var status: Vader5BridgeStatus = .stopped
    @Published var state: Vader5State = .neutral
    @Published var errorMessage: String?
    @Published var lightingStatus: Vader5LightingStatus = .checking
    @Published var lightingMode: Vader5LightingMode = .steady
    @Published var lightingColors: [Color] = [Color(red: 0, green: 116 / 255, blue: 1)]
    @Published var lightingBrightness: Double = 100
    @Published var lightingPeriod: Double = 50
    @Published var dockLightingStatus: FlydigiDockLightingStatus = .checking
    @Published var dockLightingMode: FlydigiDockLightingMode = .solid
    @Published var dockLightingColors: [Color] = [
        Color(red: 0, green: 48 / 255, blue: 160 / 255),
    ]
    @Published var dockLightingBrightness: Double = 100
    @Published var dockLightingPeriod: Double = 50
    @Published var dockLightingDirection: FlydigiDockLightingDirection = .right
    @Published var dockDeviceSettings = FlydigiDockDeviceSettings()
    @Published var dockDeviceType: UInt8?
    @Published var dockFactoryLighting: FlydigiDockLightingConfiguration?
    @Published var dockSettingsLoaded = false
    @Published var isApplyingDockLighting = false
    @Published var isApplyingDockSettings = false
    @Published var isApplyingLighting = false

    private let bridge = Vader5Bridge()
    private let dock = FlydigiDock()
    private struct LightingDraft {
        var colors: [Color]
        var brightness: Double
        var period: Double
    }
    private var lightingDrafts: [Vader5LightingMode: LightingDraft] = [:]

    init() {
        loadDockFactoryLighting(deviceType: 0)
        bridge.onStatus = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        bridge.onState = { [weak self] state in
            Task { @MainActor in self?.state = state }
        }
        bridge.onLightingStatus = { [weak self] status in
            Task { @MainActor in self?.lightingStatus = status }
        }
        bridge.onLightingConfiguration = { [weak self] configuration in
            Task { @MainActor in self?.loadLightingConfiguration(configuration) }
        }
        refreshDockStatus()
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var statusTitle: String {
        switch status {
        case .stopped: "Disconnected"
        case .connecting: "Connecting…"
        case .running(.monitor): transport == .bluetooth ? "Bluetooth connected" : "Monitoring"
        case .running(.virtualGamepad): "Gamepad active"
        case .failed: "Connection failed"
        }
    }

    func toggle() {
        errorMessage = nil
        if isRunning {
            bridge.stop()
        } else {
            do { try bridge.start(mode: mode, transport: transport) }
            catch { errorMessage = String(describing: error) }
        }
    }

    func stop() { bridge.stop() }

    var canSetLighting: Bool {
        if case .ready = lightingStatus {
            return isRunning && !isApplyingLighting
        }
        return false
    }

    func applyLighting() {
        errorMessage = nil
        saveLightingDraft()
        let configuration = Vader5LightingConfiguration(
            mode: lightingMode,
            colors: lightingColors.map(rgbColor),
            brightness: UInt8(clamping: Int(lightingBrightness.rounded())),
            period: UInt8(clamping: Int(lightingPeriod.rounded())))
        isApplyingLighting = true
        Task {
            defer { isApplyingLighting = false }
            do {
                try await bridge.setLightingAsync(configuration)
            } catch {
                errorMessage = String(describing: error)
            }
        }
    }

    var canSetDockLighting: Bool {
        dockLightingStatus == .ready && !isApplyingDockLighting &&
            (dockLightingMode != .deviceDefault || dockFactoryLighting != nil)
    }

    var canSetDockDeviceSettings: Bool {
        dockLightingStatus == .ready && dockSettingsLoaded &&
            !isApplyingDockSettings
    }

    var availableDockLightingModes: [FlydigiDockLightingMode] {
        [
            .deviceDefault, .solid, .diagonalFlow, .breathing, .gradient,
            .waveGradient, .rainbow, .pulse, .custom, .off,
        ]
    }

    func refreshDockStatus() {
        dockLightingStatus = .checking
        do {
            dockLightingStatus = try dock.isConnected()
                ? .ready
                : .unavailable("Connect the Charging Station 2 Pro over USB.")
        } catch {
            dockLightingStatus = .unavailable(String(describing: error))
        }
    }

    func refreshDockConfiguration() {
        dockLightingStatus = .checking
        dockSettingsLoaded = false
        do {
            let snapshot = try dock.readSnapshot()
            if let deviceType = snapshot.deviceType {
                dockDeviceType = deviceType
                loadDockFactoryLighting(deviceType: deviceType)
            }
            if let settings = snapshot.settings {
                dockDeviceSettings = settings
                dockSettingsLoaded = true
            }
            if let configuration = snapshot.lighting {
                loadDockLightingConfiguration(configuration)
            }
            dockLightingStatus = .ready
        } catch {
            dockLightingStatus = .unavailable(String(describing: error))
        }
    }

    func applyDockLighting() {
        errorMessage = nil
        let configuration: FlydigiDockLightingConfiguration
        if dockLightingMode == .deviceDefault {
            guard let factory = dockFactoryLighting else {
                let message =
                    "No validated factory animation is available for this dock variant."
                dockLightingStatus = .unavailable(message)
                errorMessage = message
                return
            }
            configuration = factory
        } else {
            let nativeColors = dockLightingMode.usesColors
                ? dockLightingColors.map(rgbColor)
                : []
            let framePixels = FlydigiDockFrameGenerator.pixels(
                mode: dockLightingMode,
                colors: nativeColors,
                direction: dockLightingDirection)
            configuration = FlydigiDockLightingConfiguration(
                mode: dockLightingMode,
                period: UInt8(clamping: Int(dockLightingPeriod.rounded())),
                brightness: UInt8(clamping: Int(dockLightingBrightness.rounded())),
                colors: dockLightingMode == .custom ? [] : nativeColors,
                direction: dockLightingDirection,
                pixels: framePixels)
        }

        isApplyingDockLighting = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try FlydigiDock().setLighting(configuration)
                }
            }.value
            isApplyingDockLighting = false
            switch result {
            case .success:
                dockLightingStatus = .ready
            case .failure(let error):
                dockLightingStatus = .unavailable(String(describing: error))
                errorMessage = String(describing: error)
            }
        }
    }

    func turnOffDockLighting() {
        dockLightingMode = .off
        applyDockLighting()
    }

    func applyDockDeviceSettings() {
        errorMessage = nil
        isApplyingDockSettings = true
        defer { isApplyingDockSettings = false }
        do {
            try dock.setDeviceSettings(dockDeviceSettings)
            dockLightingStatus = .ready
        } catch {
            dockLightingStatus = .unavailable(String(describing: error))
            errorMessage = String(describing: error)
        }
    }

    func selectDockLightingMode(_ mode: FlydigiDockLightingMode) {
        dockLightingMode = mode
        if mode == .deviceDefault, let factory = dockFactoryLighting {
            loadDockLightingConfiguration(factory)
            return
        }
        dockLightingPeriod = Double(mode.defaultPeriod)
        dockLightingDirection = mode.usesDirection ? .right : .none
        if mode == .diagonalFlow || mode == .waveGradient {
            dockLightingColors = [
                Color(red: 195 / 255, green: 32 / 255, blue: 230 / 255),
                Color(red: 22 / 255, green: 230 / 255, blue: 249 / 255),
            ]
        }
        normalizeDockLightingColors()
    }

    func addDockLightingColor() {
        guard dockLightingMode.allowsMultipleColors,
              dockLightingColors.count < dockLightingMode.maximumColorCount
        else { return }
        dockLightingColors.append(
            Color(red: 195 / 255, green: 32 / 255, blue: 230 / 255))
    }

    func removeDockLightingColor() {
        guard dockLightingColors.count > dockLightingMode.minimumColorCount
        else { return }
        dockLightingColors.removeLast()
    }

    private func normalizeDockLightingColors() {
        guard dockLightingMode.usesColors else { return }
        if dockLightingColors.isEmpty {
            dockLightingColors = [Color(red: 0, green: 96 / 255, blue: 1)]
        }
        while dockLightingColors.count < dockLightingMode.minimumColorCount {
            dockLightingColors.append(
                Color(red: 195 / 255, green: 32 / 255, blue: 230 / 255))
        }
        if dockLightingColors.count > dockLightingMode.maximumColorCount {
            dockLightingColors = Array(
                dockLightingColors.prefix(dockLightingMode.maximumColorCount))
        }
    }

    private func loadDockLightingConfiguration(
        _ configuration: FlydigiDockLightingConfiguration
    ) {
        dockLightingMode = configuration.mode
        dockLightingBrightness = Double(configuration.brightness)
        dockLightingPeriod = Double(configuration.period)
        dockLightingDirection = configuration.direction
        if !configuration.colors.isEmpty {
            dockLightingColors = configuration.colors.map {
                Color(
                    red: Double($0.red) / 255,
                    green: Double($0.green) / 255,
                    blue: Double($0.blue) / 255)
            }
        }
        normalizeDockLightingColors()
    }

    private func loadDockFactoryLighting(deviceType: UInt8) {
        do {
            let configuration = try DockFactoryLightingStore.configuration(
                deviceType: deviceType)
            guard configuration.mode == .deviceDefault else {
                throw FlydigiDockFactoryLightingError.unsupportedMode(
                    Int(configuration.mode.rawValue))
            }
            dockFactoryLighting = configuration
            if dockLightingMode == .deviceDefault {
                loadDockLightingConfiguration(configuration)
            }
        } catch {
            dockFactoryLighting = nil
            if dockLightingMode == .deviceDefault {
                errorMessage = String(describing: error)
            }
        }
    }

    var availableLightingModes: [Vader5LightingMode] {
        if case .ready(.sdl) = lightingStatus { return [.steady] }
        return [.deviceDefault, .flow, .breathing, .feedback, .gradient, .steady, .off]
    }

    func addLightingColor() {
        guard lightingMode.allowsMultipleColors, lightingColors.count < 5 else { return }
        lightingColors.append(Color(red: 0, green: 116 / 255, blue: 1))
    }

    func selectLightingMode(_ mode: Vader5LightingMode) {
        guard mode != lightingMode else { return }
        saveLightingDraft()
        lightingMode = mode
        if let draft = lightingDrafts[mode] {
            lightingColors = draft.colors
            lightingBrightness = draft.brightness
            lightingPeriod = draft.period
        } else if mode.usesColors {
            let blue = Color(red: 0, green: 116 / 255, blue: 1)
            lightingColors = mode == .gradient
                ? [blue, Color(red: 195 / 255, green: 32 / 255, blue: 230 / 255)]
                : [blue]
        }
        normalizeLightingColors()
    }

    func removeLightingColor() {
        guard lightingColors.count > lightingMode.minimumColorCount else { return }
        lightingColors.removeLast()
    }

    private func normalizeLightingColors() {
        guard lightingMode.usesColors else { return }
        if lightingColors.isEmpty { lightingColors = [.blue] }
        while lightingColors.count < lightingMode.minimumColorCount {
            lightingColors.append(lightingColors.last!)
        }
        if !lightingMode.allowsMultipleColors, lightingColors.count > 1 {
            lightingColors = [lightingColors[0]]
        }
    }

    private func loadLightingConfiguration(_ configuration: Vader5LightingConfiguration) {
        lightingMode = configuration.mode
        lightingColors = configuration.colors.map {
            Color(red: Double($0.red) / 255, green: Double($0.green) / 255,
                  blue: Double($0.blue) / 255)
        }
        lightingBrightness = Double(configuration.brightness)
        lightingPeriod = Double(configuration.period)
        normalizeLightingColors()
        saveLightingDraft()
    }

    private func saveLightingDraft() {
        lightingDrafts[lightingMode] = LightingDraft(
            colors: lightingColors,
            brightness: lightingBrightness,
            period: lightingPeriod)
    }

    private func rgbColor(_ color: Color) -> Vader5RGBColor {
        let nativeColor = NSColor(color)
        let converted = nativeColor.usingColorSpace(.deviceRGB) ?? nativeColor
        return Vader5RGBColor(
            red: UInt8(clamping: Int((converted.redComponent * 255).rounded())),
            green: UInt8(clamping: Int((converted.greenComponent * 255).rounded())),
            blue: UInt8(clamping: Int((converted.blueComponent * 255).rounded())))
    }
}
