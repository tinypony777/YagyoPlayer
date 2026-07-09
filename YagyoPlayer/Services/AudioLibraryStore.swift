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

/// ライブラリ一覧の並び替え。妖怪起点の並び替えは Product Direction §6 に従い持たない。
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case newest = "追加日の新しい順"
    case oldest = "追加日の古い順"
    case titleAscending = "タイトル A-Z"
    case titleDescending = "タイトル Z-A"
    case durationAscending = "長さの短い順"
    case durationDescending = "長さの長い順"
    case playlistOrder = "巻物の並び"

    var id: String { rawValue }
}

/// 既存 manifest に残っている同一ハッシュの重複を UI に出すための読み取りモデル。
struct DuplicateTrackGroup: Equatable, Identifiable, Sendable {
    var id: String { contentHash }
    let contentHash: String
    let tracks: [AudioTrack]
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

    /// import 時に弾けなかった legacy manifest の重複を利用者へ見せる。
    var duplicateTrackGroups: [DuplicateTrackGroup] {
        let groups = Dictionary(grouping: tracks.compactMap { track -> (String, AudioTrack)? in
            guard let contentHash = track.contentHash, !contentHash.isEmpty else { return nil }
            return (contentHash, track)
        }, by: { $0.0 })

        return groups.compactMap { contentHash, entries -> DuplicateTrackGroup? in
            let duplicateTracks = entries.map { $0.1 }
            guard duplicateTracks.count > 1 else { return nil }
            return DuplicateTrackGroup(
                contentHash: contentHash,
                tracks: duplicateTracks.sorted { $0.importedAt < $1.importedAt }
            )
        }
        .sorted { lhs, rhs in
            (lhs.tracks.first?.title ?? "")
                .localizedStandardCompare(rhs.tracks.first?.title ?? "") == .orderedAscending
        }
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

    /// Step 2 — Library Confidence: title / artist / artwork / notes を編集して永続化する。
    @discardableResult
    func updateMetadata(
        for trackID: AudioTrack.ID,
        title: String,
        artist: String?,
        artworkFilename: String?,
        notes: String?
    ) -> Bool {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return false }

        let previousTrack = tracks[index]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return false }

        tracks[index].title = trimmedTitle
        tracks[index].artist = Self.nilIfBlank(artist)
        tracks[index].artworkFilename = Self.nilIfBlank(artworkFilename)
        tracks[index].notes = Self.nilIfBlank(notes)

        do {
            try save()
            persistenceErrorMessage = nil
            return true
        } catch {
            tracks[index] = previousTrack
            persistenceErrorMessage = "Track metadata could not be saved: \(error.localizedDescription)"
            return false
        }
    }

    func delete(_ track: AudioTrack) {
        let previousTracks = tracks
        let previousSelectedTrackID = selectedTrackID
        let previousPlaylists = playlists

        tracks.removeAll { $0.id == track.id }
        if selectedTrackID == track.id {
            selectedTrackID = tracks.first?.id
        }

        var playlistsChanged = false
        for index in playlists.indices where playlists[index].contains(track.id) {
            playlists[index].remove(track.id)
            playlistsChanged = true
        }

        // 先に manifest を保存する: 失敗したら tracks・playlists ともに巻き戻し、ファイルはまだ消さない
        // (取込元コピーを失わないため)。playlists.json への反映も manifest 保存が成功してから行う —
        // 先に保存してしまうと、直後の manifest 保存が失敗したときに巻物の所属だけが巻き戻せなくなる。
        do {
            try save()
        } catch {
            tracks = previousTracks
            selectedTrackID = previousSelectedTrackID
            playlists = previousPlaylists
            persistenceErrorMessage = "Library could not be saved after delete: \(error.localizedDescription)"
            return
        }

        if playlistsChanged {
            try? savePlaylists()
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

    /// 検索・スコープ・並び替えを一つの入口にまとめる。UI はここだけを読めばよい。
    func filteredTracks(
        searchText: String = "",
        sort: LibrarySort = .newest,
        playlistID: Playlist.ID? = nil
    ) -> [AudioTrack] {
        let scopedTracks: [AudioTrack]
        if let playlistID,
           let playlist = playlists.first(where: { $0.id == playlistID }) {
            scopedTracks = tracks(in: playlist)
        } else {
            scopedTracks = tracks
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredTracks = query.isEmpty
            ? scopedTracks
            : scopedTracks.filter { $0.searchIndexText.contains(query) }

        switch sort {
        case .newest:
            return filteredTracks.sorted { $0.importedAt > $1.importedAt }
        case .oldest:
            return filteredTracks.sorted { $0.importedAt < $1.importedAt }
        case .titleAscending:
            return filteredTracks.sorted { Self.titleComesBefore($0, $1) }
        case .titleDescending:
            return filteredTracks.sorted { Self.titleComesBefore($1, $0) }
        case .durationAscending:
            return filteredTracks.sorted { lhs, rhs in
                Self.durationSortValue(lhs, nilValue: .greatestFiniteMagnitude)
                    < Self.durationSortValue(rhs, nilValue: .greatestFiniteMagnitude)
            }
        case .durationDescending:
            return filteredTracks.sorted { lhs, rhs in
                Self.durationSortValue(lhs, nilValue: -.greatestFiniteMagnitude)
                    > Self.durationSortValue(rhs, nilValue: -.greatestFiniteMagnitude)
            }
        case .playlistOrder:
            return playlistID == nil
                ? filteredTracks.sorted { $0.importedAt > $1.importedAt }
                : filteredTracks
        }
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

    private static func nilIfBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func titleComesBefore(_ lhs: AudioTrack, _ rhs: AudioTrack) -> Bool {
        let result = lhs.title.localizedStandardCompare(rhs.title)
        if result == .orderedSame {
            return lhs.importedAt > rhs.importedAt
        }
        return result == .orderedAscending
    }

    private static func durationSortValue(_ track: AudioTrack, nilValue: TimeInterval) -> TimeInterval {
        guard let duration = track.duration, duration.isFinite, duration >= 0 else {
            return nilValue
        }
        return duration
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
