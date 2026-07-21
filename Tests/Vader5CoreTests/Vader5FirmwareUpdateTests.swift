import Foundation
import Testing
@testable import Vader5Core

@Test func decodesFlydigiFirmwareCatalog() throws {
    let json = Data(#"""
    {"code":0,"message":"OK","data":{"device_code":"k5","chip_list":{
      "main_chip":null,
      "dongle_chip":{"version":"2.1.3.0","url":"https://example.com/dongle.fwpkg","info":"Fixes","min_app_version":"4.1.0.20","is_push":0},
      "rf_chip":{"version":"1.1.3.0","url":"https://example.com/rf.fwpkg","info":"Fixes","min_app_version":"4.1.0.20","is_push":0},
      "si_chip":null
    }}}
    """#.utf8)

    let catalog = try Vader5FirmwareUpdateClient.decodeResponse(json)
    #expect(catalog.main == nil)
    #expect(catalog.si == nil)
    #expect(catalog.dongle?.version == "2.1.3.0")
    #expect(catalog.rf?.version == "1.1.3.0")
}

@Test func buildsRecoveredHIDOTAReports() {
    #expect(Vader5HIDOTAProtocol.startReport().prefix(6) == [0x05, 0x02, 0x02, 0x00, 0x01, 0xff])

    let image = Data(0..<32)
    let packet = Vader5HIDOTAProtocol.dataReport(image: image, startingBlock: 0)
    #expect(packet.report.count == 64)
    #expect(packet.report[0...3] == [0x05, 0x02, 0x28, 0x00])
    #expect(packet.nextBlock == 2)
    #expect(packet.report[4...5] == [0x00, 0x00])
    #expect(Array(packet.report[6...21]) == (0..<16).map(UInt8.init))

    let finish = Vader5HIDOTAProtocol.finishReport(lastBlock: 1)
    #expect(finish.prefix(10) == [0x05, 0x02, 0x06, 0x00, 0x02, 0xff, 0x01, 0x00, 0xff, 0xff])
}

@Test func recoveredCRCMatchesModbusVector() {
    #expect(Vader5HIDOTAProtocol.crc16(Array("123456789".utf8)) == 0x4b37)
}

@Test func parsesRecoveredHIDOTAResponses() {
    #expect(Vader5HIDOTAProtocol.parseResponse([0x05, 0x02, 0x03, 0x00, 0x06, 0xff, 0]) == .completed)
    #expect(Vader5HIDOTAProtocol.parseResponse([0x05, 0x02, 0x03, 0x00, 0x06, 0xff, 4]) == .failed(4))
    #expect(Vader5HIDOTAProtocol.parseResponse([
        0x05, 0x01, 0x08, 0x00,
        0x04, 0x03, 0x02, 0x01,
        0x08, 0x07, 0x06, 0x05,
    ]) == .firmwareInfo(version: 0x01020304, crc: 0x05060708))
}

@Test func inspectsNearLinkPackageWithoutModifyingIt() {
    let package = Data(Vader5FirmwarePackageInspector.nearLinkMagic + [1, 2, 3, 4])
    let info = Vader5FirmwarePackageInspector.inspect(data: package, fileName: "test.fwpkg")
    #expect(info.fileName == "test.fwpkg")
    #expect(info.size == 8)
    #expect(info.magic == "4E 15 8D CB")
    #expect(info.isKnownContainer)
    #expect(info.sha256.count == 64)
}

@Test func dryRunBuildsReportsAndCompletesInMemory() throws {
    let result = try Vader5DiagnosticUpdater.run(image: Data(0..<80))
    #expect(result.blockCount == 5)
    #expect(result.events.first?.message == "SEND START")
    #expect(result.events.contains { $0.message == "SEND BLOCK 0" })
    #expect(result.events.contains { $0.message == "SEND BLOCK 3" })
    #expect(result.events.suffix(2).map(\.message) == ["SEND FINISH", "SUCCESS"])
    #expect(result.events.filter { $0.direction == .transmit }.allSatisfy { $0.bytes.count == 64 })
}

@Test func simulatorProvidesDeterministicFailureModes() {
    for (scenario, expectedStatus) in [
        (Vader5SimulationScenario.crcError(block: 0), UInt8(1)),
        (.invalidBlock(block: 0), 2),
        (.flashFull(block: 0), 3),
    ] {
        #expect(throws: Vader5FirmwareTransportError.rejected(block: 0, status: expectedStatus)) {
            try Vader5DiagnosticUpdater.run(image: Data(repeating: 0xaa, count: 32), scenario: scenario)
        }
    }
    #expect(throws: Vader5FirmwareTransportError.timeout(0)) {
        try Vader5DiagnosticUpdater.run(
            image: Data(repeating: 0xaa, count: 32), scenario: .timeout(block: 0))
    }
}

@Test func realHardwareFirmwareWritesAreUnconditionallyRefused() {
    #expect(throws: Vader5FirmwareTransportError.realHardwareWritesDisabled) {
        try Vader5DiagnosticUpdater.refuseRealHardwareUpdate()
    }
}
