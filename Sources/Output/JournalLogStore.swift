import Foundation

struct JournalLogStore {
    enum JournalLogStoreError: LocalizedError {
        case unableToResolveFolder

        var errorDescription: String? {
            switch self {
            case .unableToResolveFolder:
                return "Unable to resolve the journal folder."
            }
        }
    }

    let folderURL: URL
    var calendar: Calendar = .autoupdatingCurrent
    var timeZone: TimeZone = .autoupdatingCurrent

    static var defaultFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("FreeFlow Journal", isDirectory: true)
    }

    static func makeBookmarkData(for folderURL: URL) -> Data? {
        try? folderURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolveFolderURL(bookmarkData: Data?, plainPath: String?) -> URL {
        if let bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), !isStale {
                return url
            }
        }

        if let plainPath,
           !plainPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: (plainPath as NSString).expandingTildeInPath)
        }

        return defaultFolderURL
    }

    func dailyFileURL(for date: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return folderURL.appendingPathComponent("\(formatter.string(from: date)).md", isDirectory: false)
    }

    func append(rawTranscript: String, at date: Date = Date()) throws -> URL? {
        let trimmedTranscript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { return nil }

        let accessStarted = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessStarted {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"

        let entry = "### \(formatter.string(from: date))\n\n\(trimmedTranscript)\n\n"
        let fileURL = dailyFileURL(for: date)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            guard let data = entry.data(using: .utf8) else { return fileURL }
            try handle.write(contentsOf: data)
        } else {
            try entry.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return fileURL
    }
}
