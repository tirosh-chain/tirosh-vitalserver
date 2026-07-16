import Contracts
import Foundation

public enum RuntimeControlMultipartFormDataError: LocalizedError, Equatable {
    case contentTypeRequired
    case boundaryRequired
    case malformedBody
    case unexpectedField(String?)
    case filenameRequired
    case filesRequired

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
        }
    }
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
