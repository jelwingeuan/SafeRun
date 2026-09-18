import Foundation

struct PathValidator: Sendable {
    static func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func isWithinRoot(_ candidate: URL, root: URL) -> Bool {
        let rootPath = normalized(root).path
        let candidatePath = normalized(candidate).path

        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return false
        }

        return !candidatePath.split(separator: "/").contains("..")
    }

    static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    static func isSafeDestination(_ destination: URL?, root: URL) -> Bool {
        guard let destination else { return true }
        return isWithinRoot(destination, root: root) && isValidFileName(destination.lastPathComponent)
    }
}
