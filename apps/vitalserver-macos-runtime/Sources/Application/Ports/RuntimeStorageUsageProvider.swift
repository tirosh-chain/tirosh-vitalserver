import Contracts
import Errors

public enum RuntimeStorageUsageResult: Equatable, Sendable {
    case unavailable
    case loaded(ResourceUsage)
    case failed(String)
}

public protocol RuntimeStorageUsageProviding {
    func storageUsage(for path: String) -> RuntimeStorageUsageResult
}
