import Application
import Foundation

public enum JSONLRuntimeHostDiagnosticEventSinkError: Error, Equatable, CustomStringConvertible {
    case unexpectedPathState(path: String, state: String)
    case invalidUTF8(path: String)
    case missingTrailingNewline(path: String)
    case emptyLine(path: String, line: Int)
    case invalidLine(path: String, line: Int, reason: String)
    case duplicateConflict(path: String, sequence: Int, eventID: String)
    case sequenceGap(path: String, expected: Int, actual: Int)
    case operationFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .unexpectedPathState(let path, let state):
            return "Host diagnostic JSONL path state is unexpected path=\(path) state=\(state)"
        case .invalidUTF8(let path):
            return "Host diagnostic JSONL is not UTF-8 path=\(path)"
        case .missingTrailingNewline(let path):
            return "Host diagnostic JSONL is missing its trailing newline path=\(path)"
        case .emptyLine(let path, let line):
            return "Host diagnostic JSONL contains an empty line path=\(path) line=\(line)"
        case .invalidLine(let path, let line, let reason):
            return "Host diagnostic JSONL line is invalid path=\(path) line=\(line) reason=\(reason)"
        case .duplicateConflict(let path, let sequence, let eventID):
            return "Host diagnostic JSONL duplicate conflicts with the outbox event path=\(path) sequence=\(sequence) eventId=\(eventID)"
        case .sequenceGap(let path, let expected, let actual):
            return "Host diagnostic JSONL sequence is not contiguous path=\(path) expected=\(expected) actual=\(actual)"
        case .operationFailed(let path, let reason):
            return "Host diagnostic JSONL operation failed path=\(path) reason=\(reason)"
        }
    }
}

public struct JSONLRuntimeHostDiagnosticEventSink:
    RuntimeHostDiagnosticEventAppending,
    @unchecked Sendable
{
    public let url: URL
    private let fileStore: any RuntimeFileStore
    private let fileLock: any RuntimeFileLocking
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        url: URL,
        fileStore: any RuntimeFileStore = SystemRuntimeFileStore(),
        fileLock: any RuntimeFileLocking = POSIXRuntimeFileLock()
    ) {
        self.url = url
        self.fileStore = fileStore
        self.fileLock = fileLock
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func appendDiagnosticEvent(_ event: RuntimeHostDiagnosticOutboxEvent) throws {
        do {
            try fileStore.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileLock.withExclusiveLock(for: url) {
                let existing = try loadExistingEvents()
                if let duplicate = existing.first(where: {
                    $0.sequence == event.sequence || $0.eventID == event.eventID
                }) {
                    guard duplicate == event else {
                        throw JSONLRuntimeHostDiagnosticEventSinkError.duplicateConflict(
                            path: url.path,
                            sequence: event.sequence,
                            eventID: event.eventID
                        )
                    }
                    return
                }

                let expected = (existing.last?.sequence ?? 0) + 1
                guard event.sequence == expected else {
                    throw JSONLRuntimeHostDiagnosticEventSinkError.sequenceGap(
                        path: url.path,
                        expected: expected,
                        actual: event.sequence
                    )
                }
                let existingData = try dataForExistingFile()
                let nextData = existingData + (try encoder.encode(event)) + Data("\n".utf8)
                try fileStore.writeData(
                    nextData,
                    to: url,
                    options: .atomic,
                    posixPermissions: 0o600
                )
                guard try fileStore.readData(url) == nextData else {
                    throw JSONLRuntimeHostDiagnosticEventSinkError.operationFailed(
                        path: url.path,
                        reason: "write verification mismatch"
                    )
                }
            }
        } catch let error as JSONLRuntimeHostDiagnosticEventSinkError {
            throw error
        } catch {
            throw JSONLRuntimeHostDiagnosticEventSinkError.operationFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }

    private func loadExistingEvents() throws -> [RuntimeHostDiagnosticOutboxEvent] {
        let data = try dataForExistingFile()
        guard !data.isEmpty else { return [] }
        guard data.last == 0x0A else {
            throw JSONLRuntimeHostDiagnosticEventSinkError.missingTrailingNewline(path: url.path)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw JSONLRuntimeHostDiagnosticEventSinkError.invalidUTF8(path: url.path)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var events: [RuntimeHostDiagnosticOutboxEvent] = []
        for (offset, line) in lines.dropLast().enumerated() {
            guard !line.isEmpty else {
                throw JSONLRuntimeHostDiagnosticEventSinkError.emptyLine(
                    path: url.path,
                    line: offset + 1
                )
            }
            do {
                let event = try decoder.decode(
                    RuntimeHostDiagnosticOutboxEvent.self,
                    from: Data(line.utf8)
                )
                let expected = events.count + 1
                guard event.sequence == expected else {
                    throw JSONLRuntimeHostDiagnosticEventSinkError.sequenceGap(
                        path: url.path,
                        expected: expected,
                        actual: event.sequence
                    )
                }
                guard !events.contains(where: { $0.eventID == event.eventID }) else {
                    throw JSONLRuntimeHostDiagnosticEventSinkError.duplicateConflict(
                        path: url.path,
                        sequence: event.sequence,
                        eventID: event.eventID
                    )
                }
                events.append(event)
            } catch let error as JSONLRuntimeHostDiagnosticEventSinkError {
                throw error
            } catch {
                throw JSONLRuntimeHostDiagnosticEventSinkError.invalidLine(
                    path: url.path,
                    line: offset + 1,
                    reason: String(describing: error)
                )
            }
        }
        return events
    }

    private func dataForExistingFile() throws -> Data {
        switch fileStore.pathState(at: url) {
        case .missing:
            return Data()
        case .file:
            return try fileStore.readData(url)
        case .inspectFailed(let reason):
            throw JSONLRuntimeHostDiagnosticEventSinkError.operationFailed(
                path: url.path,
                reason: "path inspection failed: \(reason)"
            )
        case .directory, .other, .unknown:
            throw JSONLRuntimeHostDiagnosticEventSinkError.unexpectedPathState(
                path: url.path,
                state: fileStore.pathState(at: url).rawValue
            )
        }
    }
}
