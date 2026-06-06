import Application
import Bootstrap
import Contracts
import OutboundAdapters
import Foundation
import Errors

extension VMRuntimeConfig {
    static func `default`(paths: InstalledRuntimePaths) -> VMRuntimeConfig {
        VMRuntimeConfigComposition.defaultConfig(paths: paths)
    }

    static func load(from url: URL, fileStore: RuntimeFileReading) throws -> VMRuntimeConfig {
        try VMRuntimeConfigComposition.load(from: url, fileStore: fileStore)
    }

    static func validateBootFiles(_ config: VMRuntimeConfig, fileStore: RuntimeFileReading) throws {
        try VMRuntimeConfigComposition.validateBootFiles(config, fileStore: fileStore)
    }

    static func ensureNetworkIdentity(_ config: inout VMRuntimeConfig) {
        VMRuntimeConfigComposition.ensureNetworkIdentity(&config)
    }

    static func ensureRuntimeDefaults(_ config: inout VMRuntimeConfig, paths: InstalledRuntimePaths) {
        VMRuntimeConfigComposition.ensureRuntimeDefaults(&config, paths: paths)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        VMRuntimeConfigComposition.prettyJSONEncoder()
    }
}
