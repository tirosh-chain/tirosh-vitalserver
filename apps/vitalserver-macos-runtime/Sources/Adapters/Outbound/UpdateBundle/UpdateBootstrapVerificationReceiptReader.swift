import Application
import Contracts
import Darwin
import Foundation

public struct UpdateBootstrapVerificationReceiptReader:
    UpdateBootstrapVerificationReceiptReading
{
    public let pathState: (URL) -> RuntimePathState
    public let readData: (URL) throws -> Data

    public init(
        pathState: @escaping (URL) -> RuntimePathState,
        readData: @escaping (URL) throws -> Data
    ) {
        self.pathState = pathState
        self.readData = readData
    }

    public func read(
        at url: URL
    ) -> UpdateBootstrapVerificationReceiptReadResult {
        switch pathState(url) {
        case .missing:
            return .missing(path: url.path)
        case .file:
            break
        case .directory:
            return .unexpectedPathState(path: url.path, state: "directory")
        case .other(let value):
            return .unexpectedPathState(path: url.path, state: value)
        case .inspectFailed(let reason):
            return .inspectionFailed(path: url.path, reason: reason)
        case .unknown(let value):
            return .unexpectedPathState(path: url.path, state: value)
        }

        let data: Data
        do {
            data = try readData(url)
        } catch {
            if POSIXFileAccessFailure.isPermissionDenied(error) {
                return .permissionDenied(
                    path: url.path,
                    reason: String(describing: error)
                )
            }
            return .readFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
        do {
            return .loaded(
                try JSONDecoder().decode(
                    UpdateBootstrapVerificationReceipt.self,
                    from: data
                )
            )
        } catch {
            return .decodeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }
    }
}

enum POSIXFileAccessFailure {
    static func isPermissionDenied(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == NSFileReadNoPermissionError
            || cocoaError.code == NSFileWriteNoPermissionError {
            return true
        }
        if cocoaError.domain == NSPOSIXErrorDomain,
           cocoaError.code == Int(EACCES) || cocoaError.code == Int(EPERM) {
            return true
        }
        guard let underlying = cocoaError.userInfo[NSUnderlyingErrorKey]
            as? NSError else {
            return false
        }
        return underlying.domain == NSPOSIXErrorDomain
            && (underlying.code == Int(EACCES) || underlying.code == Int(EPERM))
    }
}
