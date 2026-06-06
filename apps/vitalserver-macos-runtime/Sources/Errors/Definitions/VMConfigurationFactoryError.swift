import Foundation

public enum VMConfigurationFactoryError: Error, Equatable {
    case invalidMacAddress(String)
    case missingBridgedInterface
    case noBridgedInterfaces
    case bridgedInterfaceUnavailable(String)
}
