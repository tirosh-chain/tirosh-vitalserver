import Contracts

public protocol RuntimeProgressArtifactSink {
    func save(_ document: RuntimeProgressDocument) throws
}
