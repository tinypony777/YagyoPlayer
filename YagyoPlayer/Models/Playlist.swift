import Foundation

/// アプリ内でユーザーが自由に曲を整理するための巻物（プレイリスト）。
struct Playlist: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var trackIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        trackIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.trackIDs = trackIDs
    }

    var trackCount: Int {
        trackIDs.count
    }

    func contains(_ trackID: UUID) -> Bool {
        trackIDs.contains(trackID)
    }

    mutating func add(_ trackID: UUID) {
        guard !trackIDs.contains(trackID) else { return }
        trackIDs.append(trackID)
    }

    mutating func remove(_ trackID: UUID) {
        trackIDs.removeAll { $0 == trackID }
    }

    mutating func move(_ trackID: UUID, by offset: Int) {
        guard let index = trackIDs.firstIndex(of: trackID) else { return }
        let destination = index + offset
        guard trackIDs.indices.contains(destination) else { return }
        trackIDs.swapAt(index, destination)
    }
}
