import Foundation

enum YokaiResidency {
    static let stableSpriteIDs = [
        "oni", "mokugyo", "kasa", "kappa", "kitsune", "tengu", "yuki", "biwa"
    ]

    static func spriteID(for trackID: UUID) -> String {
        let sum = trackID.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return stableSpriteIDs[sum % stableSpriteIDs.count]
    }

    static func processionIDs(residentID: String?, isUshimitsu: Bool) -> [String] {
        var ids: [String]
        if let residentID, stableSpriteIDs.contains(residentID) {
            ids = [residentID] + stableSpriteIDs.filter { $0 != residentID }
        } else {
            ids = stableSpriteIDs
        }
        if isUshimitsu { ids.append("hitotsume") }
        return ids
    }
}
