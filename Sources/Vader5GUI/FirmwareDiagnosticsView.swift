import AppKit
import SwiftUI
import Vader5Core

@MainActor
final class FirmwareDiagnosticsViewModel: ObservableObject {
    @Published var packageInfo: Vader5FirmwarePackageInfo?
    @Published var events: [Vader5DiagnosticEvent] = []
    @Published var errorMessage: String?
    @Published var availableFirmware: Vader5FirmwareCatalog?
    @Published var isCheckingFirmware = false
    @Published var hasCheckedFirmware = false
    @Published var hasReadDevice = false
    @Published var lastFirmwareCheck: Date?
    @Published var installedFirmware: Vader5FirmwareVersions?
    @Published var scenario = "Success"
    private var selectedPackage: Data?

    let scenarios = ["Success", "CRC error", "Timeout", "Invalid block", "Flash full"]
    func checkFirmware() {
        guard !isCheckingFirmware else { return }
        isCheckingFirmware = true
        errorMessage = nil
        availableFirmware = nil
        hasCheckedFirmware = false
        hasReadDevice = false
        installedFirmware = nil
        Task {
            do {
                let versions = try await Task.detached(priority: .userInitiated) {
                    try Vader5FirmwareReader.read()
                }.value
                installedFirmware = versions
                hasReadDevice = true
                lastFirmwareCheck = Date()
                availableFirmware = try await Vader5FirmwareUpdateClient().check(
                    versions: versions,
                    appVersion: "4.1.0.31"
                )
                hasCheckedFirmware = true
            } catch {
                errorMessage = String(describing: error)
            }
            isCheckingFirmware = false
        }
    }

    func checkFirmwareIfNeeded() {
        guard !hasCheckedFirmware else { return }
        checkFirmware()
    }

    func inspectPackage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.message = "Select a firmware package to inspect. The file will only be read."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            selectedPackage = data
            packageInfo = Vader5FirmwarePackageInspector.inspect(data: data, fileName: url.lastPathComponent)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func runDryRun() {
        let selected: Vader5SimulationScenario = switch scenario {
        case "CRC error": .crcError(block: 0)
        case "Timeout": .timeout(block: 0)
        case "Invalid block": .invalidBlock(block: 0)
        case "Flash full": .flashFull(block: 0)
        default: .success
        }
        do {
            let sample = Data((0..<160).map { UInt8($0 & 0xff) })
            let result = try Vader5DiagnosticUpdater.run(image: selectedPackage ?? sample, scenario: selected)
            events = result.events
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
            // Re-run the transport directly so the monitor still shows the simulated fault trace.
            let transport = Vader5DryRunTransport(scenario: selected)
            _ = try? transport.exchange(Vader5HIDOTAProtocol.startReport(), block: nil)
            _ = try? transport.exchange(
                Vader5HIDOTAProtocol.dataReport(image: Data(repeating: 0xaa, count: 16), startingBlock: 0).report,
                block: 0)
            events = transport.events
        }
    }
}

struct FirmwareDiagnosticsView: View {
    @StateObject private var model = FirmwareDiagnosticsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                safetyCard
                firmwareCard
                HStack(alignment: .top, spacing: 18) {
                    packageCard
                    simulatorCard
                }
                monitorCard
            }
            .padding(22)
        }
        .task { model.checkFirmwareIfNeeded() }
    }

    private var safetyCard: some View {
        GroupBox {
            Label(
                "Firmware Diagnostics sends one read-only identity request over USB. Firmware erase, write, and update-mode commands remain unavailable.",
                systemImage: "lock.shield.fill"
            )
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: { Text("Non-destructive mode") }
    }

    private var firmwareCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 7) {
                            Text("Current firmware reported by this Vader 5 Pro")
                                .font(.headline)
                            Text("LIVE")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                        }
                        Text("The device is read over USB first, then its reported versions are checked with Flydigi.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let checked = model.lastFirmwareCheck {
                            Text("Last checked \(checked.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if model.isCheckingFirmware {
                            Text(model.hasReadDevice ? "Checking Flydigi now…" : "Reading firmware from USB…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        model.checkFirmware()
                    } label: {
                        if model.isCheckingFirmware {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(model.hasReadDevice ? "Refresh device" : "Read device")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isCheckingFirmware)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    firmwareRow("Controller", installed: model.installedFirmware?.main, available: model.availableFirmware?.main)
                    firmwareRow("RF", installed: model.installedFirmware?.rf, available: model.availableFirmware?.rf)
                    firmwareRow("SI", installed: model.installedFirmware?.si, available: model.availableFirmware?.si)
                    firmwareRow("Dongle", installed: model.installedFirmware?.dongle, available: model.availableFirmware?.dongle)
                }
            }
            .padding(10)
        } label: {
            Label("Live firmware checker", systemImage: "memorychip")
        }
    }

    @ViewBuilder
    private func firmwareRow(
        _ name: String,
        installed: String?,
        available: Vader5FirmwareRelease?
    ) -> some View {
        GridRow {
            Text(name).font(.callout.weight(.semibold)).frame(width: 82, alignment: .leading)
            Text(installed ?? (model.isCheckingFirmware && !model.hasReadDevice ? "Reading…" : "Unknown"))
                .font(.system(.callout, design: .monospaced))
            Image(systemName: statusIcon(available: available))
                .foregroundStyle(statusColor(available: available))
            Text(statusText(available: available))
                .font(.callout)
                .foregroundStyle(statusColor(available: available))
        }
    }

    private func statusText(available: Vader5FirmwareRelease?) -> String {
        if let available { return "Update available: \(available.version)" }
        if model.hasCheckedFirmware { return "Current" }
        if model.hasReadDevice { return "Read from USB" }
        return model.isCheckingFirmware ? "Querying device" : "Not read"
    }

    private func statusIcon(available: Vader5FirmwareRelease?) -> String {
        if available != nil { return "arrow.right.circle.fill" }
        if model.hasCheckedFirmware { return "checkmark.circle.fill" }
        return model.isCheckingFirmware ? "ellipsis.circle.fill" : "questionmark.circle"
    }

    private func statusColor(available: Vader5FirmwareRelease?) -> Color {
        if available != nil { return .orange }
        return model.hasCheckedFirmware ? .green : .secondary
    }

    private var packageCard: some View {
        GroupBox("Package inspector") {
            VStack(alignment: .leading, spacing: 10) {
                if let info = model.packageInfo {
                    diagnosticRow("File", info.fileName)
                    diagnosticRow("Size", "\(info.size) bytes")
                    diagnosticRow("Magic", info.magic)
                    diagnosticRow("Container", info.isKnownContainer ? "Known NearLink .fwpkg" : "Unknown")
                    diagnosticRow("SHA-256", info.sha256)
                } else {
                    Text("Read metadata and hashes without extracting or modifying the package.")
                        .foregroundStyle(.secondary)
                }
                Button("Inspect .fwpkg…") { model.inspectPackage() }
                    .buttonStyle(.bordered)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var simulatorCard: some View {
        GroupBox("OTA simulator and dry run") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Response", selection: $model.scenario) {
                    ForEach(model.scenarios, id: \.self, content: Text.init)
                }
                Text(model.packageInfo == nil
                    ? "Builds reports from sample bytes against a fake device. Inspect a package to use its bytes."
                    : "Builds reports from the selected package against a fake device.")
                    .foregroundStyle(.secondary)
                Button("Run simulated update") { model.runDryRun() }
                    .buttonStyle(.borderedProminent)
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var monitorCard: some View {
        GroupBox("HID monitor (simulated)") {
            VStack(alignment: .leading, spacing: 6) {
                if model.events.isEmpty {
                    Text("Run a simulation to see decoded reports.").foregroundStyle(.secondary)
                }
                ForEach(model.events) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.direction.rawValue)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(event.direction == .transmit ? .blue : .green)
                            .frame(width: 48, alignment: .leading)
                        Text(event.message).font(.system(.caption, design: .monospaced))
                        if !event.bytes.isEmpty {
                            Text(event.bytes.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " "))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diagnosticRow(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption.bold())
            Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}
