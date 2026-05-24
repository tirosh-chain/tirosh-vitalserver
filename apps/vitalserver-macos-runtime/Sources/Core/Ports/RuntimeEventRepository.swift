import Contracts

public protocol RuntimeEventRepository {
    func append(_ event: RuntimeEventDocument) throws
    func recent(limit: Int) -> [RuntimeEventDocument]
}
