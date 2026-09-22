import Foundation

/// Stores completed practice summaries in a small, versioned JSON file.
struct PracticeHistoryStore {
    let directory: URL
    private let fileName = "practice-history.json"

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private struct Archive: Codable {
        let version: Int
        let sessions: [PracticeSessionSummary]
    }

    /// Loads the newest 100 valid summaries. A missing file means no history.
    func load() throws -> [PracticeSessionSummary] {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
        guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return Array(archive.sessions.sorted { $0.completedAt > $1.completedAt }.prefix(100))
    }

    /// Atomically writes summaries and keeps the newest sessions first.
    func save(_ sessions: [PracticeSessionSummary]) throws {
        let ordered = Array(sessions.sorted { $0.completedAt > $1.completedAt }.prefix(100))
        let data = try JSONEncoder().encode(Archive(version: 1, sessions: ordered))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
    }
}
