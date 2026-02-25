import Foundation

struct ProfileManager {
    static func listProfiles() -> [String] {
        var profiles = Set<String>()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let awsDir = home.appendingPathComponent(".aws")

        for file in ["config", "credentials"] {
            let url = awsDir.appendingPathComponent(file)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    var name = String(trimmed.dropFirst().dropLast())
                    if name.hasPrefix("profile ") { name = String(name.dropFirst(8)) }
                    profiles.insert(name)
                }
            }
        }

        return profiles.isEmpty ? ["default"] : Array(profiles).sorted()
    }
}
