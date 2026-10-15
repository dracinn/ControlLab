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
    @Published var downloadingModule: String?
    @Published var firmwareDownloadMessage: String?
    @Published var firmwareDownloadError: String?
    @Published var selectedPackageIsTelinkImage = false
    @Published var selectedPackageIsMainImage = false
    @Published var dongleChannelPresent = false
    @Published var rfChannelPresent = false
    @Published var mainChannelPresent = false
    @Published var isUpdating = false
    @Published var isUpdatingMain = false
    @Published var updateSent = 0
    @Published var updateTotal = 0
    @Published var updateMessage: String?
    @Published var pendingUpdateTarget: InstallTarget?
    @Published var showEventLog = false
    private var selectedPackage: Data?

    enum InstallTarget: Equatable {
        case dongle
        case controllerRF
        case main

        var displayName: String {
            switch self {
            case .dongle: "dongle"
            case .controllerRF: "controller RF"
            case .main: "main chip"
            }
        }
    }

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
                    appVersion: "5.0.0.0"
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
            refreshUpdateAvailability()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func downloadFirmware(_ release: Vader5FirmwareRelease, module: String) {
        guard downloadingModule == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = release.url.lastPathComponent.isEmpty
            ? "\(module.lowercased())-\(release.version).fwpkg"
            : release.url.lastPathComponent
        panel.message = "Save the firmware package for offline inspection. It will not be installed."
        panel.prompt = "Download"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        downloadingModule = module
        firmwareDownloadMessage = nil
        firmwareDownloadError = nil
        Task {
            do {
                let info = try await Vader5FirmwareDownloadClient().download(
                    release: release,
                    to: destination)
                selectedPackage = try Data(contentsOf: destination)
                packageInfo = info
                refreshUpdateAvailability()
                firmwareDownloadMessage = "Saved \(module) \(release.version) as \(info.fileName) (SHA-256 \(info.sha256.prefix(12))…)."
            } catch {
                firmwareDownloadError = String(describing: error)
            }
            downloadingModule = nil
        }
    }

    private func refreshUpdateAvailability() {
        selectedPackageIsTelinkImage =
            selectedPackage.map { (try? Vader5DongleUpdater.validate(image: $0)) != nil } ?? false
        selectedPackageIsMainImage =
            selectedPackage.map { (try? Vader5MainUpdater.validate(image: $0)) != nil } ?? false
        Task.detached(priority: .utility) {
            let dongle = Vader5DongleUpdater.isChannelPresent(target: .dongle)
            let rf = Vader5DongleUpdater.isChannelPresent(target: .controllerRF)
            let main = Vader5MainUpdater.isChannelPresent()
            Task { @MainActor in
                self.dongleChannelPresent = dongle
                self.rfChannelPresent = rf
                self.mainChannelPresent = main
            }
        }
    }

    func startUpdate(target: InstallTarget) {
        switch target {
        case .main:
            startMainUpdate()
        case .dongle:
            startTelinkUpdate(target: .dongle)
        case .controllerRF:
            startTelinkUpdate(target: .controllerRF)
        }
    }

    private func startMainUpdate() {
        guard let image = selectedPackage, !isUpdating else { return }
        isUpdating = true
        isUpdatingMain = true
        updateSent = 0
        updateTotal = 0
        updateMessage = nil
        errorMessage = nil
        events = []
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let updater = Vader5MainUpdater()
                    updater.onPhase = { phase in
                        Task { @MainActor in
                            switch phase {
                            case let .programming(sent, total):
                                self.updateSent = sent
                                self.updateTotal = total
                            case let .verifying(read, total):
                                self.updateSent = read
                                self.updateTotal = total
                            default:
                                break
                            }
                        }
                    }
                    updater.onEvent = { event in
                        Task { @MainActor in self.events.append(event) }
                    }
                    try updater.update(image: image)
                }.value
                updateMessage = "Main chip update committed successfully. The controller rebooted into the new image."
                try? await Task.sleep(for: .seconds(2))
                checkFirmware()
            } catch {
                errorMessage = String(describing: error)
            }
            isUpdating = false
            isUpdatingMain = false
        }
    }

    private func startTelinkUpdate(target: Vader5DongleUpdater.Target) {
        guard let image = selectedPackage, !isUpdating else { return }
        isUpdating = true
        updateSent = 0
        updateTotal = 0
        updateMessage = nil
        errorMessage = nil
        events = []
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let updater = Vader5DongleUpdater(target: target)
                    updater.onPhase = { phase in
                        guard case let .transferring(sent, total) = phase else { return }
                        Task { @MainActor in
                            self.updateSent = sent
                            self.updateTotal = total
                        }
                    }
                    updater.onEvent = { event in
                        Task { @MainActor in self.events.append(event) }
                    }
                    _ = try updater.update(image: image)
                }.value
                updateMessage = "\(target.displayName.capitalized) update committed successfully. The device rebooted into the new image."
                try? await Task.sleep(for: .seconds(2))
                checkFirmware()
            } catch {
                errorMessage = String(describing: error)
            }
            isUpdating = false
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
                packageCard
                monitorCard
            }
            .padding(22)
        }
        .task { model.checkFirmwareIfNeeded() }
    }

    private var safetyCard: some View {
        GroupBox {
            Label(
                "Firmware metadata requires the USB receiver. Telink OTA updates run the verified flow on the receiver's FFEE channel (dongle) or the cabled controller's FFEF channel (RF), ask for confirmation before writing, and the chip validates the image before committing.",
                systemImage: "lock.shield.fill"
            )
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        } label: { Text("Firmware diagnostics") }
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
                if let message = model.firmwareDownloadMessage {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let error = model.firmwareDownloadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
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
            if let available {
                Button {
                    model.downloadFirmware(available, module: name)
                } label: {
                    if model.downloadingModule == name {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .controlSize(.small)
                .disabled(model.downloadingModule != nil)
            } else {
                Color.clear.frame(width: 94, height: 1)
            }
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
                    if let layout = info.nearLinkLayout {
                        diagnosticRow("Subpackage", "\(layout.subpackageMagic) @ 0x\(String(layout.subpackageOffset, radix: 16).uppercased()), \(layout.subpackageLength) bytes")
                        diagnosticRow("Protected payload", "0x\(String(layout.payloadOffset, radix: 16).uppercased()) + \(layout.payloadLength) bytes")
                        diagnosticRow("Payload header", layout.payloadHeader)
                        diagnosticRow("Payload SHA-256", layout.payloadSHA256Matches ? "Verified: \(layout.payloadSHA256)" : "Mismatch: \(layout.payloadSHA256)")
                    }
                } else {
                    Text("Read metadata and hashes without extracting or modifying the package.")
                        .foregroundStyle(.secondary)
                }
                Button("Inspect .fwpkg…") { model.inspectPackage() }
                    .buttonStyle(.bordered)

                if model.selectedPackageIsTelinkImage || model.selectedPackageIsMainImage {
                    Divider()
                    if model.isUpdating {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Updating — do not unplug or power off.")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.orange)
                            ProgressView(
                                value: Double(model.updateSent),
                                total: Double(max(model.updateTotal, 1)))
                            Text("\(model.updateSent)/\(model.updateTotal) \(model.isUpdatingMain ? "bytes" : "blocks")")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 10) {
                            if model.selectedPackageIsTelinkImage && model.dongleChannelPresent {
                                Button {
                                    model.pendingUpdateTarget = .dongle
                                } label: {
                                    Label("Install to dongle", systemImage: "memorychip")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            if model.selectedPackageIsTelinkImage && model.rfChannelPresent {
                                Button {
                                    model.pendingUpdateTarget = .controllerRF
                                } label: {
                                    Label("Install to controller RF", systemImage: "memorychip")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            if model.selectedPackageIsMainImage && model.mainChannelPresent {
                                Button {
                                    model.pendingUpdateTarget = .main
                                } label: {
                                    Label("Install to main chip", systemImage: "memorychip")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                            let noChannel = (model.selectedPackageIsTelinkImage && !model.dongleChannelPresent && !model.rfChannelPresent)
                                || (model.selectedPackageIsMainImage && !model.mainChannelPresent)
                            if noChannel {
                                Label(
                                    model.selectedPackageIsMainImage
                                        ? "The controller's USB-C command channel is not connected."
                                        : "No Telink update channel is connected (receiver FFEE or cabled controller FFEF).",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Text("Installing writes this image to the selected chip. The device verifies every byte before the commit command is sent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = model.updateMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .alert(
            "Update \(model.pendingUpdateTarget?.displayName ?? "device")?",
            isPresented: Binding(
                get: { model.pendingUpdateTarget != nil },
                set: { if !$0 { model.pendingUpdateTarget = nil } }
            )
        ) {
            Button("Update", role: .destructive) {
                if let target = model.pendingUpdateTarget {
                    model.startUpdate(target: target)
                }
                model.pendingUpdateTarget = nil
            }
            Button("Cancel", role: .cancel) { model.pendingUpdateTarget = nil }
        } message: {
            Text(confirmationText(for: model.pendingUpdateTarget))
        }
    }

    private func confirmationText(for target: FirmwareDiagnosticsViewModel.InstallTarget?) -> String {
        switch target {
        case .dongle:
            "This writes the selected image to the receiver's dongle chip. Keep the receiver plugged in until the update completes."
        case .controllerRF:
            "This writes the selected image to the controller's RF chip over its USB-C connection. Only install an image Flydigi published for the RF module, and keep the controller cabled until the update completes."
        case .main:
            "This reboots the controller's main chip into the Megahunt boot device and writes the selected image. Only install an image Flydigi published for the main chip, keep the controller cabled, and do not unplug it until the update completes."
        case nil:
            ""
        }
    }

    private var monitorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let last = model.events.last {
                    HStack(spacing: 14) {
                        monitorStat("TX", model.events.lazy.filter { $0.direction == .transmit }.count, .blue)
                        monitorStat("RX", model.events.lazy.filter { $0.direction == .receive }.count, .green)
                        if model.events.contains(where: { $0.direction == .status }) {
                            monitorStat("STATUS", model.events.lazy.filter { $0.direction == .status }.count, .orange)
                        }
                        Divider().frame(height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(last.message).font(.caption.weight(.semibold))
                            Text("\(last.direction.rawValue) · \(last.timestamp.formatted(date: .omitted, time: .standard))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    Text("OTA frames exchanged with the receiver appear here during an update.")
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Packet log (\(model.events.count))", isExpanded: $model.showEventLog) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 3) {
                                ForEach(model.events.suffix(80)) { event in
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
                                    .id(event.id)
                                }
                            }
                        }
                        .frame(height: 180)
                        .onChange(of: model.events.count) { _ in
                            if let last = model.events.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .disabled(model.events.isEmpty)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("HID monitor", systemImage: "waveform.path.ecg")
        }
    }

    private func monitorStat(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)").font(.callout.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }
    }

    private func diagnosticRow(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption.bold())
            Text(value).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}
