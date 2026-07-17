import Foundation

enum UpdateAgentConfiguration {
    static let githubReleaseAPI = URL(string: "https://api.github.com/repos/apple/container/releases/latest")!
    static let jitterRange: ClosedRange<Int> = 0 ... 3600
}
