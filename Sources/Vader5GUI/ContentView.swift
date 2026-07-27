import AppKit
import SwiftUI
import Vader5Core

private enum WorkspacePage: String, CaseIterable {
    case controller = "Controller"
    case configuration = "Configuration"
    case lighting = "Lighting"
    case firmware = "Firmware"

    var icon: String {
        switch self {
        case .controller: "gamecontroller.fill"
        case .configuration: "slider.horizontal.3"
        case .lighting: "lightbulb.led.fill"
        case .firmware: "memorychip.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .controller: "Live input and motion data"
        case .configuration: "Profiles, mappings, sticks, gyro, and triggers"
        case .lighting: "RGB effects and device presets"
        case .firmware: "Versions, packages, and safe diagnostics"
        }
    }
}

private enum CLTheme {
    static let background = Color(red: 0.055, green: 0.063, blue: 0.078)
    static let sidebar = Color(red: 0.075, green: 0.084, blue: 0.102)
    static let surface = Color(red: 0.095, green: 0.106, blue: 0.128)
    static let raised = Color(red: 0.12, green: 0.132, blue: 0.157)
    static let border = Color.white.opacity(0.075)
    static let accent = Color(red: 0.23, green: 0.58, blue: 1)
}

struct ContentView: View {
    @ObservedObject var model: BridgeViewModel
    @State private var page: WorkspacePage = .controller

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                topBar
                Divider().overlay(CLTheme.border)
                pageContent
            }
        }
        .background(CLTheme.background)
        .preferredColorScheme(.dark)
        .tint(CLTheme.accent)
        .onDisappear { model.stop() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(CLTheme.accent.gradient)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 0) {
                    Text("ControlLab").font(.headline.weight(.bold))
                    Text("DEVICE STUDIO").font(.system(size: 8, weight: .bold))
                        .tracking(1.2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 19)

            VStack(alignment: .leading, spacing: 4) {
                Text("DEVICE").font(.system(size: 9, weight: .bold))
                    .tracking(1.1).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(CLTheme.raised)
                        .frame(width: 42, height: 42)
                        .overlay(Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 19)).foregroundStyle(CLTheme.accent))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Vader 5 Pro").font(.callout.weight(.semibold))
                        HStack(spacing: 5) {
                            Circle().fill(model.isRunning ? .green : .secondary)
                                .frame(width: 6, height: 6)
                            Text(model.statusTitle).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(CLTheme.surface, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(CLTheme.border))
            }
            .padding(.horizontal, 14).padding(.bottom, 20)

            Text("WORKSPACE").font(.system(size: 9, weight: .bold))
                .tracking(1.1).foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.bottom, 8)
            VStack(spacing: 5) {
                ForEach(WorkspacePage.allCases, id: \.self) { item in
                    SidebarButton(page: item, selected: page == item) { page = item }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 11) {
                Picker("Connection", selection: $model.transport) {
                    ForEach(Vader5Transport.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.isRunning)

                Picker("Mode", selection: $model.mode) {
                    ForEach(Vader5BridgeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                .disabled(model.isRunning || model.transport == .bluetooth)

                Button { model.toggle() } label: {
                    Label(model.isRunning ? "Disconnect" : "Connect device",
                          systemImage: model.isRunning ? "stop.fill" : "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(CLTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(CLTheme.border))
            .padding(12)
        }
        .frame(width: 218)
        .background(CLTheme.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(CLTheme.border).frame(width: 1) }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.rawValue).font(.title2.weight(.semibold))
                Text(page.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.transport == .usbReceiver {
                StatusPill(text: "USB 37D7:2401", icon: "cable.connector")
            } else {
                StatusPill(text: "Bluetooth", icon: "antenna.radiowaves.left.and.right")
            }
            StatusPill(
                text: model.isRunning ? "ONLINE" : "OFFLINE",
                icon: model.isRunning ? "checkmark.circle.fill" : "circle.dashed",
                tint: model.isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 24).frame(height: 72)
        .background(CLTheme.sidebar.opacity(0.72))
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .controller: controllerPage
        case .configuration: ControllerConfigurationView(state: model.state)
        case .lighting: lightingPage
        case .firmware:
            FirmwareDiagnosticsView().background(CLTheme.background)
        }
    }

    private var controllerPage: some View {
        ScrollView {
            VStack(spacing: 16) {
                errorBanner
                HStack(alignment: .top, spacing: 16) {
                    StudioPanel(title: "Input preview", icon: "dot.scope") {
                        ControllerInputView(state: model.state, allowsLayoutEditing: true)
                            .frame(minHeight: 390)
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        liveStatusPanel
                        analogPanel
                        pressedButtonsPanel
                    }
                    .frame(width: 270)
                }
                motionPanel
            }
            .padding(20)
        }
    }

    private var liveStatusPanel: some View {
        StudioPanel(title: "Device status", icon: "wave.3.right") {
            VStack(spacing: 12) {
                DetailRow(name: "Connection", value: model.transport.rawValue)
                DetailRow(name: "Bridge", value: model.statusTitle)
                DetailRow(name: "D-pad", value: dpadName)
                DetailRow(name: "Active buttons", value: "\(model.state.buttons.rawValue.nonzeroBitCount)")
            }
        }
    }

    private var analogPanel: some View {
        StudioPanel(title: "Analog input", icon: "slider.horizontal.3") {
            VStack(spacing: 12) {
                AnalogMeter(label: "LT", value: model.state.leftTrigger)
                AnalogMeter(label: "RT", value: model.state.rightTrigger)
                Divider().overlay(CLTheme.border)
                Text("L  \(model.state.leftX), \(model.state.leftY)")
                Text("R  \(model.state.rightX), \(model.state.rightY)")
            }
            .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    private var pressedButtonsPanel: some View {
        StudioPanel(title: "Pressed now", icon: "button.programmable") {
            let active = activeButtonNames
            Text(active.isEmpty ? "No buttons pressed" : active.joined(separator: "  •  "))
                .font(.caption.weight(active.isEmpty ? .regular : .semibold))
                .foregroundStyle(active.isEmpty ? .secondary : CLTheme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var motionPanel: some View {
        StudioPanel(title: "Motion telemetry", icon: "gyroscope") {
            HStack(spacing: 0) {
                MotionReadout(title: "GYROSCOPE", vector: model.state.gyro)
                Divider().frame(height: 58).overlay(CLTheme.border)
                MotionReadout(title: "ACCELEROMETER", vector: model.state.accelerometer)
                if model.transport == .bluetooth {
                    Divider().frame(height: 58).overlay(CLTheme.border)
                    Label("Unavailable in the Xbox Bluetooth profile", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var lightingPage: some View {
        ScrollView {
            VStack(spacing: 16) {
                errorBanner
                HStack(alignment: .top, spacing: 16) {
                    StudioPanel(title: "Controller preview", icon: "gamecontroller.fill") {
                        ZStack(alignment: .bottom) {
                            RadialGradient(colors: [CLTheme.accent.opacity(0.16), .clear],
                                           center: .center, startRadius: 20, endRadius: 270)
                            ControllerInputView(state: model.state).frame(minHeight: 410)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    lightingEditor
                        .frame(width: 330)
                }
                dockLightingEditor
            }
            .padding(20)
        }
        .onAppear { model.refreshDockConfiguration() }
    }

    private var lightingEditor: some View {
        StudioPanel(title: "Controller lighting", icon: "lightbulb.led.fill") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    FieldLabel("LIGHTING MODE")
                    Picker("Lighting mode", selection: Binding(
                        get: { model.lightingMode },
                        set: { model.selectLightingMode($0) })) {
                        ForEach(model.availableLightingModes, id: \.self) {
                            Text($0.title).tag($0)
                        }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                    .disabled(!model.canSetLighting)
                }

                if model.lightingMode.usesColors {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack { FieldLabel("COLORS"); Spacer(); Text("\(model.lightingColors.count)/5").font(.caption2).foregroundStyle(.secondary) }
                        HStack(spacing: 10) {
                            ForEach(model.lightingColors.indices, id: \.self) { index in
                                ColorPicker("Color \(index + 1)", selection: $model.lightingColors[index], supportsOpacity: false)
                                    .labelsHidden()
                            }
                            if model.lightingMode.allowsMultipleColors {
                                Button { model.addLightingColor() } label: { Image(systemName: "plus") }
                                    .buttonStyle(.bordered).disabled(model.lightingColors.count >= 5)
                                Button { model.removeLightingColor() } label: { Image(systemName: "minus") }
                                    .buttonStyle(.bordered)
                                    .disabled(model.lightingColors.count <= model.lightingMode.minimumColorCount)
                            }
                        }
                    }
                }

                if model.lightingMode != .off {
                    SliderField(label: "BRIGHTNESS", value: $model.lightingBrightness, suffix: "%")
                }
                if model.lightingMode.isAnimated && model.lightingMode != .off {
                    SliderField(label: "CYCLE TIME", value: $model.lightingPeriod, suffix: "")
                }

                lightingMessage
                Button { model.applyLighting() } label: {
                    Label("Apply to controller", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!model.canSetLighting)
            }
        }
    }

    private var dockLightingEditor: some View {
        StudioPanel(title: "Charging Station 2 Pro", icon: "rectangle.grid.3x2.fill") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            FieldLabel("DOCK DISPLAY PREVIEW")
                            Spacer()
                            Text("3-PIXEL TRIANGLE · 162 PIXELS")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                        }
                        DockLightingPreview(
                            mode: model.dockLightingMode,
                            colors: model.dockLightingColors,
                            brightness: model.dockLightingBrightness,
                            period: model.dockLightingPeriod,
                            direction: model.dockLightingDirection)
                            .frame(maxWidth: 430)
                        Text("Near-front Flydigi Dock 2 Pro product image")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Text("14-pixel straight runs with three-pixel corner clusters")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            FieldLabel("LIGHTING MODE")
                            Picker("Dock lighting mode", selection: Binding(
                                get: { model.dockLightingMode },
                                set: { model.selectDockLightingMode($0) })) {
                                ForEach(model.availableDockLightingModes, id: \.self) {
                                    Text($0.title).tag($0)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .disabled(!model.canSetDockLighting)
                        }

                        if model.dockLightingMode.usesColors {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    FieldLabel(model.dockLightingMode == .custom
                                               ? "FRAME FILL"
                                               : "COLORS")
                                    Spacer()
                                    if model.dockLightingMode.allowsMultipleColors {
                                        Text("\(model.dockLightingColors.count)/5")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                HStack(spacing: 10) {
                                    ForEach(model.dockLightingColors.indices, id: \.self) { index in
                                        ColorPicker(
                                            "Dock color \(index + 1)",
                                            selection: $model.dockLightingColors[index],
                                            supportsOpacity: false)
                                            .labelsHidden()
                                    }
                                    if model.dockLightingMode.allowsMultipleColors {
                                        Button { model.addDockLightingColor() } label: {
                                            Image(systemName: "plus")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(model.dockLightingColors.count >= 5)
                                        Button { model.removeDockLightingColor() } label: {
                                            Image(systemName: "minus")
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(model.dockLightingColors.count <=
                                                  model.dockLightingMode.minimumColorCount)
                                    }
                                }
                            }
                        }

                        if model.dockLightingMode != .off {
                            SliderField(
                                label: "BRIGHTNESS",
                                value: $model.dockLightingBrightness,
                                suffix: "%")
                        }
                        if model.dockLightingMode.isAnimated {
                            SliderField(
                                label: "CYCLE TIME",
                                value: $model.dockLightingPeriod,
                                suffix: "")
                        }
                        if model.dockLightingMode.usesDirection {
                            VStack(alignment: .leading, spacing: 7) {
                                FieldLabel("DIRECTION")
                                Picker("Direction", selection: $model.dockLightingDirection) {
                                    ForEach(FlydigiDockLightingDirection.allCases, id: \.self) {
                                        Text($0.title).tag($0)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            }
                        }

                        dockLightingMessage
                        HStack {
                            Button { model.refreshDockConfiguration() } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.isApplyingDockLighting)
                            Button { model.turnOffDockLighting() } label: {
                                Label("Turn off", systemImage: "power")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!model.canSetDockLighting)
                        }
                        Button { model.applyDockLighting() } label: {
                            Label(
                                model.isApplyingDockLighting ? "Applying…" : "Apply lighting",
                                systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!model.canSetDockLighting)
                    }
                    .frame(width: 330)
                }

                Divider().overlay(CLTheme.border)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            FieldLabel("DEVICE BEHAVIOR")
                            Text("Space Station charging and power settings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !model.dockSettingsLoaded {
                            Label("Waiting for dock configuration",
                                  systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 24) {
                        Toggle(
                            "Sleep while charging",
                            isOn: $model.dockDeviceSettings.sleepWhenCharging)
                        Toggle(
                            "Show charging animation",
                            isOn: $model.dockDeviceSettings.showAnimationWhenCharging)
                        Toggle(
                            "LED sync",
                            isOn: $model.dockDeviceSettings.ledSync)
                        Toggle(
                            "Turn off with system",
                            isOn: $model.dockDeviceSettings.closeWithSystem)
                    }
                    .font(.caption)
                    .disabled(!model.canSetDockDeviceSettings)
                    Button { model.applyDockDeviceSettings() } label: {
                        Label(
                            model.isApplyingDockSettings
                                ? "Saving behavior…"
                                : "Apply device behavior",
                            systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canSetDockDeviceSettings)
                }
            }
        }
    }

    @ViewBuilder private var dockLightingMessage: some View {
        if model.isApplyingDockLighting {
            Label("Sending the 162-pixel frame…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
        } else {
            switch model.dockLightingStatus {
            case .checking:
                Label("Checking the USB dock…", systemImage: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            case .ready:
                Label("USB 37D7:6001", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unavailable(let message):
                Label(message, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var lightingMessage: some View {
        switch model.lightingStatus {
        case .checking:
            Label(model.isRunning ? "Reading current configuration…" : "Connect to check lighting support",
                  systemImage: "ellipsis.circle")
        case .ready(let backend):
            Label(backend.rawValue, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable(let message):
            Label(message, systemImage: "info.circle").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var errorBanner: some View {
        if let message = model.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.callout)
                Spacer()
            }
            .padding(12).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.25)))
        }
    }

    private var dpadName: String {
        let names = ["Up", "Up-right", "Right", "Down-right", "Down", "Down-left", "Left", "Up-left", "Center"]
        return names[min(Int(model.state.dpad), 8)]
    }

    private var activeButtonNames: [String] {
        let buttons: [(String, Vader5Buttons)] = [
            ("A", .a), ("B", .b), ("X", .x), ("Y", .y), ("C", .c), ("Z", .z),
            ("LB", .leftBumper), ("RB", .rightBumper), ("L3", .leftStick), ("R3", .rightStick),
            ("M1", .m1), ("M2", .m2), ("M3", .m3), ("M4", .m4),
            ("LM", .leftMacro), ("RM", .rightMacro), ("View", .select), ("Menu", .start),
            ("Home", .home), ("Fn", .function),
        ]
        return buttons.compactMap { model.state.buttons.contains($0.1) ? $0.0 : nil }
    }
}

private struct SidebarButton: View {
    let page: WorkspacePage
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: page.icon).frame(width: 20)
                Text(page.rawValue).font(.callout.weight(.medium))
                Spacer()
                if selected { RoundedRectangle(cornerRadius: 2).fill(CLTheme.accent).frame(width: 3, height: 18) }
            }
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, 12).frame(height: 40)
            .background(selected ? CLTheme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct StudioPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.callout.weight(.semibold))
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(CLTheme.surface, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(CLTheme.border))
    }
}

private struct StatusPill: View {
    let text: String
    let icon: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: icon).font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(CLTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(CLTheme.border))
    }
}

private struct DetailRow: View {
    let name: String
    let value: String
    var body: some View {
        HStack { Text(name).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) }
            .font(.caption)
    }
}

private struct AnalogMeter: View {
    let label: String
    let value: UInt8
    var body: some View {
        HStack(spacing: 9) {
            Text(label).font(.caption2.bold()).frame(width: 18)
            ProgressView(value: Double(value), total: 255).tint(CLTheme.accent)
            Text("\(value)").font(.system(.caption2, design: .monospaced)).frame(width: 25)
        }
    }
}

private struct MotionReadout: View {
    let title: String
    let vector: Vector3
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
            Text("X  \(vector.x)     Y  \(vector.y)     Z  \(vector.z)")
                .font(.system(.callout, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary) }
}

private struct SliderField: View {
    let label: String
    @Binding var value: Double
    let suffix: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { FieldLabel(label); Spacer(); Text("\(Int(value))\(suffix)").font(.system(.caption, design: .monospaced)) }
            Slider(value: $value, in: 1...100)
        }
    }
}
