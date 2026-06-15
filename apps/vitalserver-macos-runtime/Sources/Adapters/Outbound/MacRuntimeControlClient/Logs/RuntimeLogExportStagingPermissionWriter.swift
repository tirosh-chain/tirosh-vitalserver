import Foundation
import Errors

struct RuntimeLogExportStagingPermissionWriter {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func makeBundleWritable(_ bundleRoot: URL) throws {
        try makeItemWritable(bundleRoot, isDirectory: true)
        var enumerationFailure: (url: URL, error: Error)?
        guard let enumerator = fileManager.enumerator(
            at: bundleRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: { url, error in
                enumerationFailure = (url, error)
                return false
            }
        ) else {
            throw RuntimeLogExporterError.pathInspectionFailed(
                path: bundleRoot.path,
                reason: "directory enumeration unavailable"
            )
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            try makeItemWritable(url, isDirectory: values.isDirectory == true)
        }

        if let enumerationFailure {
            throw RuntimeLogExporterError.pathInspectionFailed(
                path: enumerationFailure.url.path,
                reason: enumerationFailure.error.localizedDescription
            )
        }
    }

    private func makeItemWritable(_ url: URL, isDirectory: Bool) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value else {
            throw RuntimeLogExporterError.missingPOSIXPermissions(path: url.path)
        }
        let writablePermissions = Int(permissions | (isDirectory ? 0o700 : 0o600))
        try fileManager.setAttributes([.posixPermissions: writablePermissions], ofItemAtPath: url.path)
    }
}
