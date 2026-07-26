import Contracts
import Foundation

public protocol RuntimeStatusArtifactSink {
    func save(_ document: RuntimeStatusDocument) throws
}
