import CryptoKit
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

@Test func parsesBoundedNearLinkContainerLayout() throws {
    var package = Data(repeating: 0, count: 0x100)
    func write(_ bytes: [UInt8], at offset: Int) {
        package.replaceSubrange(offset..<offset + bytes.count, with: bytes)
    }
    func writeUInt32(_ value: UInt32, at offset: Int) {
        write([
            UInt8(value & 0xff), UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff), UInt8(value >> 24),
        ], at: offset)
    }

    write(Vader5FirmwarePackageInspector.nearLinkMagic, at: 0)
    writeUInt32(0x40, at: 8)
    write(Vader5FirmwarePackageInspector.nearLinkMagic, at: 0x40)
    writeUInt32(0x20, at: 0x48)
    writeUInt32(0x90, at: 0x64)
    writeUInt32(0x70, at: 0x68)
    write(Array("QTOF".utf8), at: 0x90)
    writeUInt32(0xc0, at: 0x98)
    writeUInt32(0x40, at: 0x9c)
    write([0x5a, 0x00, 0x10, 0x00], at: 0xc0)
    let payloadDigest = SHA256.hash(data: package[0xc0..<0x100])
    write(Array(payloadDigest), at: 0xa0)

    let info = Vader5FirmwarePackageInspector.inspect(data: package)
    let layout = try #require(info.nearLinkLayout)
    #expect(layout.outerHeaderSize == 0x40)
    #expect(layout.innerHeaderSize == 0x20)
    #expect(layout.descriptorOffset == 0x60)
    #expect(layout.subpackageMagic == "QTOF")
    #expect(layout.payloadOffset == 0xc0)
    #expect(layout.payloadLength == 0x40)
    #expect(layout.payloadHeader == "5A 00 10 00")
    #expect(layout.payloadSHA256Matches)

    writeUInt32(0x80, at: 0x9c)
    #expect(Vader5FirmwarePackageInspector.parseNearLinkLayout(package) == nil)
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

@Test func strictSimulatorTargetsTheRequestedBlock() {
    #expect(throws: Vader5FirmwareTransportError.rejected(block: 3, status: 1)) {
        try Vader5DiagnosticUpdater.run(
            image: Data(repeating: 0xaa, count: 80), scenario: .crcError(block: 3))
    }
}

@Test func strictSimulatorDetectsCorruptedRecords() throws {
    let transport = Vader5DryRunTransport()
    #expect(try transport.exchange(Vader5HIDOTAProtocol.startReport(), block: nil) == .acknowledgement)
    var packet = Vader5HIDOTAProtocol.dataReport(
        image: Data(repeating: 0xaa, count: 16), startingBlock: 0).report
    packet[6] ^= 0xff
    #expect(throws: Vader5FirmwareTransportError.self) {
        try transport.exchange(packet, block: 0)
    }
}

@Test func simulatorRetriesTransientCorruption() throws {
    let result = try Vader5DiagnosticUpdater.run(
        image: Data(repeating: 0xaa, count: 48),
        scenario: .corruptedPacketOnce(block: 0),
        policy: .init(maxPacketRetries: 1))
    #expect(result.blockCount == 3)
    #expect(result.events.contains { $0.message == "RETRY BLOCK 0, ATTEMPT 1" })
    #expect(result.events.last?.message == "SUCCESS")
}

@Test func simulatorRestartsAfterDisconnectAndInterruption() throws {
    for scenario in [
        Vader5SimulationScenario.disconnectOnce(block: 0),
        .interrupted(block: 0),
    ] {
        let result = try Vader5DiagnosticUpdater.run(
            image: Data(repeating: 0xaa, count: 48),
            scenario: scenario,
            policy: .init(maxRecoveryRestarts: 1))
        #expect(result.events.filter { $0.message == "SEND START" }.count == 2)
        #expect(result.events.contains { $0.message == "RECOVERY RESTART FROM BLOCK 0" })
        #expect(result.events.last?.message == "SUCCESS")
    }
}

@Test func simulatorStopsWhenRecoveryIsDisabled() {
    #expect(throws: Vader5FirmwareTransportError.disconnected(0)) {
        try Vader5DiagnosticUpdater.run(
            image: Data(repeating: 0xaa, count: 16), scenario: .disconnectOnce(block: 0))
    }
    #expect(throws: Vader5FirmwareTransportError.interrupted(0)) {
        try Vader5DiagnosticUpdater.run(
            image: Data(repeating: 0xaa, count: 16), scenario: .interrupted(block: 0))
    }
    #expect(throws: Vader5FirmwareTransportError.unexpectedResponse) {
        try Vader5DiagnosticUpdater.run(
            image: Data(repeating: 0xaa, count: 16),
            scenario: .unexpectedAcknowledgement(block: 0))
    }
}

@Test func realHardwareFirmwareWritesAreUnconditionallyRefused() {
    #expect(throws: Vader5FirmwareTransportError.realHardwareWritesDisabled) {
        try Vader5DiagnosticUpdater.refuseRealHardwareUpdate()
    }
}

@Test func validatesFirmwareDownloadResponses() throws {
    let url = URL(string: "https://example.com/firmware.fwpkg")!
    let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
    try Vader5FirmwareDownloadClient.validate(data: Data([1]), response: ok)

    #expect(throws: Vader5FirmwareDownloadError.emptyFile) {
        try Vader5FirmwareDownloadClient.validate(data: Data(), response: ok)
    }
    let missing = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
    #expect(throws: Vader5FirmwareDownloadError.invalidResponse) {
        try Vader5FirmwareDownloadClient.validate(data: Data([1]), response: missing)
    }
}

@Test func upgradesFlydigiCDNDownloadsToHTTPS() throws {
    let returnedURL = URL(string: "http://api-web.cdn.flydigi.com/devicefirmwares/test.fwpkg")!
    let secureURL = try Vader5FirmwareDownloadClient.secureURL(for: returnedURL)
    #expect(secureURL.absoluteString == "https://api-web.cdn.flydigi.com/devicefirmwares/test.fwpkg")

    let unknownHTTP = URL(string: "http://example.com/firmware.fwpkg")!
    #expect(throws: Vader5FirmwareDownloadError.insecureURL) {
        try Vader5FirmwareDownloadClient.secureURL(for: unknownHTTP)
    }
}
