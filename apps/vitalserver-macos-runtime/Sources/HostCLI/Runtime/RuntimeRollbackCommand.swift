import Foundation

enum RuntimeRollbackCommand: Equatable {
    case latestBackup
    case specificBackup(URL)
}
