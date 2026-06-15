public enum RuntimeGuestDocumentLoadResult<Document> {
    case missing
    case loaded(Document)
    case failed(String)
}
