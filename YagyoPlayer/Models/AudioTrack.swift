import Foundation

struct AudioTrack: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var originalFilename: String
    var storedFilename: String
    var importedAt: Date
    var duration: TimeInterval?

    init(
        id: UUID = UUID(),
        title: String,
        originalFilename: String,
        storedFilename: String,
        importedAt: Date = Date(),
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.originalFilename = originalFilename
        self.storedFilename = storedFilename
        self.importedAt = importedAt
        self.duration = duration
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
}
