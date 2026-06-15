import Foundation
import Application
import Contracts
import Errors

public enum RedisBackupResultReader {
    public static func load(from url: URL, fileStore: RuntimeFileStore) -> RuntimeRedisBackupResultLoadResult {
        let state = fileStore.pathState(at: url)
        switch state {
        case .file:
            break
        case .missing:
            return .missing
        case .inspectFailed(let reason):
            return .failed("redis backup result path inspection failed path=\(url.path) reason=\(reason)")
        case .directory, .other, .unknown:
            return .failed("redis backup result path state is unexpected path=\(url.path) state=\(state.rawValue)")
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(RedisBackupResultDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
