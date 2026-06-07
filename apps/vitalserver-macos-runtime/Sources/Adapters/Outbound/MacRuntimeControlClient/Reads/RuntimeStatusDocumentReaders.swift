import Application
import Contracts
import Errors
import Foundation
import RuntimeControl

struct RuntimeStatusDocumentReader {
    let url: URL
    let fileStore: RuntimeFileReading & RuntimeFileWriting

    func load() -> RuntimeStatusDocumentRead {
        switch JSONFileRuntimeStatusRepository(url: url, fileStore: fileStore).loadResult() {
        case .loaded(let document):
            RuntimeStatusDocumentRead(document: document, error: nil, issue: nil)
        case .missing:
            RuntimeStatusDocumentRead(
                document: nil,
                error: nil,
                issue: RuntimeStatusReadIssue(
                    source: "runtimeStatus",
                    message: "runtime status document is missing"
                )
            )
        case .failed(let message):
            RuntimeStatusDocumentRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "runtimeStatus", message: message)
            )
        }
    }
}

struct GuestRuntimeStateDocumentReader {
    let path: String
    let fileStore: RuntimeFileStore

    func load() -> GuestRuntimeStateRead {
        let url = URL(fileURLWithPath: path)
        let pathState = fileStore.pathState(at: url)
        switch pathState {
        case .file:
            break
        case .missing:
            return GuestRuntimeStateRead(
                document: nil,
                error: nil,
                issue: RuntimeStatusReadIssue(
                    source: "guestRuntimeState",
                    message: "guest runtime state document is missing"
                )
            )
        case .inspectFailed(let reason):
            let message = "guest runtime state path inspection failed path=\(url.path) reason=\(reason)"
            return GuestRuntimeStateRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "guestRuntimeState", message: message)
            )
        case .directory, .other, .unknown:
            let message = "guest runtime state path state is unexpected path=\(url.path) state=\(pathState.rawValue)"
            return GuestRuntimeStateRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "guestRuntimeState", message: message)
            )
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
            return GuestRuntimeStateRead(document: document, error: nil, issue: nil)
        } catch {
            return GuestRuntimeStateRead(
                document: nil,
                error: error.localizedDescription,
                issue: RuntimeStatusReadIssue(source: "guestRuntimeState", message: error.localizedDescription)
            )
        }
    }
}
