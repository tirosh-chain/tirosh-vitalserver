import Contracts
public protocol RuntimeStorageUsageProviding {
    func storageUsage(for path: String) -> ResourceUsage?
}
