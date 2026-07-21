import Foundation

public enum Vader5Protocol {
    public static let vendorID = 0x37d7
    public static let productID = 0x2401
    public static let usagePage = 0xffa0
    public static let usage = 1

    static let initCommands: [[UInt8]] = [
        [0x5a, 0xa5, 0x01, 0x02, 0x03],
        [0x5a, 0xa5, 0xa1, 0x02, 0xa3],
        [0x5a, 0xa5, 0x02, 0x02, 0x04],
        [0x5a, 0xa5, 0x04, 0x02, 0x06],
        [0x5a, 0xa5, 0x11, 0x07, 0xff, 0x01, 0xff, 0xff, 0xff, 0x15],
    ]

    static let stopCommand: [UInt8] =
        [0x5a, 0xa5, 0x11, 0x07, 0xff, 0x00, 0xff, 0xff, 0xff, 0x14]

    public static func parse(_ data: UnsafeBufferPointer<UInt8>) -> Vader5State? {
        guard data.count >= 29,
              data[0] == 0x5a, data[1] == 0xa5, data[2] == 0xef else { return nil }

        func s16(_ offset: Int) -> Int16 {
            Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
        }
        let b11 = data[11]
        let b12 = data[12]
        let ext = data[13]
        let ext2 = data[14]
        var buttons: Vader5Buttons = []
        func set(_ button: Vader5Buttons, when pressed: Bool) {
            if pressed { buttons.insert(button) }
        }
        set(.a, when: b11 & 0x10 != 0)
        set(.b, when: b11 & 0x20 != 0)
        set(.x, when: b11 & 0x80 != 0)
        set(.y, when: b12 & 0x01 != 0)
        set(.leftBumper, when: b12 & 0x04 != 0)
        set(.rightBumper, when: b12 & 0x08 != 0)
        set(.select, when: b11 & 0x40 != 0)
        set(.start, when: b12 & 0x02 != 0)
        set(.leftStick, when: b12 & 0x40 != 0)
        set(.rightStick, when: b12 & 0x80 != 0)
        set(.m1, when: ext & 0x04 != 0)
        set(.m2, when: ext & 0x08 != 0)
        set(.m3, when: ext & 0x10 != 0)
        set(.m4, when: ext & 0x20 != 0)
        set(.home, when: ext2 & 0x08 != 0)
        set(.function, when: ext2 & 0x01 != 0)
        set(.leftMacro, when: ext & 0x40 != 0)
        set(.rightMacro, when: ext & 0x80 != 0)

        let dpadMap: [UInt8] = [8, 0, 2, 1, 4, 8, 3, 8, 6, 7, 8, 8, 5, 8, 8, 8]
        return Vader5State(
            leftX: s16(3), leftY: Int16(clamping: -Int(s16(5))),
            rightX: s16(7), rightY: Int16(clamping: -Int(s16(9))),
            leftTrigger: data[15], rightTrigger: data[16],
            dpad: dpadMap[Int(b11 & 0x0f)], buttons: buttons,
            extraButtons: ext,
            gyro: .init(x: s16(17), y: s16(19), z: s16(21)),
            accelerometer: .init(x: s16(23), y: s16(25), z: s16(27))
        )
    }

    public static func parse(_ data: [UInt8]) -> Vader5State? {
        data.withUnsafeBufferPointer(parse)
    }

    static func virtualReport(for state: Vader5State) -> [UInt8] {
        func put16(_ value: Int16, into output: inout [UInt8], at offset: Int) {
            let raw = UInt16(bitPattern: value)
            output[offset] = UInt8(raw & 0xff)
            output[offset + 1] = UInt8(raw >> 8)
        }
        var report = [UInt8](repeating: 0, count: 15)
        report[0] = 1
        report[1] = UInt8(state.buttons.rawValue & 0xff)
        report[2] = UInt8((state.buttons.rawValue >> 8) & 0xff)
        report[3] = UInt8((state.buttons.rawValue >> 16) & 0x03)
        report[4] = state.dpad
        put16(state.leftX, into: &report, at: 5)
        put16(state.leftY, into: &report, at: 7)
        put16(state.rightX, into: &report, at: 9)
        put16(state.rightY, into: &report, at: 11)
        report[13] = state.leftTrigger
        report[14] = state.rightTrigger
        return report
    }
}
