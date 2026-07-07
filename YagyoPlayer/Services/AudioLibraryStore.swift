import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AudioLibraryStore: ObservableObject {
    enum ImportState: Equatable {
        case idle
        case importing(Int)
        case finished(Int)
        case failed(String)
    }

    @Published private(set) var tracks: [AudioTrack] = []
    @Published var selectedTrackID: AudioTrack.ID?
    @Published var importState: ImportState = .idle

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
                return
            }

            let data = try Data(contentsOf: manifestURL)
            tracks = try decoder.decode([AudioTrack].self, from: data)
                .sorted { $0.importedAt > $1.importedAt }
            selectedTrackID = tracks.first?.id
        } catch {
            importState = .failed("Library could not be loaded.")
            tracks = []
        }
    }

    func importAudioFiles(from urls: [URL]) async {
        guard !urls.isEmpty else { return }

        importState = .importing(urls.count)
        var importedTracks: [AudioTrack] = []

        do {
            try ensureLibraryDirectory()
            for url in urls {
                if let track = try await copyIntoLibrary(url) {
                    importedTracks.append(track)
                }
            }

            tracks.insert(contentsOf: importedTracks, at: 0)
            selectedTrackID = importedTracks.first?.id ?? selectedTrackID
            try save()
            importState = .finished(importedTracks.count)
        } catch {
            importState = .failed(error.localizedDescription)
        }
    }

    func delete(_ track: AudioTrack) {
        tracks.removeAll { $0.id == track.id }
        if selectedTrackID == track.id {
            selectedTrackID = tracks.first?.id
        }

        try? fileManager.removeItem(at: fileURL(for: track))
        try? save()
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

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var libraryDirectory: URL {
        documentsDirectory.appending(path: "YagyoLibrary", directoryHint: .isDirectory)
    }

    private var manifestURL: URL {
        libraryDirectory.appending(path: "library.json", directoryHint: .notDirectory)
    }

    private func ensureLibraryDirectory() throws {
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
    }

    private func save() throws {
        let data = try encoder.encode(tracks)
        try data.write(to: manifestURL, options: [.atomic])
    }

    private func copyIntoLibrary(_ sourceURL: URL) async throws -> AudioTrack? {
        let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard sourceURL.conformsToAudioType else { return nil }

        let originalFilename = sourceURL.lastPathComponent
        let baseTitle = sourceURL.deletingPathExtension().lastPathComponent
        let destinationFilename = uniqueFilename(for: sourceURL)
        let destinationURL = libraryDirectory.appending(path: destinationFilename, directoryHint: .notDirectory)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let duration = await audioDuration(for: destinationURL)
        return AudioTrack(
            title: baseTitle.isEmpty ? originalFilename : baseTitle,
            originalFilename: originalFilename,
            storedFilename: destinationFilename,
            duration: duration
        )
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
        guard !tracks.isEmpty else { return nil }
        guard let track, let index = tracks.firstIndex(where: { $0.id == track.id }) else {
            return tracks.first
        }

        let nextIndex = (index + offset + tracks.count) % tracks.count
        return tracks[nextIndex]
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
