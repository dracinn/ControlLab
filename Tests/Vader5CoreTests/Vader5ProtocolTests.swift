import Testing
@testable import Vader5Core

@Test func parsesEnhancedReport() {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...2] = [0x5a, 0xa5, 0xef]
    report[3] = 0x34; report[4] = 0x12
    report[5] = 0x00; report[6] = 0x80
    report[11] = 0x11 // A + dpad up
    report[12] = 0x0c // LB + RB
    report[13] = 0xd4 // M1 + M3 + LM + RM
    report[14] = 0x08 // Home
    report[15] = 127; report[16] = 255

    let state = Vader5Protocol.parse(report)
    #expect(state != nil)
    #expect(state?.leftX == 0x1234)
    #expect(state?.leftY == 32767)
    #expect(state?.dpad == 0)
    #expect(state?.buttons.contains(.a) == true)
    #expect(state?.buttons.contains(.m1) == true)
    #expect(state?.buttons.contains(.m3) == true)
    #expect(state?.buttons.contains(.leftMacro) == true)
    #expect(state?.buttons.contains(.rightMacro) == true)
    #expect(state?.buttons.contains(.home) == true)
    #expect(state?.leftTrigger == 127)
    #expect(state?.rightTrigger == 255)
}

@Test func virtualReportIncludesLMAndRM() {
    let state = Vader5State(
        leftX: 1, leftY: 2, rightX: 3, rightY: 4,
        leftTrigger: 5, rightTrigger: 6, dpad: 8,
        buttons: [.leftMacro, .rightMacro], extraButtons: 0xc0,
        gyro: .init(x: 0, y: 0, z: 0),
        accelerometer: .init(x: 0, y: 0, z: 0)
    )
    let report = Vader5Protocol.virtualReport(for: state)
    #expect(report.count == 15)
    #expect(report[3] & 0x03 == 0x03)
    #expect(report[4] == 8)
    #expect(report[13] == 5)
    #expect(report[14] == 6)
}

@Test func rejectsUnrecognizedReport() {
    #expect(Vader5Protocol.parse([UInt8](repeating: 0, count: 32)) == nil)
}
