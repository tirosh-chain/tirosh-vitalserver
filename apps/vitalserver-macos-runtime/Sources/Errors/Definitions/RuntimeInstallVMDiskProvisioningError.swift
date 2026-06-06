import Foundation

public enum RuntimeInstallVMDiskProvisioningError: Error, CustomStringConvertible {
    case missingFile(String)

    public var description: String {
        switch self {
        case .missingFile(let path):
            return "missing file: \(path)"
        }
    }
}
