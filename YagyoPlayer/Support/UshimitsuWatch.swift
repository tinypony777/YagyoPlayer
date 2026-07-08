import Combine
import Foundation

/// 丑三つ時 — 深夜2時になると自動で夜が深まり、絵巻の月に触れると
/// 手動でも刻を進められる。Web版の refreshNight の移植。
@MainActor
final class UshimitsuWatch: ObservableObject {
    @Published private(set) var isNight = false
    @Published private(set) var announcement: String?

    private var forced = false
    private var timer: Timer?
    private var announcementTask: Task<Void, Never>?

    init() {
        refresh(announce: false)
        // 自分が居なくなったら次の刻で自ら止まる — deinit不要のリーク対策
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor in
                self?.refresh(announce: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func toggleForced() {
        forced.toggle()
        refresh(announce: true)
    }

    private func refresh(announce: Bool) {
        let isWitchingHour = Calendar.current.component(.hour, from: Date()) == 2
        let next = forced || isWitchingHour
        guard next != isNight else { return }

        isNight = next
        if announce {
            show(next ? "丑三つ時──" : "夜が明けた")
        }
    }

    private func show(_ text: String) {
        announcement = text
        announcementTask?.cancel()
        announcementTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            self?.announcement = nil
        }
    }
}
