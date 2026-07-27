import Foundation
import Vader5Core

enum DockFactoryLightingStore {
    static func configuration(
        deviceType: UInt8
    ) throws -> FlydigiDockLightingConfiguration {
        guard deviceType <= 4 else {
            throw FlydigiDockFactoryLightingError.missingLightingConfiguration
        }
        let name = "default_mapping_\(deviceType)"
        let packaged = Bundle.main.url(
            forResource: name,
            withExtension: "dat",
            subdirectory: "FlydigiDockDefaults")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/FlydigiDockDefaults")
            .appendingPathComponent("\(name).dat")
        return try FlydigiDockFactoryLighting.decode(
            Data(contentsOf: packaged ?? source))
    }
}
