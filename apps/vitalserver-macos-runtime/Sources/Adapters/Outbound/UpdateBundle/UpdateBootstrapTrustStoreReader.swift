import Contracts
import Domain
import Foundation

public enum UpdateBootstrapTrustStoreLoadError: Error, Equatable, Sendable {
    case unavailable(path: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case invalid(UpdateBootstrapTrustStoreValidationError)
    case publicKeyDecodeFailed(keyId: String)
}

public struct UpdateBootstrapTrustStoreReader {
    public init() {}

    public func loadPublicKeys(from url: URL) throws -> [String: Data] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if isMissingFileError(error) {
                throw UpdateBootstrapTrustStoreLoadError.unavailable(path: url.path)
            }
            throw UpdateBootstrapTrustStoreLoadError.readFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }

        let store: UpdateBootstrapTrustStore
        do {
            store = try JSONDecoder().decode(
                UpdateBootstrapTrustStore.self,
                from: data
            )
        } catch {
            throw UpdateBootstrapTrustStoreLoadError.decodeFailed(
                path: url.path,
                reason: String(describing: error)
            )
        }

        do {
            try UpdateBootstrapTrustStorePolicy.validate(store)
        } catch let error as UpdateBootstrapTrustStoreValidationError {
            throw UpdateBootstrapTrustStoreLoadError.invalid(error)
        }

        var keys: [String: Data] = [:]
        for key in store.keys {
            guard let decoded = Data(base64Encoded: key.publicKey),
                  decoded.count == 32 else {
                throw UpdateBootstrapTrustStoreLoadError.publicKeyDecodeFailed(
                    keyId: key.id
                )
            }
            keys[key.id] = decoded
        }
        return keys
    }

    private func isMissingFileError(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == NSFileReadNoSuchFileError {
            return true
        }
        guard let underlying = cocoaError.userInfo[NSUnderlyingErrorKey] as? NSError else {
            return false
        }
        return underlying.domain == NSPOSIXErrorDomain && underlying.code == 2
    }
}
