import Contracts
import Errors
public protocol RuntimeHTTPProber {
    func statusCode(url: String) -> String
    func statusRead(url: String) -> RuntimeHTTPProbeResult
}

public extension RuntimeHTTPProber {
    func statusRead(url: String) -> RuntimeHTTPProbeResult {
        .reportedStatus(statusCode(url: url))
    }
}
