import Foundation
import Contracts
import Errors

public protocol RuntimeControlStaticFileReading: Sendable {
    func pathState(at url: URL) -> RuntimePathState
    func readData(at url: URL) throws -> Data
}

public struct SystemRuntimeControlStaticFileReader: RuntimeControlStaticFileReading {
    public init() {}

    public func pathState(at url: URL) -> RuntimePathState {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                return .other("missing-file-type")
            }
            switch type {
            case .typeRegular:
                return .file
            case .typeDirectory:
                return .directory
            default:
                return .other(type.rawValue)
            }
        } catch {
            return isNoSuchFile(error) ? .missing : .inspectFailed(error.localizedDescription)
        }
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    private func isNoSuchFile(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
            return true
        }
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOENT)
    }
}

public struct RuntimeControlStaticFileResponder: Sendable {
    private let fileReader: any RuntimeControlStaticFileReading
    private let pathResolver: RuntimeControlStaticFilePathResolver
    private let responseFactory = RuntimeControlStaticFileResponseFactory()

    public init(
        rootDirectory: URL,
        fileReader: any RuntimeControlStaticFileReading = SystemRuntimeControlStaticFileReader()
    ) {
        self.fileReader = fileReader
        self.pathResolver = RuntimeControlStaticFilePathResolver(
            rootDirectory: rootDirectory,
            fileReader: fileReader
        )
    }

    public func response(for request: RuntimeControlHTTPRequest) -> RuntimeControlHTTPResponse? {
        guard pathResolver.shouldHandle(request) else {
            return nil
        }

        switch pathResolver.lookup(rawPath: request.path) {
        case .found(let fileURL):
            do {
                let body = try fileReader.readData(at: fileURL)
                return responseFactory.found(fileURL: fileURL, body: body)
            } catch {
                return responseFactory.readFailed(error.localizedDescription)
            }
        case .notFound:
            return responseFactory.notFound()
        case .failed(let reason):
            return responseFactory.readFailed(reason)
        case .rejected(let reason):
            return responseFactory.badRequest(reason)
        }
    }
}
