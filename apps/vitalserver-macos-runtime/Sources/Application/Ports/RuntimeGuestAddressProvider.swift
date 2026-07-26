import Contracts

public protocol RuntimeGuestAddressProvider: Sendable {
    func readGuestAddress() -> RuntimeGuestAddressReadResult
}
