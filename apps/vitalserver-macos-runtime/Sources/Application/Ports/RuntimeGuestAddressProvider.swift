import Contracts

public protocol RuntimeGuestAddressProvider {
    func readGuestAddress() -> RuntimeGuestAddressReadResult
}
