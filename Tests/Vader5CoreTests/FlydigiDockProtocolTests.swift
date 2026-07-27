import Testing
@testable import Vader5Core

@Test func buildsDockInitializationAndTenDataReports() {
    let reports = FlydigiDockProtocol.solidColorReports(
        color: .init(red: 0x11, green: 0x22, blue: 0x33))

    #expect(reports.count == 11)
    #expect(reports.allSatisfy { $0.count == 64 })
    #expect(Array(reports[0][0..<10]) == [
        0x5a, 0xa5, 0x61, 0x07, 0x0a, 0x00, 0x00, 0x00, 0x0a, 0x7c,
    ])
    #expect(Array(reports[1][0..<9]) == [
        0x5a, 0xa5, 0x62, 0x39, 0x00, 0x0a, 0x00, 0x00, 50,
    ])
    #expect(Array(reports[1][9..<15]) == [
        0x01, 0x01, 0x64, 0x03, 0x00, 0x00,
    ])
    #expect(Array(reports[1][15..<21]) == [
        0x11, 0x22, 0x33, 0x11, 0x22, 0x33,
    ])
    #expect(reports[10][3] == 0x31)
    #expect(reports[10][7] == 9)
    #expect(reports[10][8] == 42)
}

@Test func buildsDockChecksumsFromCommandThroughPayload() {
    let reports = FlydigiDockProtocol.solidColorReports(
        color: .init(red: 1, green: 2, blue: 3))

    for report in reports.dropFirst() {
        let checksumOffset = 9 + Int(report[8])
        let expected = report[2..<checksumOffset].reduce(UInt8(0)) { $0 &+ $1 }
        #expect(report[checksumOffset] == expected)
    }
}

@Test func appliesDockBrightnessToEveryPixelComponent() {
    let reports = FlydigiDockProtocol.solidColorReports(
        color: .init(red: 200, green: 100, blue: 50),
        brightness: 25)

    #expect(reports[1][11] == 25)
    #expect(Array(reports[1][15..<18]) == [200, 100, 50])
}

@Test func rejectsIncorrectDockPixelCount() {
    #expect(throws: FlydigiDockProtocolError.self) {
        try FlydigiDockProtocol.reports(
            pixels: [.init(red: 0, green: 0, blue: 0)])
    }
}

@Test func buildsSpaceStationGradientConfiguration() throws {
    let reports = try FlydigiDockProtocol.reports(configuration: .init(
        mode: .gradient,
        period: 40,
        brightness: 80,
        colors: [
            .init(red: 255, green: 0, blue: 0),
            .init(red: 0, green: 0, blue: 255),
        ],
        direction: .upRight))

    #expect(reports.count == 2)
    #expect(Array(reports[0][0..<10]) == [
        0x5a, 0xa5, 0x61, 0x07, 0x0a, 0x00, 0x00, 0x00, 0x01, 0x73,
    ])
    #expect(reports[1][3] == 19)
    #expect(Array(reports[1][9..<21]) == [
        0, 40, 80, 6, 6, 2,
        255, 0, 0,
        0, 0, 255,
    ])
}

@Test func buildsMultiFrameDockAnimationWithTruePacketCount() throws {
    let colors: [Vader5RGBColor] = [
        .init(red: 255, green: 0, blue: 0),
        .init(red: 0, green: 0, blue: 255),
    ]
    let pixels = FlydigiDockFrameGenerator.pixels(
        mode: .gradient,
        colors: colors,
        direction: .downRight,
        animationFrameCount: 12)
    let reports = try FlydigiDockProtocol.reports(configuration: .init(
        mode: .gradient,
        period: 40,
        brightness: 80,
        colors: colors,
        direction: .downRight,
        pixels: pixels))

    #expect(pixels.count == 12 * FlydigiDockProtocol.pixelCount)
    #expect(reports.count == 118)
    #expect(reports[0][7] == 0)
    #expect(reports[0][8] == 117)
    #expect(reports[1][4] == 0)
    #expect(reports[1][5] == 117)
    #expect(reports[1][9] == 12)
    #expect(reports[117][4] == 0)
    #expect(reports[117][5] == 117)
    #expect(reports[117][6] == 0)
    #expect(reports[117][7] == 116)
    #expect(reports[117][8] == 44)
}

@Test func generatesDistinctAnimationFramesAndOneStaticFrame() {
    let colors: [Vader5RGBColor] = [
        .init(red: 255, green: 0, blue: 0),
        .init(red: 0, green: 0, blue: 255),
    ]
    let animated = FlydigiDockFrameGenerator.pixels(
        mode: .rainbow,
        colors: colors,
        direction: .right,
        animationFrameCount: 12)
    let firstFrame = Array(animated[0..<FlydigiDockProtocol.pixelCount])
    let secondFrame = Array(
        animated[FlydigiDockProtocol.pixelCount..<(2 * FlydigiDockProtocol.pixelCount)])
    let solid = FlydigiDockFrameGenerator.pixels(
        mode: .solid,
        colors: colors,
        direction: .right)

    #expect(animated.count == 12 * FlydigiDockProtocol.pixelCount)
    #expect(firstFrame != secondFrame)
    #expect(solid.count == FlydigiDockProtocol.pixelCount)
    #expect(solid.allSatisfy { $0 == colors[0] })
}

@Test func rejectsPartialDockAnimationFrame() {
    #expect(throws: FlydigiDockProtocolError.self) {
        try FlydigiDockProtocol.reports(configuration: .init(
            mode: .gradient,
            pixels: Array(
                repeating: .init(red: 0, green: 0, blue: 0),
                count: FlydigiDockProtocol.pixelCount + 1)))
    }
}

@Test func buildsSpaceStationDockSettingCommands() {
    #expect(Array(FlydigiDockProtocol.heartbeatReport()[0..<5]) ==
            [0x5a, 0xa5, 0x01, 0x02, 0x03])
    #expect(Array(FlydigiDockProtocol.readLightingConfigurationReport()[0..<5]) ==
            [0x5a, 0xa5, 0x14, 0x02, 0x16])
    #expect(Array(FlydigiDockProtocol.deviceSettingReport(
        .sleepWhenCharging, enabled: true)[0..<6]) ==
        [0x5a, 0xa5, 0x11, 0x03, 0x01, 0x15])
    #expect(Array(FlydigiDockProtocol.deviceSettingReport(
        .showAnimationWhenCharging, enabled: false)[0..<6]) ==
        [0x5a, 0xa5, 0x19, 0x03, 0x00, 0x1c])
}

@Test func parsesSpaceStationDockSnapshot() {
    var heartbeat = [UInt8](repeating: 0, count: 64)
    heartbeat[0...2] = [0x5a, 0xa5, 0x01]
    heartbeat[18...21] = [1, 0, 1, 1]

    var lighting = [UInt8](repeating: 0, count: 64)
    lighting[0...8] = [0x5a, 0xa5, 0x14, 0, 6, 75, 35, 2, 2]
    lighting[9...14] = [255, 0, 0, 0, 0, 255]

    let snapshot = FlydigiDockProtocol.parseSnapshot([heartbeat, lighting])
    #expect(snapshot.settings == .init(
        sleepWhenCharging: true,
        ledSync: false,
        closeWithSystem: true,
        showAnimationWhenCharging: true))
    #expect(snapshot.lighting?.mode == .gradient)
    #expect(snapshot.lighting?.brightness == 75)
    #expect(snapshot.lighting?.period == 35)
    #expect(snapshot.lighting?.direction == .left)
    #expect(snapshot.lighting?.colors == [
        .init(red: 255, green: 0, blue: 0),
        .init(red: 0, green: 0, blue: 255),
    ])
}
