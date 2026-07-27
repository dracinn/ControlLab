import SwiftUI
import Vader5Core

private enum ConfigurationTab: String, CaseIterable {
    case common = "Common"
    case button = "Button"
    case joystick = "Joystick"
    case motion = "Motion"
    case trigger = "Trigger"

    var icon: String {
        switch self {
        case .common: "dial.medium"
        case .button: "button.programmable"
        case .joystick: "circle.grid.cross"
        case .motion: "gyroscope"
        case .trigger: "hand.point.up.left.fill"
        }
    }
}

private enum StickSide: String, CaseIterable, Codable { case left = "Left joystick", right = "Right joystick" }
private enum TriggerSide: String, CaseIterable, Codable { case left = "Left trigger", right = "Right trigger" }
private enum CurvePreset: String, CaseIterable, Codable { case standard = "Default", instant = "Instant", delay = "Delay", custom = "Custom" }
private enum Circularity: String, CaseIterable, Codable { case rectangle = "Rectangle", circle = "Circle" }
private enum SleepTime: String, CaseIterable, Codable { case oneMinute = "1 min", fiveMinutes = "5 min", fifteenMinutes = "15 min", oneHour = "1 h", threeHours = "3 h", never = "Never" }
private enum CenterSensitivity: String, CaseIterable, Codable { case fast = "Fast", medium = "Medium", slow = "Slow" }
private enum Accuracy: String, CaseIterable, Codable { case twelve = "12 bit", eleven = "11 bit", ten = "10 bit", nine = "9 bit", eight = "8 bit" }
private enum MappingKind: String, CaseIterable, Codable { case click = "Click", turbo = "Turbo", macro = "Macro", special = "Special" }
private enum TurboActivation: String, CaseIterable, Codable { case hold = "Hold for turbo", toggle = "Press to toggle", burst = "Burst" }
private enum GyroOutput: String, CaseIterable, Codable { case rightStick = "Right joystick", leftStick = "Left joystick", mouse = "Mouse" }
private enum GyroActivation: String, CaseIterable, Codable { case always = "Always on", hold = "While held", toggle = "Press to toggle" }
private enum TriggerMode: String, CaseIterable, Codable {
    case common = "Normal"
    case racing = "Racing"
    case sniper = "Sniper"
    case recoil = "Recoil"
    case lock = "Trigger lock"
    case vibration = "Vibration"
}

private struct StickDraft: Codable, Equatable {
    var circularity: Circularity = .rectangle
    var curve: CurvePreset = .standard
    var centerOffset = 0.0
    var centerDeadZone = 0.0
    var edgeOffset = 0.0
    var edgeDeadZone = 0.0
    var customMidpoint = 50.0
}

private struct ButtonDraft: Codable, Equatable {
    var source = "M1"
    var destination = "A"
    var kind: MappingKind = .click
    var turboActivation: TurboActivation = .hold
    var turboFrequency = 15.0
    var macroPreview = "A · 50 ms · B"
}

private struct ConfigurationProfile: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    var gripVibration = true
    var gripVibrationIntensity = 50.0
    var sleepTime: SleepTime = .fifteenMinutes
    var fastSwap = false
    var turboEnabled = false
    var joystickDebounce = true
    var automaticCalibration = true
    var rebounceAlgorithm = true
    var accuracy: Accuracy = .ten
    var centerSensitivity: CenterSensitivity = .medium
    var leftStick = StickDraft()
    var rightStick = StickDraft()
    var button = ButtonDraft()
    var gyroEnabled = false
    var gyroOutput: GyroOutput = .rightStick
    var gyroActivation: GyroActivation = .hold
    var gyroActivationButton = "LT"
    var gyroHorizontalSensitivity = 50.0
    var gyroVerticalSensitivity = 50.0
    var invertGyroX = false
    var invertGyroY = false
    var leftTriggerStart = 0.0
    var leftTriggerEnd = 100.0
    var leftTriggerMode: TriggerMode?
    var rightTriggerStart = 0.0
    var rightTriggerEnd = 100.0
    var rightTriggerMode: TriggerMode?
    var triggerVibration = true
    var triggerVibrationIntensity = 50.0
}

@MainActor
private final class ControllerConfigurationModel: ObservableObject {
    @Published var profiles: [ConfigurationProfile]
    @Published var selectedProfile: Int

    private static let profilesKey = "ControlLab.controllerProfiles.v1"
    private static let selectionKey = "ControlLab.selectedControllerProfile.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([ConfigurationProfile].self, from: data),
           decoded.count == 4 {
            profiles = decoded
        } else {
            profiles = (1...4).map { ConfigurationProfile(id: $0, name: "Config \($0)") }
        }
        selectedProfile = min(max(UserDefaults.standard.integer(forKey: Self.selectionKey), 0), 3)
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Self.profilesKey)
        }
        UserDefaults.standard.set(selectedProfile, forKey: Self.selectionKey)
    }

    func restoreSelected() {
        let id = profiles[selectedProfile].id
        profiles[selectedProfile] = ConfigurationProfile(id: id, name: "Config \(id)")
    }
}

struct ControllerConfigurationView: View {
    let state: Vader5State
    @StateObject private var model = ControllerConfigurationModel()
    @State private var tab: ConfigurationTab = .common
    @State private var stickSide: StickSide = .left
    @State private var triggerSide: TriggerSide = .left

    private let background = SpaceStationTheme.darkest
    private let sidebar = SpaceStationTheme.secondDark
    private let surface = SpaceStationTheme.thirdDark
    private let border = SpaceStationTheme.line
    private let accent = SpaceStationTheme.accent

    var body: some View {
        HStack(spacing: 0) {
            profileRail
            ScrollView {
                VStack(spacing: 0) {
                    controllerHero
                    tabBar
                    settingsContent
                        .padding(.horizontal, 24)
                        .padding(.vertical, 36)
                }
            }
        }
        .background(background)
        .onChange(of: model.profiles) { _ in model.save() }
        .onChange(of: model.selectedProfile) { _ in model.save() }
    }

    private var profileBinding: Binding<ConfigurationProfile> {
        $model.profiles[model.selectedProfile]
    }

    private var controllerHero: some View {
        ZStack {
            background
            Ellipse()
                .fill(accent.opacity(0.42))
                .frame(width: 720, height: 92)
                .blur(radius: 70)
                .offset(y: 132)
            ControllerInputView(state: state)
                .frame(height: 324)
                .padding(.horizontal, 34)
            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("VADER 5 PRO")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.3)
                            .foregroundStyle(SpaceStationTheme.secondaryText)
                        Text(model.profiles[model.selectedProfile].name)
                            .font(.title3.weight(.medium))
                    }
                    Spacer()
                    Label("Onboard \(model.selectedProfile + 1)",
                          systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))
                }
                Spacer()
            }
            .padding(20)
        }
        .frame(height: 340)
        .clipped()
    }

    private var profileRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ONBOARD CONFIGS").font(.system(size: 9, weight: .bold))
                .tracking(1).foregroundStyle(.secondary)
            ForEach(model.profiles.indices, id: \.self) { index in
                Button { model.selectedProfile = index } label: {
                    HStack {
                        Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                        Text(model.profiles[index].name).font(.callout.weight(.medium))
                        Spacer()
                        if model.selectedProfile == index {
                            Circle().fill(accent).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 10).frame(height: 39)
                    .background(model.selectedProfile == index ? accent.opacity(0.15) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(model.selectedProfile == index ? accent.opacity(0.7) : border))
                }
                .buttonStyle(.plain)
            }

            Text("PROFILE NAME")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(SpaceStationTheme.secondaryText)
                .padding(.top, 8)
            TextField("Profile name", text: profileBinding.name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(border))

            Toggle("Fast swap", isOn: profileBinding.fastSwap)
                .font(.caption).padding(.top, 8)
            Divider().overlay(border).padding(.vertical, 4)
            Text("Drafts are saved on this Mac. Device profile writes remain disabled until the USB protocol is verified.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Restore this draft") { model.restoreSelected() }
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
            Button("Apply to controller") {}
                .buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(true)
        }
        .padding(14).frame(width: 184)
        .background(sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(border).frame(width: 1) }
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(ConfigurationTab.allCases, id: \.self) { item in
                Button { tab = item } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.caption.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 36)
                        .foregroundStyle(tab == item ? .white : .secondary)
                        .background(alignment: .bottom) {
                            if tab == item {
                                LinearGradient(
                                    colors: [.clear, accent, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .background(sidebar)
        .overlay(alignment: .top) { Rectangle().fill(border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(border).frame(height: 1) }
    }

    @ViewBuilder private var settingsContent: some View {
        switch tab {
        case .common: commonSettings
        case .button: buttonSettings
        case .joystick: joystickSettings
        case .motion: gyroSettings
        case .trigger: triggerSettings
        }
    }

    private var commonSettings: some View {
        HStack(alignment: .top, spacing: 16) {
            ConfigPanel(title: "Controller", icon: "power") {
                ConfigPicker(title: "Controller sleep time", selection: profileBinding.sleepTime)
                Toggle("Enable turbo function", isOn: profileBinding.turboEnabled)
                Toggle("Allow fast profile swap", isOn: profileBinding.fastSwap)
            }
            ConfigPanel(title: "Vibration", icon: "waveform.path") {
                Toggle("Grip vibration", isOn: profileBinding.gripVibration)
                ConfigSlider(title: "Grip vibration intensity", value: profileBinding.gripVibrationIntensity,
                             range: 0...100, suffix: "%")
                    .disabled(!profileBinding.wrappedValue.gripVibration)
                Button("Vibration test") {}.buttonStyle(.bordered).disabled(true)
            }
            ConfigPanel(title: "Joystick global settings", icon: "circle.grid.cross") {
                Toggle("Joystick debounce", isOn: profileBinding.joystickDebounce)
                Toggle("Automatic calibration", isOn: profileBinding.automaticCalibration)
                Toggle("Rebounce algorithm", isOn: profileBinding.rebounceAlgorithm)
                ConfigPicker(title: "Accuracy", selection: profileBinding.accuracy)
                ConfigPicker(title: "Center sensitivity", selection: profileBinding.centerSensitivity)
            }
        }
    }

    private var buttonSettings: some View {
        ConfigPanel(title: "Button assignment", icon: "button.programmable") {
            Picker("Mapping type", selection: profileBinding.button.kind) {
                ForEach(MappingKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack(spacing: 18) {
                ConfigStringPicker(title: "Input", selection: profileBinding.button.source,
                                   values: buttonNames)
                Image(systemName: "equal").foregroundStyle(.secondary)
                ConfigStringPicker(title: "Output", selection: profileBinding.button.destination,
                                   values: outputNames)
            }
            switch profileBinding.wrappedValue.button.kind {
            case .click:
                HelpRow("Choose any controller, keyboard, or mouse output for the selected input.")
            case .turbo:
                ConfigPicker(title: "Activation method", selection: profileBinding.button.turboActivation)
                ConfigSlider(title: "Frequency", value: profileBinding.button.turboFrequency,
                             range: 1...30, suffix: " presses/s")
            case .macro:
                ConfigField(title: "Macro preview", text: profileBinding.button.macroPreview)
                HelpRow("Macro timing is stored in the local draft; controller writes are not enabled.")
            case .special:
                HelpRow("Special outputs include mouse clicks, wheel directions, keyboard keys, and Disabled.")
            }
        }
    }

    private var joystickSettings: some View {
        VStack(spacing: 14) {
            Picker("Joystick", selection: $stickSide) {
                ForEach(StickSide.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 330)
            HStack(alignment: .top, spacing: 16) {
                ConfigPanel(title: "Mapping", icon: "arrow.triangle.2.circlepath") {
                    LabeledContent("Mapping to", value: "Joystick")
                    ConfigPicker(title: "Circularity algorithm", selection: stickBinding.circularity)
                    HelpRow("Rectangle favors active range; Circle favors even directionality.")
                }
                ConfigPanel(title: "Sensitivity curve", icon: "chart.xyaxis.line") {
                    ConfigPicker(title: "Curve", selection: stickBinding.curve)
                    sensitivityCurve
                    if stickBinding.wrappedValue.curve == .custom {
                        ConfigSlider(title: "Midpoint", value: stickBinding.customMidpoint,
                                     range: 1...99, suffix: "%")
                    }
                }
                ConfigPanel(title: "Joystick active range", icon: "scope") {
                    ConfigSlider(title: "Center offset", value: stickBinding.centerOffset, range: 0...50, suffix: "%")
                    ConfigSlider(title: "Center dead zone", value: stickBinding.centerDeadZone, range: 0...50, suffix: "%")
                    ConfigSlider(title: "Edge offset", value: stickBinding.edgeOffset, range: 0...50, suffix: "%")
                    ConfigSlider(title: "Edge dead zone", value: stickBinding.edgeDeadZone, range: 0...50, suffix: "%")
                }
            }
        }
    }

    private var stickBinding: Binding<StickDraft> {
        stickSide == .left ? profileBinding.leftStick : profileBinding.rightStick
    }

    private var sensitivityCurve: some View {
        GeometryReader { proxy in
            let inset = 12.0
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    Path { path in
                        let x = inset + (proxy.size.width - inset * 2) * Double(index) / 5
                        path.move(to: CGPoint(x: x, y: inset)); path.addLine(to: CGPoint(x: x, y: proxy.size.height - inset))
                        let y = inset + (proxy.size.height - inset * 2) * Double(index) / 5
                        path.move(to: CGPoint(x: inset, y: y)); path.addLine(to: CGPoint(x: proxy.size.width - inset, y: y))
                    }.stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
                Path { path in
                    path.move(to: CGPoint(x: inset, y: proxy.size.height - inset))
                    let curve = stickBinding.wrappedValue.curve
                    let midpoint = curve == .instant ? 25.0 : curve == .delay ? 75.0 : stickBinding.wrappedValue.customMidpoint
                    path.addLine(to: CGPoint(x: proxy.size.width / 2,
                                             y: proxy.size.height - inset - (proxy.size.height - inset * 2) * midpoint / 100))
                    path.addLine(to: CGPoint(x: proxy.size.width - inset, y: inset))
                }.stroke(accent, lineWidth: 2)
            }
            .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        }.frame(height: 130)
    }

    private var gyroSettings: some View {
        HStack(alignment: .top, spacing: 16) {
            ConfigPanel(title: "Gyro mapping", icon: "gyroscope") {
                Toggle("Enable gyro mapping", isOn: profileBinding.gyroEnabled)
                ConfigPicker(title: "Mapping to", selection: profileBinding.gyroOutput)
                ConfigPicker(title: "Activation method", selection: profileBinding.gyroActivation)
                if profileBinding.wrappedValue.gyroActivation != .always {
                    ConfigStringPicker(title: "Activation button", selection: profileBinding.gyroActivationButton,
                                       values: buttonNames)
                }
            }
            ConfigPanel(title: "Gyro sensitivity", icon: "move.3d") {
                ConfigSlider(title: "Horizontal", value: profileBinding.gyroHorizontalSensitivity, range: 1...100, suffix: "%")
                ConfigSlider(title: "Vertical", value: profileBinding.gyroVerticalSensitivity, range: 1...100, suffix: "%")
                Toggle("Invert horizontal axis", isOn: profileBinding.invertGyroX)
                Toggle("Invert vertical axis", isOn: profileBinding.invertGyroY)
            }.disabled(!profileBinding.wrappedValue.gyroEnabled)
            ConfigPanel(title: "Live sensor", icon: "waveform.path.ecg") {
                SensorRow(name: "Gyro", values: state.gyro)
                SensorRow(name: "Accelerometer", values: state.accelerometer)
            }
        }
    }

    private var triggerSettings: some View {
        VStack(spacing: 14) {
            Picker("Trigger", selection: $triggerSide) {
                ForEach(TriggerSide.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 330)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 24)],
                alignment: .leading,
                spacing: 24
            ) {
                ConfigPanel(title: "Trigger mode", icon: "hand.point.up.left.fill") {
                    ConfigPicker(title: "Mode", selection: triggerModeBinding)
                    TriggerModePreview(mode: triggerModeBinding.wrappedValue)
                    HelpRow(triggerModeDescription)
                }
                ConfigPanel(title: "Trigger active range", icon: "slider.horizontal.below.rectangle") {
                    ConfigSlider(title: "Start point", value: triggerStartBinding, range: 0...99, suffix: "%")
                    ConfigSlider(title: "End point", value: triggerEndBinding, range: 1...100, suffix: "%")
                    HelpRow("The end point should remain above the start point.")
                }
                ConfigPanel(title: "Trigger vibration", icon: "waveform.path") {
                    Toggle("Enable trigger vibration", isOn: profileBinding.triggerVibration)
                    ConfigSlider(title: "Intensity", value: profileBinding.triggerVibrationIntensity,
                                 range: 0...100, suffix: "%")
                        .disabled(!profileBinding.wrappedValue.triggerVibration)
                    Button("Vibration test") {}.buttonStyle(.bordered).disabled(true)
                }
                ConfigPanel(title: "Live input", icon: "gauge.with.dots.needle.33percent") {
                    ProgressView(value: Double(triggerSide == .left ? state.leftTrigger : state.rightTrigger), total: 255)
                        .tint(accent)
                    Text("\(triggerSide == .left ? state.leftTrigger : state.rightTrigger) / 255")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var triggerStartBinding: Binding<Double> {
        triggerSide == .left ? profileBinding.leftTriggerStart : profileBinding.rightTriggerStart
    }

    private var triggerEndBinding: Binding<Double> {
        triggerSide == .left ? profileBinding.leftTriggerEnd : profileBinding.rightTriggerEnd
    }

    private var triggerModeBinding: Binding<TriggerMode> {
        Binding(
            get: {
                if triggerSide == .left {
                    return profileBinding.wrappedValue.leftTriggerMode ?? .common
                }
                return profileBinding.wrappedValue.rightTriggerMode ?? .common
            },
            set: { mode in
                var profile = profileBinding.wrappedValue
                if triggerSide == .left {
                    profile.leftTriggerMode = mode
                } else {
                    profile.rightTriggerMode = mode
                }
                profileBinding.wrappedValue = profile
            })
    }

    private var triggerModeDescription: String {
        switch triggerModeBinding.wrappedValue {
        case .common: "Linear travel using the selected active range."
        case .racing: "Progressive resistance intended for throttle and braking."
        case .sniper: "A short, controlled pull for precise activation."
        case .recoil: "Simulated repeated resistance for automatic fire."
        case .lock: "Restricts the trigger to a short digital-style pull."
        case .vibration: "Adds trigger vibration across the active range."
        }
    }

    private let buttonNames = ["A", "B", "X", "Y", "C", "Z", "LB", "RB", "LT", "RT", "L3", "R3", "M1", "M2", "M3", "M4", "LM", "RM", "View", "Menu", "Home", "Fn"]
    private let outputNames = ["A", "B", "X", "Y", "C", "Z", "LB", "RB", "LT", "RT", "L3", "R3", "View", "Menu", "Home", "Left click", "Right click", "Wheel up", "Wheel down", "Keyboard key", "Disabled"]
}

private struct ConfigPanel<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: icon).font(.callout.weight(.semibold))
            content
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(SpaceStationTheme.thirdDark,
                    in: RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius))
        .overlay(RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius)
            .stroke(SpaceStationTheme.line))
    }
}

private struct TriggerModePreview: View {
    let mode: TriggerMode

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                Capsule()
                    .fill(SpaceStationTheme.accent)
                    .frame(width: fillWidth, height: 6)
            }
            HStack {
                Text("TRAVEL")
                Spacer()
                Text(mode.rawValue.uppercased())
            }
            .font(.system(size: 9, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(SpaceStationTheme.secondaryText)
        }
        .padding(12)
        .background(SpaceStationTheme.darkest,
                    in: RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius))
    }

    private var fillWidth: CGFloat {
        switch mode {
        case .common: 210
        case .racing: 180
        case .sniper: 90
        case .recoil: 145
        case .lock: 58
        case .vibration: 170
        }
    }
}

private struct ConfigSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title); Spacer(); Text("\(Int(value.rounded()))\(suffix)").monospacedDigit() }
                .font(.caption)
            Slider(value: $value, in: range, step: 1)
        }
    }
}

private struct ConfigPicker<Value: Hashable & RawRepresentable>: View where Value.RawValue == String, Value: CaseIterable {
    let title: String
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(Array(Value.allCases), id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(SpaceStationTheme.darkest,
                        in: RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius))
            .overlay(RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius)
                .stroke(SpaceStationTheme.line))
        }
    }
}

private struct ConfigStringPicker: View {
    let title: String
    @Binding var selection: String
    let values: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(SpaceStationTheme.darkest,
                        in: RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius))
            .overlay(RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius)
                .stroke(SpaceStationTheme.line))
        }
    }
}

private struct ConfigField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(SpaceStationTheme.darkest,
                            in: RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius))
                .overlay(RoundedRectangle(cornerRadius: SpaceStationTheme.smallRadius)
                    .stroke(SpaceStationTheme.line))
        }
    }
}

private struct HelpRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label(text, systemImage: "info.circle").font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SensorRow: View {
    let name: String
    let values: Vector3
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text("X \(values.x)   Y \(values.y)   Z \(values.z)")
                .font(.system(.caption, design: .monospaced))
        }
    }
}
