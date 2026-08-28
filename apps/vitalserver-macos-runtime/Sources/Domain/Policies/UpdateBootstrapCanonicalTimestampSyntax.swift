import Foundation

public enum UpdateBootstrapCanonicalTimestampSyntax {
    public static func isCanonical(_ value: String) -> Bool {
        guard value.count == 20,
              value[value.index(value.startIndex, offsetBy: 4)] == "-",
              value[value.index(value.startIndex, offsetBy: 7)] == "-",
              value[value.index(value.startIndex, offsetBy: 10)] == "T",
              value[value.index(value.startIndex, offsetBy: 13)] == ":",
              value[value.index(value.startIndex, offsetBy: 16)] == ":",
              value.hasSuffix("Z") else {
            return false
        }
        let formatter = makeFormatter()
        guard let date = formatter.date(from: value) else {
            return false
        }
        return formatter.string(from: date) == value
    }

    public static func format(_ date: Date) -> String {
        makeFormatter().string(from: date)
    }

    private static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        formatter.isLenient = false
        return formatter
    }
}
