import SwiftUI
import Vader5Core

struct ContentView: View {
    @ObservedObject var model: BridgeViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    connectionCard
                    HStack(alignment: .top, spacing: 18) {
                        sticksCard
                        buttonsCard
                    }
                    sensorsCard
                }
                .padding(22)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("Vader 5 Pro").font(.title2.bold())
                Text("macOS bridge").foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)
            Text(model.statusTitle).font(.headline)
        }
        .padding(.horizontal, 22).padding(.vertical, 16)
    }

    private var connectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Mode", selection: $model.mode) {
                    ForEach(Vader5BridgeMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isRunning)

                if model.mode == .virtualGamepad {
                    Label("Requires Apple’s virtual HID entitlement", systemImage: "checkmark.seal")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Label("Reads live controller input without creating a virtual device", systemImage: "waveform.path.ecg")
                        .font(.callout).foregroundStyle(.secondary)
                }

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.callout)
                }

                HStack {
                    Text("USB 37D7:2401").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.isRunning ? "Stop bridge" : "Start bridge") { model.toggle() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(10)
        } label: { Label("Connection", systemImage: "cable.connector") }
    }

    private var sticksCard: some View {
        GroupBox("Analog input") {
            VStack(spacing: 16) {
                HStack(spacing: 22) {
                    StickView(x: model.state.leftX, y: model.state.leftY, label: "Left stick")
                    StickView(x: model.state.rightX, y: model.state.rightY, label: "Right stick")
                }
                TriggerView(label: "LT", value: model.state.leftTrigger)
                TriggerView(label: "RT", value: model.state.rightTrigger)
            }.padding(10)
        }.frame(maxWidth: .infinity)
    }

    private var buttonsCard: some View {
        GroupBox("Buttons") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(buttonItems, id: \.0) { name, button in
                    Text(name).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(model.state.buttons.contains(button) ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundStyle(model.state.buttons.contains(button) ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }.padding(10)
        }.frame(maxWidth: .infinity)
    }

    private var sensorsCard: some View {
        GroupBox("Motion sensors") {
            HStack {
                SensorValue(title: "Gyroscope", vector: model.state.gyro)
                Divider().frame(height: 52)
                SensorValue(title: "Accelerometer", vector: model.state.accelerometer)
            }.padding(10)
        }
    }

    private let buttonItems: [(String, Vader5Buttons)] = [
        ("A", .a), ("B", .b), ("X", .x), ("Y", .y),
        ("LB", .leftBumper), ("RB", .rightBumper), ("L3", .leftStick), ("R3", .rightStick),
        ("M1", .m1), ("M2", .m2), ("M3", .m3), ("M4", .m4),
        ("LM", .leftMacro), ("RM", .rightMacro), ("View", .select), ("Menu", .start),
        ("Home", .home), ("Fn", .function),
    ]
}

private struct StickView: View {
    let x: Int16; let y: Int16; let label: String
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let nx = CGFloat(x) / 32767
                let ny = CGFloat(y) / 32767
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.12))
                    Circle().stroke(Color.secondary.opacity(0.3))
                    Circle().fill(Color.accentColor)
                        .frame(width: 20, height: 20)
                        .offset(x: nx * proxy.size.width * 0.38, y: ny * proxy.size.height * 0.38)
                }
            }.frame(width: 96, height: 96)
            Text(label).font(.caption.bold())
            Text("\(x), \(y)").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

private struct TriggerView: View {
    let label: String; let value: UInt8
    var body: some View {
        HStack {
            Text(label).font(.caption.bold()).frame(width: 24)
            ProgressView(value: Double(value), total: 255)
            Text("\(value)").font(.system(.caption, design: .monospaced)).frame(width: 28, alignment: .trailing)
        }
    }
}

private struct SensorValue: View {
    let title: String; let vector: Vector3
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.bold())
            Text("X \(vector.x)   Y \(vector.y)   Z \(vector.z)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
