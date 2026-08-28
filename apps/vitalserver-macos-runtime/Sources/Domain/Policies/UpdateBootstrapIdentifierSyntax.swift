public enum UpdateBootstrapIdentifierSyntax {
    public static func isIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            return (65...90).contains(code)
                || (97...122).contains(code)
                || (48...57).contains(code)
                || "-._".unicodeScalars.contains(scalar)
        }
    }

    public static func isVersion(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            let code = scalar.value
            return (65...90).contains(code)
                || (97...122).contains(code)
                || (48...57).contains(code)
                || ".+-_".unicodeScalars.contains(scalar)
        }
    }
}
