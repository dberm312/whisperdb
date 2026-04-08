import Foundation

public enum EnvLoader {
    public static func load() -> [String: String] {
        // On macOS: look for .env file in standard locations
        // On iOS: look for Config.plist in the app bundle
        #if os(iOS)
        return loadFromPlist()
        #else
        return loadFromEnvFile()
        #endif
    }

    public static func get(_ key: String) -> String? {
        // Check process environment first (allows override)
        if let value = ProcessInfo.processInfo.environment[key] {
            return value
        }
        return load()[key]
    }

    // MARK: - macOS: .env file

    #if os(macOS)
    private static func loadFromEnvFile() -> [String: String] {
        let candidates = [
            FileManager.default.currentDirectoryPath + "/.env",
            Bundle.main.bundlePath + "/../.env",
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/.env").path,
            (Bundle.main.resourcePath ?? "") + "/.env",
        ]

        for path in candidates {
            if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
                return parseEnv(contents)
            }
        }
        return [:]
    }

    private static func parseEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                   (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                result[key] = value
            }
        }
        return result
    }
    #endif

    // MARK: - iOS: Config.plist

    #if os(iOS)
    private static func loadFromPlist() -> [String: String] {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            return [:]
        }
        return dict
    }
    #endif
}
