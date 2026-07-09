import AVFoundation
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// 取込 1 件分の失敗記録。
struct ImportFailure: Equatable, Identifiable, Sendable {
    var id: String { filename }
    let filename: String
    let reason: String
}

/// 取込結果の集計 — 成功・重複スキップ・失敗を個別に数える。
struct ImportSummary: Equatable, Sendable {
    var imported: Int = 0
    var duplicates: Int = 0
    var failures: [ImportFailure] = []

    var hasIssues: Bool {
        duplicates > 0 || !failures.isEmpty
    }
}

@MainActor
final class AudioLibraryStore: ObservableObject {
    enum ImportState: Equatable {
        case idle
        case importing(Int)
        case finished(ImportSummary)
        case failed(String)
    }

    @Published private(set) var tracks: [AudioTrack] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var selectedTrackID: AudioTrack.ID?
    @Published var activePlaylistID: Playlist.ID?
    @Published var importState: ImportState = .idle
    /// library.json への保存失敗をUIに知らせる(再生統計など、取込以外の書き込み用)。
    @Published var persistenceErrorMessage: String?

    private let fileManager: FileManager
    private let documentsDirectoryOverride: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default, documentsDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.documentsDirectoryOverride = documentsDirectory
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    var hasTracks: Bool {
        !tracks.isEmpty
    }

    var selectedTrack: AudioTrack? {
        guard let selectedTrackID else { return tracks.first }
        return tracks.first { $0.id == selectedTrackID } ?? tracks.first
    }

    func load() {
        do {
            try ensureLibraryDirectory()
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                tracks = []
                loadPlaylists()
                return
            }

            let data = try Data(contentsOf: manifestURL)
            tracks = try decoder.decode([AudioTrack].self, from: data)
                .sorted { $0.importedAt > $1.importedAt }
            selectedTrackID = tracks.first?.id
            loadPlaylists()
        } catch {
            importState = .failed("Library could not be loaded.")
            tracks = []
        }
    }

    func importAudioFiles(from urls: [URL]) async {
        guard !urls.isEmpty else { return }

        importState = .importing(urls.count)

        do {
            try ensureLibraryDirectory()
        } catch {
            importState = .failed(error.localizedDescription)
            return
        }

        var summary = ImportSummary()
        var importedTracks: [AudioTrack] = []
        backfillContentHashesIfNeeded()
        var knownHashes = Set(tracks.compactMap(\.contentHash))

        for url in urls {
            do {
                switch try await copyIntoLibrary(url, knownHashes: knownHashes) {
                case .imported(let track):
                    importedTracks.append(track)
                    summary.imported += 1
                    if let hash = track.contentHash {
                        knownHashes.insert(hash)
                    }
                case .duplicate:
                    summary.duplicates += 1
                case .unsupported:
                    summary.failures.append(
                        ImportFailure(filename: url.lastPathComponent, reason: "Unsupported file type")
                    )
                }
            } catch {
                summary.failures.append(
                    ImportFailure(filename: url.lastPathComponent, reason: error.localizedDescription)
                )
            }
        }

        if !importedTracks.isEmpty {
            tracks.insert(contentsOf: importedTracks, at: 0)
            do {
                try save()
                selectedTrackID = importedTracks.first?.id ?? selectedTrackID
            } catch {
                // 保存できなければ成功扱いにしない: メモリとコピー済みファイルを巻き戻し、失敗として報告する。
                let importedIDs = Set(importedTracks.map(\.id))
                tracks.removeAll { importedIDs.contains($0.id) }
                for track in importedTracks {
                    try? fileManager.removeItem(at: fileURL(for: track))
                }
                summary.imported = 0
                summary.failures.append(contentsOf: importedTracks.map { track in
                    ImportFailure(
                        filename: track.originalFilename,
                        reason: "Library could not be saved: \(error.localizedDescription)"
                    )
                })
            }
        }
        importState = .finished(summary)
    }

    /// PR適用前に取り込まれた曲は contentHash を持たないため、保存済みファイルから補完する。
    private func backfillContentHashesIfNeeded() {
        var didChange = false
        for index in tracks.indices where tracks[index].contentHash == nil {
            let url = fileURL(for: tracks[index])
            guard fileManager.fileExists(atPath: url.path),
                  let hash = try? Self.sha256Hex(of: url) else { continue }
            tracks[index].contentHash = hash
            didChange = true
        }
        if didChange {
            // 保存に失敗してもメモリ上のハッシュで重複判定は機能する。
            try? save()
        }
    }

    /// 再生イベント(半分以上の再生または完走)を統計に記録し、永続化する。
    func recordPlayback(for trackID: AudioTrack.ID, at date: Date = Date()) {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        tracks[index].recordPlayback(at: date)
        do {
            try save()
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Playback stats could not be saved: \(error.localizedDescription)"
        }
    }

    func delete(_ track: AudioTrack) {
        let previousTracks = tracks
        let previousSelectedTrackID = selectedTrackID

        tracks.removeAll { $0.id == track.id }
        if selectedTrackID == track.id {
            selectedTrackID = tracks.first?.id
        }

        var playlistsChanged = false
        for index in playlists.indices where playlists[index].contains(track.id) {
            playlists[index].remove(track.id)
            playlistsChanged = true
        }
        if playlistsChanged {
            try? savePlaylists()
        }

        // 先に manifest を保存する: 失敗したら巻き戻し、ファイルはまだ消さない(取込元コピーを失わないため)。
        do {
            try save()
        } catch {
            tracks = previousTracks
            selectedTrackID = previousSelectedTrackID
            persistenceErrorMessage = "Library could not be saved after delete: \(error.localizedDescription)"
            return
        }

        do {
            try fileManager.removeItem(at: fileURL(for: track))
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "The audio file could not be removed after delete: \(error.localizedDescription)"
        }
    }

    func select(_ track: AudioTrack) {
        selectedTrackID = track.id
    }

    func fileURL(for track: AudioTrack) -> URL {
        libraryDirectory.appending(path: track.storedFilename, directoryHint: .notDirectory)
    }

    func nextTrack(after track: AudioTrack?) -> AudioTrack? {
        trackByOffset(1, from: track)
    }

    func previousTrack(before track: AudioTrack?) -> AudioTrack? {
        trackByOffset(-1, from: track)
    }

    func mostRecentTrack() -> AudioTrack? {
        tracks.sorted { $0.importedAt > $1.importedAt }.first
    }

    // MARK: - Playlists

    var activePlaylist: Playlist? {
        guard let activePlaylistID else { return nil }
        return playlists.first { $0.id == activePlaylistID }
    }

    /// 次曲・前曲の巡回対象。巻物が選ばれていればその並び、なければ行列全体。
    var playbackQueue: [AudioTrack] {
        guard let activePlaylist else { return tracks }
        let queue = tracks(in: activePlaylist)
        return queue.isEmpty ? tracks : queue
    }

    func tracks(in playlist: Playlist) -> [AudioTrack] {
        let trackByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.trackIDs.compactMap { trackByID[$0] }
    }

    @discardableResult
    func createPlaylist(named name: String) -> Playlist? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let playlist = Playlist(name: trimmed)
        playlists.append(playlist)
        try? savePlaylists()
        return playlist
    }

    func renamePlaylist(_ playlist: Playlist, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].name = trimmed
        try? savePlaylists()
    }

    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        if activePlaylistID == playlist.id {
            activePlaylistID = nil
        }
        try? savePlaylists()
    }

    func addTrack(_ track: AudioTrack, to playlist: Playlist) {
        guard tracks.contains(where: { $0.id == track.id }),
              let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].add(track.id)
        try? savePlaylists()
    }

    func removeTrack(_ track: AudioTrack, from playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].remove(track.id)
        try? savePlaylists()
    }

    func moveTrack(_ track: AudioTrack, in playlist: Playlist, by offset: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists[index].move(track.id, by: offset)
        try? savePlaylists()
    }

    private var documentsDirectory: URL {
        if let documentsDirectoryOverride {
            return documentsDirectoryOverride
        }
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var libraryDirectory: URL {
        documentsDirectory.appending(path: "YagyoLibrary", directoryHint: .isDirectory)
    }

    private var manifestURL: URL {
        libraryDirectory.appending(path: "library.json", directoryHint: .notDirectory)
    }

    private var playlistsURL: URL {
        libraryDirectory.appending(path: "playlists.json", directoryHint: .notDirectory)
    }

    private func ensureLibraryDirectory() throws {
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
    }

    private func save() throws {
        let data = try encoder.encode(tracks)
        try data.write(to: manifestURL, options: [.atomic])
    }

    private func loadPlaylists() {
        guard fileManager.fileExists(atPath: playlistsURL.path) else {
            playlists = []
            activePlaylistID = nil
            return
        }

        do {
            let data = try Data(contentsOf: playlistsURL)
            playlists = try decoder.decode([Playlist].self, from: data)
            sanitizePlaylistsAgainstCurrentLibrary()
        } catch {
            playlists = []
            activePlaylistID = nil
        }
    }

    private func savePlaylists() throws {
        try ensureLibraryDirectory()
        let data = try encoder.encode(playlists)
        try data.write(to: playlistsURL, options: [.atomic])
    }

    private func sanitizePlaylistsAgainstCurrentLibrary() {
        let validTrackIDs = Set(tracks.map(\.id))
        var didChange = false

        for index in playlists.indices {
            let originalTrackIDs = playlists[index].trackIDs
            let sanitizedTrackIDs = originalTrackIDs.filter(validTrackIDs.contains)
            if sanitizedTrackIDs != originalTrackIDs {
                playlists[index].trackIDs = sanitizedTrackIDs
                didChange = true
            }
        }

        if let activePlaylistID,
           !playlists.contains(where: { $0.id == activePlaylistID }) {
            self.activePlaylistID = nil
        }

        if didChange {
            try? savePlaylists()
        }
    }

    private enum ImportOutcome {
        case imported(AudioTrack)
        case duplicate
        case unsupported
    }

    private func copyIntoLibrary(_ sourceURL: URL, knownHashes: Set<String>) async throws -> ImportOutcome {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard sourceURL.conformsToAudioType else { return .unsupported }

        let contentHash = try Self.sha256Hex(of: sourceURL)
        if knownHashes.contains(contentHash) {
            return .duplicate
        }

        let originalFilename = sourceURL.lastPathComponent
        let baseTitle = sourceURL.deletingPathExtension().lastPathComponent
        let destinationFilename = uniqueFilename(for: sourceURL)
        let destinationURL = libraryDirectory.appending(path: destinationFilename, directoryHint: .notDirectory)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let duration = await audioDuration(for: destinationURL)
        let track = AudioTrack(
            title: baseTitle.isEmpty ? originalFilename : baseTitle,
            originalFilename: originalFilename,
            storedFilename: destinationFilename,
            duration: duration,
            contentHash: contentHash
        )
        return .imported(track)
    }

    /// ファイル全体の SHA-256 をチャンク読みで計算する(大きな音源でもメモリを圧迫しない)。
    private static let hashChunkSize = 1_048_576

    private static func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: hashChunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func uniqueFilename(for url: URL) -> String {
        let extensionName = url.pathExtension.isEmpty ? "audio" : url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let safeStem = stem.isEmpty ? "track" : stem
        return "\(safeStem)-\(UUID().uuidString).\(extensionName)"
    }

    private func audioDuration(for url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : nil
        } catch {
            return nil
        }
    }

    private func trackByOffset(_ offset: Int, from track: AudioTrack?) -> AudioTrack? {
        let queue = playbackQueue
        guard !queue.isEmpty else { return nil }
        guard let track, let index = queue.firstIndex(where: { $0.id == track.id }) else {
            return queue.first
        }

        let nextIndex = (index + offset + queue.count) % queue.count
        return queue[nextIndex]
    }
}

private extension URL {
    var conformsToAudioType: Bool {
        if let type = UTType(filenameExtension: pathExtension), type.conforms(to: .audio) {
            return true
        }

        let audioExtensions = Set(["mp3", "m4a", "wav", "aiff", "aif", "aac", "caf", "flac"])
        return audioExtensions.contains(pathExtension.lowercased())
    }
}
