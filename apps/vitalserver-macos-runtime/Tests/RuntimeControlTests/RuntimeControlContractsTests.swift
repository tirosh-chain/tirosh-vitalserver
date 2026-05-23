import RuntimeControl
import XCTest

final class RuntimeControlContractsTests: XCTestCase {
    func testRuntimeStatePreservesUnknownValues() throws {
        let state = RuntimeState(rawValue: "maintenance")

        XCTAssertEqual(state.rawValue, "maintenance")

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeState.self, from: encoded)

        XCTAssertEqual(decoded, .unknown("maintenance"))
    }

    func testRuntimeSettingsConfigureArgumentsUseNetworkModeRawValue() {
        let settings = RuntimeSettings(networkMode: .bridged, bridgedInterface: "en0")

        let arguments = settings.configureArguments()

        XCTAssertEqual(value(after: "--network", in: arguments), "bridged")
        XCTAssertEqual(value(after: "--bridged-interface", in: arguments), "en0")
    }

    private func value(after marker: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: marker),
              arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }
}
