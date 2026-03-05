import Foundation

struct UpdateCheckerService {
    private let baseURL = "https://api.github.com/repos/bilal-fazlani/aws-ssm-param-store-ui/releases"
    private let latestURL: URL

    private static var hasChecked = false

    init() {
        latestURL = URL(string: "\(baseURL)/latest")!
    }

    func checkForUpdate() async -> String? {
        guard !Self.hasChecked else { return nil }
        Self.hasChecked = true

        guard let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }

        guard let (data, _) = try? await URLSession.shared.data(from: latestURL) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String else {
            return nil
        }

        let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        return isNewer(remoteVersion, than: localVersion) ? remoteVersion : nil
    }

    func fetchReleaseNotes(for version: String) async -> String? {
        let tag = "v\(version)"
        guard let url = URL(string: "\(baseURL)/tags/\(tag)") else { return nil }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["body"] as? String,
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return body
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts  = local.split(separator: ".").compactMap { Int($0) }

        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count  ? localParts[i]  : 0
            if r != l { return r > l }
        }
        return false
    }
}
