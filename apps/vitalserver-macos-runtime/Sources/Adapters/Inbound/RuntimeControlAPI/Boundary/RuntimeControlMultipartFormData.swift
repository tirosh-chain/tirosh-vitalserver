import Contracts
import Foundation

public enum RuntimeControlMultipartFormDataError: LocalizedError, Equatable {
    case contentTypeRequired
    case boundaryRequired
    case malformedBody
    case unexpectedField(String?)
    case filenameRequired
    case filesRequired
    case tooManyFiles(Int)
    case truncatedBody

    public var errorDescription: String? {
        switch self {
        case .contentTypeRequired:
            return "Vital Files upload requires multipart/form-data."
        case .boundaryRequired:
            return "Vital Files upload multipart boundary is missing."
        case .malformedBody:
            return "Vital Files upload multipart body is invalid."
        case .unexpectedField(let field):
            return "Vital Files upload only accepts multipart field 'files'; received \(field ?? "<missing>")."
        case .filenameRequired:
            return "Every Vital Files upload part requires a filename."
        case .filesRequired:
            return "Select at least one .vital file."
        case .tooManyFiles(let maximum):
            return "Vital Files upload contains too many files; maximum is \(maximum)."
        case .truncatedBody:
            return "Vital Files upload ended before the closing boundary."
        }
    }
}

public struct RuntimeControlMultipartStagingError: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct RuntimeLabVitalFileLibraryTransactionError: LocalizedError {
    public let operationError: String
    public let recoveryErrors: [String]

    public init(operationError: String, recoveryErrors: [String]) {
        self.operationError = operationError
        self.recoveryErrors = recoveryErrors
    }

    public var errorDescription: String? {
        guard !recoveryErrors.isEmpty else {
            return "Vital Files upload failed: \(operationError)"
        }
        return "Vital Files upload failed: \(operationError); recovery failures: \(recoveryErrors.joined(separator: "; "))"
    }
}

extension RuntimeControlHTTPRequest {
    func decodedVitalFileUploads() throws -> [RuntimeLabVitalFileUploadSource] {
        guard let contentType = headerValue(named: "Content-Type"),
              contentType.lowercased().hasPrefix("multipart/form-data;") else {
            throw RuntimeControlMultipartFormDataError.contentTypeRequired
        }
        guard let boundary = multipartBoundary(contentType), !boundary.isEmpty else {
            throw RuntimeControlMultipartFormDataError.boundaryRequired
        }
        if let stagedBody {
            return try RuntimeControlStagedMultipartDecoder.decode(
                stagedBody,
                boundary: boundary
            )
        }
        guard let body else {
            throw RuntimeControlMultipartFormDataError.filesRequired
        }

        let delimiter = Data("--\(boundary)".utf8)
        let segments = body.split(separator: delimiter)
        var files: [RuntimeLabVitalFileUploadSource] = []
        for rawSegment in segments.dropFirst() {
            var segment = rawSegment
            if segment.starts(with: Data("--".utf8)) {
                break
            }
            if segment.starts(with: Data("\r\n".utf8)) {
                segment.removeFirst(2)
            }
            if segment.suffix(2) == Data("\r\n".utf8) {
                segment.removeLast(2)
            }
            let headerSeparator = Data("\r\n\r\n".utf8)
            guard let separatorRange = segment.range(of: headerSeparator),
                  let headerText = String(data: segment[..<separatorRange.lowerBound], encoding: .utf8) else {
                throw RuntimeControlMultipartFormDataError.malformedBody
            }
            let contentStart = separatorRange.upperBound
            let disposition = headerText
                .components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-disposition:") }
            guard let disposition else {
                throw RuntimeControlMultipartFormDataError.malformedBody
            }
            let parameters = multipartDispositionParameters(disposition)
            guard parameters["name"] == "files" else {
                throw RuntimeControlMultipartFormDataError.unexpectedField(parameters["name"])
            }
            guard let fileName = parameters["filename"], !fileName.isEmpty else {
                throw RuntimeControlMultipartFormDataError.filenameRequired
            }
            files.append(RuntimeLabVitalFileUploadSource(
                fileName: fileName,
                content: Data(segment[contentStart...])
            ))
        }
        guard !files.isEmpty else {
            throw RuntimeControlMultipartFormDataError.filesRequired
        }
        return files
    }
}

private enum RuntimeControlStagedMultipartDecoder {
    private static let maximumFiles = 32
    private static let maximumHeaderLineBytes = 8 * 1024
    private static let maximumPartHeaderBytes = 32 * 1024

    static func decode(
        _ stagedBody: RuntimeControlStagedHTTPRequestBody,
        boundary: String
    ) throws -> [RuntimeLabVitalFileUploadSource] {
        do {
            let values = try stagedBody.fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
            ])
            guard values.isRegularFile == true,
                  let actualSize = values.fileSize,
                  Int64(actualSize) == stagedBody.sizeBytes else {
                throw RuntimeControlMultipartFormDataError.truncatedBody
            }
            let input = try FileHandle(forReadingFrom: stagedBody.fileURL)
            defer { try? input.close() }
            let reader = RuntimeControlMultipartFileReader(input: input)
            let delimiter = Data("--\(boundary)".utf8)
            guard try reader.readLine(maxBytes: maximumHeaderLineBytes)
                    == delimiter + Data("\r\n".utf8) else {
                throw RuntimeControlMultipartFormDataError.malformedBody
            }

            var sources: [RuntimeLabVitalFileUploadSource] = []
            while true {
                guard sources.count < maximumFiles else {
                    throw RuntimeControlMultipartFormDataError.tooManyFiles(
                        maximumFiles
                    )
                }
                let headerText = try readPartHeaders(reader)
                let disposition = headerText
                    .components(separatedBy: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-disposition:") }
                guard let disposition else {
                    throw RuntimeControlMultipartFormDataError.malformedBody
                }
                let parameters = multipartDispositionParameters(disposition)
                guard parameters["name"] == "files" else {
                    throw RuntimeControlMultipartFormDataError.unexpectedField(
                        parameters["name"]
                    )
                }
                guard let fileName = parameters["filename"], !fileName.isEmpty else {
                    throw RuntimeControlMultipartFormDataError.filenameRequired
                }
                let partURL = stagedBody.temporaryDirectoryURL
                    .appendingPathComponent(
                        String(format: "part-%04d.vital", sources.count)
                    )
                guard FileManager.default.createFile(
                    atPath: partURL.path,
                    contents: nil
                ) else {
                    throw RuntimeControlMultipartStagingError(
                        "Vital Files upload part staging file could not be created."
                    )
                }
                let output = try FileHandle(forWritingTo: partURL)
                let closed: Bool
                do {
                    closed = try reader.copyPart(
                        to: output,
                        delimiter: delimiter
                    )
                    try output.synchronize()
                    try output.close()
                } catch {
                    try? output.close()
                    throw error
                }
                let partValues = try partURL.resourceValues(forKeys: [.fileSizeKey])
                guard let partSize = partValues.fileSize, partSize >= 0 else {
                    throw RuntimeControlMultipartStagingError(
                        "Vital Files upload part staging size is unavailable."
                    )
                }
                sources.append(RuntimeLabVitalFileUploadSource(
                    fileName: fileName,
                    fileURL: partURL,
                    sizeBytes: Int64(partSize),
                    accessMode: .direct
                ))
                if closed {
                    break
                }
            }
            guard !sources.isEmpty else {
                throw RuntimeControlMultipartFormDataError.filesRequired
            }
            return sources
        } catch let error as RuntimeControlMultipartFormDataError {
            throw error
        } catch let error as RuntimeControlMultipartStagingError {
            throw error
        } catch {
            throw RuntimeControlMultipartStagingError(
                "Vital Files upload staging failed: \(error.localizedDescription)"
            )
        }
    }

    private static func readPartHeaders(
        _ reader: RuntimeControlMultipartFileReader
    ) throws -> String {
        var data = Data()
        while true {
            guard let line = try reader.readLine(maxBytes: maximumHeaderLineBytes) else {
                throw RuntimeControlMultipartFormDataError.truncatedBody
            }
            if line == Data("\r\n".utf8) {
                break
            }
            data.append(line)
            guard data.count <= maximumPartHeaderBytes else {
                throw RuntimeControlMultipartFormDataError.malformedBody
            }
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw RuntimeControlMultipartFormDataError.malformedBody
        }
        return text
    }
}

private final class RuntimeControlMultipartFileReader {
    private static let readChunkBytes = 64 * 1024

    private let input: FileHandle
    private var buffer = Data()
    private var reachedEnd = false

    init(input: FileHandle) {
        self.input = input
    }

    func readLine(maxBytes: Int) throws -> Data? {
        let lineEnding = Data("\r\n".utf8)
        while true {
            if let range = buffer.range(of: lineEnding) {
                let length = buffer.distance(
                    from: buffer.startIndex,
                    to: range.upperBound
                )
                guard length <= maxBytes else {
                    throw RuntimeControlMultipartFormDataError.malformedBody
                }
                let line = Data(buffer.prefix(length))
                buffer.removeFirst(length)
                return line
            }
            guard buffer.count < maxBytes else {
                throw RuntimeControlMultipartFormDataError.malformedBody
            }
            if reachedEnd {
                if buffer.isEmpty {
                    return nil
                }
                throw RuntimeControlMultipartFormDataError.truncatedBody
            }
            try fill()
        }
    }

    func copyPart(to output: FileHandle, delimiter: Data) throws -> Bool {
        let marker = Data("\r\n".utf8) + delimiter
        while true {
            if let range = buffer.range(of: marker) {
                let prefixLength = buffer.distance(
                    from: buffer.startIndex,
                    to: range.lowerBound
                )
                if prefixLength > 0 {
                    try output.write(contentsOf: buffer.prefix(prefixLength))
                }
                buffer.removeFirst(prefixLength + marker.count)
                try ensureBuffered(2)
                if buffer.starts(with: Data("--".utf8)) {
                    buffer.removeFirst(2)
                    if buffer.starts(with: Data("\r\n".utf8)) {
                        buffer.removeFirst(2)
                    }
                    try requireNoEpilogue()
                    return true
                }
                if buffer.starts(with: Data("\r\n".utf8)) {
                    buffer.removeFirst(2)
                    return false
                }
                try output.write(contentsOf: marker)
                continue
            }
            if reachedEnd {
                throw RuntimeControlMultipartFormDataError.truncatedBody
            }
            let retainedBytes = max(0, marker.count - 1)
            if buffer.count > retainedBytes {
                let writable = buffer.count - retainedBytes
                try output.write(contentsOf: buffer.prefix(writable))
                buffer.removeFirst(writable)
            }
            try fill()
        }
    }

    private func ensureBuffered(_ count: Int) throws {
        while buffer.count < count, !reachedEnd {
            try fill()
        }
        guard buffer.count >= count else {
            throw RuntimeControlMultipartFormDataError.truncatedBody
        }
    }

    private func requireNoEpilogue() throws {
        while !reachedEnd {
            try fill()
            if buffer.count > 2 {
                throw RuntimeControlMultipartFormDataError.malformedBody
            }
        }
        guard buffer.isEmpty || buffer == Data("\r\n".utf8) else {
            throw RuntimeControlMultipartFormDataError.malformedBody
        }
        buffer.removeAll()
    }

    private func fill() throws {
        guard !reachedEnd else { return }
        let chunk = try input.read(upToCount: Self.readChunkBytes) ?? Data()
        if chunk.isEmpty {
            reachedEnd = true
        } else {
            buffer.append(chunk)
        }
    }
}

private func multipartBoundary(_ contentType: String) -> String? {
    for parameter in contentType.split(separator: ";").dropFirst() {
        let pair = parameter.split(separator: "=", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard pair.count == 2, pair[0].lowercased() == "boundary" else {
            continue
        }
        return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    return nil
}

private func multipartDispositionParameters(_ header: String) -> [String: String] {
    var parameters: [String: String] = [:]
    for parameter in header.split(separator: ";").dropFirst() {
        let pair = parameter.split(separator: "=", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard pair.count == 2 else { continue }
        parameters[pair[0].lowercased()] = pair[1]
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
    return parameters
}

private extension Data {
    func split(separator: Data) -> [Data] {
        guard !separator.isEmpty else { return [self] }
        var result: [Data] = []
        var start = startIndex
        while let range = self[start...].range(of: separator) {
            result.append(Data(self[start..<range.lowerBound]))
            start = range.upperBound
        }
        result.append(Data(self[start..<endIndex]))
        return result
    }
}
