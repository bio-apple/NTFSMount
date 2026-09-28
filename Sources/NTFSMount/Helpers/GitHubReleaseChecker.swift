import Foundation
import NTFSMountCore

/// Quiet GitHub `/releases/latest` probe. Failures (offline, timeout, bad JSON) return nil.
enum GitHubReleaseChecker {
  static func fetchLatestVersion(
    session: URLSession = .shared
  ) async -> String? {
    var request = URLRequest(url: GitHubReleaseUpdate.latestReleaseAPIURL)
    request.timeoutInterval = 12
    request.setValue("NTFSMount", forHTTPHeaderField: "User-Agent")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
      else { return nil }
      return GitHubReleaseUpdate.tagName(fromLatestReleaseJSON: data)
    } catch {
      return nil
    }
  }
}
