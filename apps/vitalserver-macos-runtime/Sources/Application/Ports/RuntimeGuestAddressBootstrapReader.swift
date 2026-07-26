import Contracts

public protocol RuntimeGuestAddressBootstrapReading: Sendable {
    func readBootstrapGuestAddress() -> RuntimeGuestAddressReadResult
}
