import Contracts
import Errors
public protocol RuntimeHTTPProber {
    func statusCode(url: String) -> String
}
