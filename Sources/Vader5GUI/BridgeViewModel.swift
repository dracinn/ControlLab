import Foundation
import Vader5Core

@MainActor
final class BridgeViewModel: ObservableObject {
    @Published var mode: Vader5BridgeMode = .monitor
    @Published var status: Vader5BridgeStatus = .stopped
    @Published var state: Vader5State = .neutral
    @Published var errorMessage: String?

    private let bridge = Vader5Bridge()

    init() {
        bridge.onStatus = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        bridge.onState = { [weak self] state in
            Task { @MainActor in self?.state = state }
        }
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var statusTitle: String {
        switch status {
        case .stopped: "Disconnected"
        case .connecting: "Connecting…"
        case .running(.monitor): "Monitoring"
        case .running(.virtualGamepad): "Gamepad active"
        case .failed: "Connection failed"
        }
    }

    func toggle() {
        errorMessage = nil
        if isRunning {
            bridge.stop()
        } else {
            do { try bridge.start(mode: mode) }
            catch { errorMessage = String(describing: error) }
        }
    }

    func stop() { bridge.stop() }
}
