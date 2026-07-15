import Foundation
import Synchronization

final class SecurityScopedAccess: Sendable {
    private let accessedURLs: Mutex<[URL]>

    init(_ urls: [URL]) {
        var seen = Set<URL>()
        let accessed = urls.filter { url in
            guard url.isFileURL, seen.insert(url.standardizedFileURL).inserted else {
                return false
            }
            return url.startAccessingSecurityScopedResource()
        }
        accessedURLs = Mutex(accessed)
    }

    deinit {
        close()
    }

    func close() {
        let urls = accessedURLs.withLock { urls in
            let result = urls
            urls.removeAll()
            return result
        }
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
