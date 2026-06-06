import Contracts
public protocol RuntimeHTTPProber {
    func statusCode(url: String) -> String
}
