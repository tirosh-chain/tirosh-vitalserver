import Contracts
import Foundation

public struct UpdateBootstrapCanonicalPayloadEncoder {
    public init() {}

    public func encode(_ envelope: UpdateBootstrapEnvelope) throws -> Data {
        let fields = [
            field("schemaVersion", try string(envelope.schemaVersion)),
            field("id", try string(envelope.id)),
            field("productId", try string(envelope.productId)),
            field("target", try target(envelope.target)),
            field("targetRelease", try release(envelope.targetRelease)),
            field(
                "layerOrder",
                array(try envelope.layerOrder.map { try string($0.rawValue) })
            ),
            field(
                "nextUpdaterArtifact",
                try artifact(envelope.nextUpdaterArtifact)
            ),
            field("specification", try artifact(envelope.specification)),
            field(
                "payloadArtifacts",
                array(try envelope.payloadArtifacts.map { try artifact($0) })
            ),
            field("issuedAt", try string(envelope.issuedAt)),
        ]
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    private func target(_ target: UpdateBootstrapTarget) throws -> String {
        object([
            field("platform", try string(target.platform.rawValue)),
            field("architecture", try string(target.architecture.rawValue)),
        ])
    }

    private func release(_ release: UpdateBootstrapRelease) throws -> String {
        object([
            field("productVersion", try string(release.productVersion)),
            field("runtimeVersion", try string(release.runtimeVersion)),
        ])
    }

    private func artifact(_ artifact: UpdateBootstrapArtifact) throws -> String {
        object([
            field("id", try string(artifact.id)),
            field("relativePath", try string(artifact.relativePath)),
            field("sha256", try string(artifact.sha256)),
            field("sizeBytes", String(artifact.sizeBytes)),
            field("mediaType", try string(artifact.mediaType)),
        ])
    }

    private func field(_ name: String, _ value: String) -> String {
        "\"\(name)\":\(value)"
    }

    private func object(_ fields: [String]) -> String {
        "{\(fields.joined(separator: ","))}"
    }

    private func array(_ values: [String]) -> String {
        "[\(values.joined(separator: ","))]"
    }

    private func string(_ value: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
