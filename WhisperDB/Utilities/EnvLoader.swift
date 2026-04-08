import Foundation

enum EnvLoader {
    static func load() -> [String: String] {
        // Look for .env in the directory where the binary is run from
        let candidates = [
            FileManager.default.currentDirectoryPath + "/.env",
            Bundle.main.bundlePath + "/../.env",
        ]

        for path in candidates {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                return parse(contents)
            }
        }
        return [:]
    }

    static func get(_ key: String) -> String? {
        // Check process environment first (allows override), then .env file
        if let value = ProcessInfo.processInfo.environment[key] {
            return value
        }
        return load()[key]
    }

    private static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                // Strip surrounding quotes
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                result[key] = value
            }
        }
        return result
    }
}
