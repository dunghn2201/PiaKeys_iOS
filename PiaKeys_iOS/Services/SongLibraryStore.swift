import Foundation

/// Persists the imported library atomically. Score paths are relative to Application
/// Support so they survive changes to the application's sandbox container URL.
struct SongLibraryStore {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    private struct Library: Codable {
        let version: Int
        var songs: [PracticeSong]
    }

    func load() throws -> [PracticeSong] {
        let url = directory.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [.demo] }
        var library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: url))
        guard library.version == 1,
              Set(library.songs.map(\.id)).count == library.songs.count,
              library.songs.allSatisfy({ song in
                  !song.id.isEmpty && song.notes.allSatisfy {
                      (21...108).contains($0.noteNumber) && (1...127).contains($0.velocity) &&
                      $0.startMilliseconds >= 0 && $0.durationMilliseconds > 0 &&
                      !$0.startMilliseconds.addingReportingOverflow($0.durationMilliseconds).overflow
                  }
              }) else { throw CocoaError(.fileReadCorruptFile) }
        for index in library.songs.indices {
            library.songs[index].scoreURL = library.songs[index].scoreURL.map {
                directory.appendingPathComponent("Scores").appendingPathComponent($0.lastPathComponent)
            }
        }
        return library.songs.isEmpty ? [.demo] : library.songs
    }

    func save(_ songs: [PracticeSong]) throws {
        // A failed restore must not let a later import overwrite the unreadable
        // original library. Keep it available for recovery.
        _ = try load()
        var storedSongs = songs
        for index in storedSongs.indices {
            storedSongs[index].scoreURL = storedSongs[index].scoreURL.map { URL(fileURLWithPath: $0.lastPathComponent) }
        }
        let data = try JSONEncoder().encode(Library(version: 1, songs: storedSongs))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("library.json"), options: .atomic)
    }
}
