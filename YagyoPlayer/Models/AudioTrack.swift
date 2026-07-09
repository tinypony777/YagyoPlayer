import Foundation

struct AudioTrack: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var originalFilename: String
    var storedFilename: String
    var importedAt: Date
    var duration: TimeInterval?

    /// ユーザーが編集できる任意のアーティスト名。
    var artist: String?
    /// artwork の参照名。画像ファイルの実体導入は後続で扱い、ここでは library.json に残るメタデータとして保持する。
    var artworkFilename: String?

    /// SHA-256(hex)。取込時に計算し、重複検出・バージョン束・A/B比較の土台になる。
    var contentHash: String?

    // MARK: 住み着きの統計(§4.3)— すべて optional で library.json 後方互換

    /// 再生イベント(半分以上の再生または完走)の累計回数。
    var playCount: Int?
    /// 最後に再生イベントが記録された日時。
    var lastPlayedAt: Date?
    /// 聴いた時間帯の記録。キーは "0"〜"23"(時)、値はその時間帯の再生イベント数。
    var playHourCounts: [String: Int]?
    /// ユーザーのメモ。
    var notes: String?

    init(
        id: UUID = UUID(),
        title: String,
        originalFilename: String,
        storedFilename: String,
        importedAt: Date = Date(),
        duration: TimeInterval? = nil,
        artist: String? = nil,
        artworkFilename: String? = nil,
        contentHash: String? = nil,
        playCount: Int? = nil,
        lastPlayedAt: Date? = nil,
        playHourCounts: [String: Int]? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.importedAt = importedAt
        self.duration = duration
        self.artist = artist
        self.artworkFilename = artworkFilename
        self.contentHash = contentHash
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.playHourCounts = playHourCounts
        self.notes = notes
    }

    /// 再生イベントを 1 回分記録する。
    mutating func recordPlayback(at date: Date = Date(), calendar: Calendar = .current) {
        playCount = (playCount ?? 0) + 1
        lastPlayedAt = date
        let hourKey = String(calendar.component(.hour, from: date))
        var counts = playHourCounts ?? [:]
        counts[hourKey, default: 0] += 1
        playHourCounts = counts
    }

    var durationText: String {
        guard let duration, duration.isFinite, duration > 0 else {
            return "--:--"
        }

        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var importedDateText: String {
        importedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var searchIndexText: String {
        [title, artist, originalFilename, storedFilename, artworkFilename, notes]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
    }
}
