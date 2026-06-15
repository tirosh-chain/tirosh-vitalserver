import Foundation
import Errors

public enum RuntimeControlDevConsoleDocument {
    public static let path = "/dev/runtime-control"

    public static func response(for request: RuntimeControlHTTPRequest) -> RuntimeControlHTTPResponse? {
        guard request.method == .get else {
            return nil
        }
        let requestPath = URLComponents(string: request.path)?.path ?? request.path
        guard requestPath == path || requestPath == "\(path)/" || requestPath == "\(path).html" else {
            return nil
        }
        return htmlResponse()
    }

    private static func htmlResponse() -> RuntimeControlHTTPResponse {
        guard let url = Bundle.module.url(forResource: "RuntimeControlDevConsole", withExtension: "html") else {
            return resourceFailureResponse("Runtime Control dev console resource is missing.")
        }
        do {
            return RuntimeControlHTTPResponse(
                status: .ok,
                headers: ["Content-Type": "text/html; charset=utf-8"],
                body: try Data(contentsOf: url)
            )
        } catch {
            return resourceFailureResponse("Runtime Control dev console resource could not be read: \(error.localizedDescription)")
        }
    }

    private static func resourceFailureResponse(_ message: String) -> RuntimeControlHTTPResponse {
        RuntimeControlHTTPResponse(
            status: .internalServerError,
            headers: ["Content-Type": "application/json"],
            body: RuntimeControlErrorResponseEncoder.encode(code: .handlerFailed, message: message)
        )
    }
}
