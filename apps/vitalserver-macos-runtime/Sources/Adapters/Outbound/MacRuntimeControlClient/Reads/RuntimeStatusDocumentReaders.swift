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

struct RuntimeInstallStateDocumentReader {
    let path: String
    let fileStore: RuntimeFileStore

    func load() -> RuntimeInstallStateRead {
        let url = URL(fileURLWithPath: path)
        switch fileStore.pathState(at: url) {
        case .file:
            break
        case .missing:
            return RuntimeInstallStateRead(document: nil, error: nil, issue: nil)
        case .inspectFailed(let reason):
            let message = "runtime install state path inspection failed path=\(url.path) reason=\(reason)"
            return RuntimeInstallStateRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "runtimeInstallState", message: message)
            )
        case .directory, .other, .unknown:
            let message = "runtime install state path state is unexpected path=\(url.path) state=\(fileStore.pathState(at: url).rawValue)"
            return RuntimeInstallStateRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "runtimeInstallState", message: message)
            )
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(RuntimeInstallStateDocument.self, from: data)
            return RuntimeInstallStateRead(document: document, error: nil, issue: nil)
        } catch {
            return RuntimeInstallStateRead(
                document: nil,
                error: error.localizedDescription,
                issue: RuntimeStatusReadIssue(source: "runtimeInstallState", message: error.localizedDescription)
            )
        }
    }
}

struct RuntimeRedisRelayStatusReader {
    let path: String
    let fileStore: RuntimeFileStore

    func load() -> RuntimeRedisRelayStatusRead {
        let url = URL(fileURLWithPath: path)
        let pathState = fileStore.pathState(at: url)
        switch pathState {
        case .file:
            break
        case .missing:
            return RuntimeRedisRelayStatusRead(document: nil, error: nil, issue: nil)
        case .inspectFailed(let reason):
            let message = "redis relay status path inspection failed path=\(url.path) reason=\(reason)"
            return RuntimeRedisRelayStatusRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "redisRelayStatus", message: message)
            )
        case .directory, .other, .unknown:
            let message = "redis relay status path state is unexpected path=\(url.path) state=\(pathState.rawValue)"
            return RuntimeRedisRelayStatusRead(
                document: nil,
                error: message,
                issue: RuntimeStatusReadIssue(source: "redisRelayStatus", message: message)
            )
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(RuntimeRedisRelayStatus.self, from: data)
            return RuntimeRedisRelayStatusRead(document: document, error: nil, issue: nil)
        } catch {
            return RuntimeRedisRelayStatusRead(
                document: nil,
                error: error.localizedDescription,
                issue: RuntimeStatusReadIssue(source: "redisRelayStatus", message: error.localizedDescription)
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
