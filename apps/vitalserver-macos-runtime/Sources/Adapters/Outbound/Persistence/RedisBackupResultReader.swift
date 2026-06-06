import Foundation
import Application
import Contracts
import Errors

public enum RedisBackupResultReader {
    public static func load(from url: URL, fileStore: RuntimeFileStore) -> RuntimeRedisBackupResultLoadResult {
        guard fileStore.fileExists(url) else {
            return .missing
        }
        do {
            let data = try fileStore.readData(url)
            return try .loaded(JSONDecoder().decode(RedisBackupResultDocument.self, from: data))
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
