import Foundation

struct RuntimeArtifactPayloadInstaller {
    var tarCommand: String
    var fileSize: (URL) throws -> UInt64
    var createDirectory: (URL, Bool) throws -> Void
    var moveItem: (URL, URL) throws -> Void
    var runRequired: (String, [String]) throws -> Void
    var pathRemover: RuntimeArtifactReplacementPathRemover
    var log: (String) -> Void

    func replaceTarGz(_ source: URL, destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).update")
        log(
            "archive replacement started source=\(source.path) destination=\(destination.path) temporary=\(temporary.path) size=\(RuntimeArtifactByteFormatter.formatBytes(try fileSize(source)))"
        )
        try pathRemover.removePathIfPresent(temporary)
        try createDirectory(temporary, true)
        try runRequired(tarCommand, ["-xzf", source.path, "-C", temporary.path, "--strip-components", "1"])
        try pathRemover.removePathIfPresent(destination)
        try moveItem(temporary, destination)
        log("archive replacement completed destination=\(destination.path)")
    }

    func extractTarGz(_ source: URL, destination: URL) throws {
        log(
            "archive extraction started source=\(source.path) destination=\(destination.path) size=\(RuntimeArtifactByteFormatter.formatBytes(try fileSize(source)))"
        )
        try createDirectory(destination, true)
        try runRequired(tarCommand, ["-xzf", source.path, "-C", destination.path])
        log("archive extraction completed destination=\(destination.path)")
    }
}

enum RuntimeArtifactByteFormatter {
    static func formatBytes(_ bytes: UInt64) -> String {
        let mib = Double(bytes) / 1_048_576
        return String(format: "%.1f MiB", max(mib, 0))
    }
}
