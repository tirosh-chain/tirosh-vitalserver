import Contracts
import Domain
import Foundation

public typealias UpdateBootstrapVerificationInvocationBindingReadResult =
    UpdateBootstrapVerificationInvocationBindingReadInput

public protocol UpdateBootstrapVerificationInvocationBindingReading {
    func read(
        at url: URL
    ) -> UpdateBootstrapVerificationInvocationBindingReadResult
}
