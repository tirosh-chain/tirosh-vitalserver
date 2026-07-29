import Contracts
import Foundation
import RuntimeControl

protocol RuntimeTimeAuthorityReading: Sendable {
    func loadTimeAuthority() -> RuntimeTimeAuthorityResourceRead
}

struct SystemRuntimeTimeAuthorityReader: RuntimeTimeAuthorityReading {
    let documentURL: URL

    init(
        documentURL: URL = InstalledRuntimePaths.defaultInstalled.timeAuthority
    ) {
        self.documentURL = documentURL
    }

    func loadTimeAuthority() -> RuntimeTimeAuthorityResourceRead {
        do {
            let data = try Data(contentsOf: documentURL)
            let document = try JSONDecoder().decode(
                RuntimeTimeAuthorityDocument.self,
                from: data
            )
            return RuntimeTimeAuthorityResourceRead(
                state: .loaded,
                document: document
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return RuntimeTimeAuthorityResourceRead(state: .missing)
        } catch {
            return RuntimeTimeAuthorityResourceRead(
                state: .failed,
                readError: "Host time authority read failed path=\(documentURL.path) reason=\(error.localizedDescription)"
            )
        }
    }
}
