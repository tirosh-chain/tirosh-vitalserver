import Application
import Contracts
import Foundation
import RuntimeControl

struct RuntimeVitalDBCurrentObservationProvider {
    private let loadCurrentObservation: () -> RuntimeVitalDBCurrentObservationRead

    init(load: @escaping () -> RuntimeVitalDBCurrentObservationRead) {
        self.loadCurrentObservation = load
    }

    func load() -> RuntimeVitalDBCurrentObservationRead {
        loadCurrentObservation()
    }

    static func live(
        paths: RuntimePaths,
        fileStore: RuntimeFileReading & RuntimeFileWriting = SystemRuntimeFileStore()
    ) -> RuntimeVitalDBCurrentObservationProvider {
        let runtimeStatePath = paths.runtimeState
        let runtimeStatusPath = paths.runtimeStatus
        return RuntimeVitalDBCurrentObservationProvider {
            let guestStateReader = GuestRuntimeStateVitalDBObservationReader(
                path: runtimeStatePath,
                fileStore: fileStore
            )
            let statusReader = RuntimeStatusVitalDBObservationReader(
                url: URL(fileURLWithPath: runtimeStatusPath),
                fileStore: fileStore
            )
            var readIssues: [String] = []
            switch guestStateReader.load() {
            case .loaded(let observation):
                if let observation {
                    return .loaded(observation, source: .guestRuntimeState)
                }
            case .missing:
                readIssues.append("runtimeState=missing")
            case .failed(let message):
                readIssues.append("runtimeState=\(message)")
            }

            switch statusReader.load() {
            case .loaded(let observation):
                if let observation {
                    return .loaded(observation, source: .runtimeStatus, readIssues: readIssues)
                }
            case .missing:
                readIssues.append("runtimeStatus=missing")
            case .failed(let message):
                readIssues.append("runtimeStatus=\(message)")
            }
            return .unavailable(readIssues: readIssues)
        }
    }
}

private enum RuntimeVitalDBObservationDocumentRead {
    case missing
    case loaded(VitalDBObservationDocument?)
    case failed(String)
}

private struct GuestRuntimeStateVitalDBObservationReader {
    let path: String
    let fileStore: RuntimeFileReading

    func load() -> RuntimeVitalDBObservationDocumentRead {
        let url = URL(fileURLWithPath: path)
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("runtime state path inspection failed path=\(path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("runtime state path state is unexpected path=\(path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            let document = try JSONDecoder().decode(GuestRuntimeStateDocument.self, from: data)
            return .loaded(document.vitalDBObservation)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

private struct RuntimeStatusVitalDBObservationReader {
    let url: URL
    let fileStore: RuntimeFileReading & RuntimeFileWriting

    func load() -> RuntimeVitalDBObservationDocumentRead {
        switch JSONFileRuntimeStatusRepository(url: url, fileStore: fileStore).loadResult() {
        case .loaded(let document):
            return .loaded(document.vitalDBObservation)
        case .missing:
            return .missing
        case .failed(let message):
            return .failed(message)
        }
    }
}
