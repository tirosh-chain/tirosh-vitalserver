import RuntimeContracts
public protocol RuntimeHTTPProber {
    func statusCode(url: String) -> String
}
