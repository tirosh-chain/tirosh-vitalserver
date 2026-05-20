import Foundation

struct InstallerSettings: Codable {
    var cpuCount = 8
    var memoryGiB = 8
    var diskGiB = 64
    var networkMode = "shared"
    var proxyPort = 80
    var vitalFilesDirectory = "/Library/Application Support/TiroshVitalServer/vm/data/vital-files"
    var adminPassword = "admin"
    var vmHostname = "tirosh-vitalserver"
    var publicHost = ""
    var publicPort = 80
    var startAfterInstall = true
    var startOnBoot = true
}

extension JSONEncoder {
    static var installerPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
