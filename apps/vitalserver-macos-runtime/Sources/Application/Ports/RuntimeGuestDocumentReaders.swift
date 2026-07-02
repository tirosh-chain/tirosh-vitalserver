import Contracts
import Foundation

public typealias RuntimeGuestDocumentLoadResult<Document> = Contracts.RuntimeGuestDocumentLoadResult<Document>

public protocol RuntimeGuestBootstrapResultReader {
    func loadBootstrapResultDocument() -> RuntimeGuestDocumentLoadResult<GuestBootstrapResultDocument>
}
