import AVFoundation
import Foundation
import MediaPlayer
import UIKit

enum PlaybackContext: Equatable {
    case library
    case playlist(Playlist.ID)
}

@MainActor
final class PlaybackController: ObservableObject {
    @Published var currentTrack: AudioTrack?
    @Published var isPlaying = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.88 {
        didSet {
            applyEffectiveVolume()
        }
    }
    /// 狐火の帳でだけ使う減衰乗数。ユーザーの基準音量 `volume` とは保存・更新を分離する。
    @Published private(set) var loudnessMatchMultiplier: Float = 1
    /// 0 dB側も「適用中」と区別できるよう、乗数とは別に比較セッションの有効状態を持つ。
    @Published private(set) var isLoudnessMatchActive = false

    let paradeSignals = ParadeSignalCoordinator()
    private var smoothedAudioLevel = 0.0

    /// いま鳴っている音の大きさ(0...1)。夜行絵巻の妖怪や提灯がこれに反応する。
    var audioLevel: Double { paradeSignals.snapshot.level }

    /// 読み込み・再生に失敗したとき、無言で止まらずユーザーに伝えるためのメッセージ。
    @Published var playbackErrorMessage: String?

    private var audioPlayer: AVAudioPlayer?
    // deinit は nonisolated かつ Timer/観測トークンは Sendable ではないため、
    // 後始末を安全に行うために nonisolated(unsafe) にする(実際のアクセスは常に MainActor 上、
    // deinit 時点では他に参照が無く競合しない)。
    private nonisolated(unsafe) var timer: Timer?
    private nonisolated(unsafe) var meterTimer: Timer?
    private var remoteCommandsInstalled = false
    private weak var remoteLibrary: AudioLibraryStore?
    /// 現在のロードで再生イベント(半分以上の再生または完走)を記録済みか。
    private var hasRecordedPlaybackEvent = false

    /// 割り込み(電話・Siri)開始時点で再生中だったか。割り込み終了時、これが true の場合のみ再開する。
    private var wasPlayingBeforeInterruption = false
    /// 入れ子の割り込み(通話中にさらに別の割り込みが重なる等)に対応する深さ。0に戻ったときだけ再開を検討する。
    private var interruptionDepth = 0
    private nonisolated(unsafe) var notificationObserverTokens: [NSObjectProtocol] = []

    init() {
        installAudioSessionObservers()
    }

    deinit {
        timer?.invalidate()
        meterTimer?.invalidate()
        for token in notificationObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsedTime / duration, 0), 1)
    }

    var elapsedText: String {
        Self.timeText(elapsedTime)
    }

    var durationText: String {
        Self.timeText(duration)
    }

    /// A/B切替直前に読むbackendの現在位置。0.35秒周期のUI表示値を比較位置へ流用しない。
    var currentPlaybackTime: TimeInterval {
        audioPlayer?.currentTime ?? elapsedTime
    }

    /// AVAudioPlayerへ渡す実効音量。Phase Bは基準音量を上書きせず、この積だけを変更する。
    var effectiveVolume: Float {
        let baseVolume = volume.isFinite ? volume : 0
        let matchMultiplier = loudnessMatchMultiplier.isFinite ? loudnessMatchMultiplier : 1
        return min(max(baseVolume * matchMultiplier, 0), 1)
    }

    /// 減衰だけのラウドネスマッチを適用する。1より大きい値はブーストせず等倍へ戻す。
    func setLoudnessMatchMultiplier(_ multiplier: Float) {
        guard multiplier.isFinite else {
            clearLoudnessMatch()
            return
        }
        loudnessMatchMultiplier = min(max(multiplier, 0), 1)
        isLoudnessMatchActive = true
        applyEffectiveVolume()
    }

    /// 帳の比較を解除し、保存済みの基準音量を正確に復元する。
    func clearLoudnessMatch() {
        loudnessMatchMultiplier = 1
        isLoudnessMatchActive = false
        applyEffectiveVolume()
    }

    /// 参照Bの差し替え時、旧Bが鳴っていれば先に止めてから無効になったmatchを解除する。
    func prepareForLoudnessMatchReferenceChange(from previousReferenceTrackID: AudioTrack.ID?) {
        if currentTrack?.id == previousReferenceTrackID {
            pause()
        }
        clearLoudnessMatch()
    }

    /// AVAudioSession の割り込み・ルート変更を監視する。トラック未読込の時点から効くよう init で登録する。
    private func installAudioSessionObservers() {
        let center = NotificationCenter.default

        // Notification 自体は Sendable を保証できない(userInfo が [AnyHashable: Any])ため、
        // アクター境界を越える前にコールバック側で Sendable な値へ分解しておく。
        notificationObserverTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        })

        notificationObserverTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        })
    }

    /// 電話・Siri等の割り込みから復帰する。中断前に再生中だった場合のみ、かつ入れ子の割り込みがすべて終わったときだけ再開する。
    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if interruptionDepth == 0 {
                wasPlayingBeforeInterruption = isPlaying
            }
            interruptionDepth += 1
            pause()

        case .ended:
            interruptionDepth = max(0, interruptionDepth - 1)
            guard interruptionDepth == 0 else { return }
            defer { wasPlayingBeforeInterruption = false }
            guard wasPlayingBeforeInterruption else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
            guard options.contains(.shouldResume) else { return }
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                play()
            } catch {
                playbackErrorMessage = "Playback could not resume after the interruption: \(error.localizedDescription)"
            }

        @unknown default:
            break
        }
    }

    /// イヤホン・Bluetoothが外れたら一時停止する。スピーカーで自動継続しない — 音を意図せず外に出さないための約束。
    /// 割り込み中に出力先を失った場合は、割り込みが終わってもスピーカーへ自動再開しない。
    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable else { return }
        wasPlayingBeforeInterruption = false
        pause()
    }

    func installRemoteCommands(library: AudioLibraryStore) {
        remoteLibrary = library
        guard !remoteCommandsInstalled else { return }
        remoteCommandsInstalled = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    func load(
        _ track: AudioTrack,
        from library: AudioLibraryStore,
        autoplay: Bool = false,
        context: PlaybackContext? = nil
    ) {
        // 比較中の旧playerを先に無音化してから基準音量へ戻す。
        // file初期化中だけ旧音源が大きくなる過渡を作らず、A/B側はload後に対象側の値を明示適用する。
        audioPlayer?.pause()
        clearLoudnessMatch()
        resetParadeSignal(reason: .trackLoadStarted, isPlaying: false)
        remoteLibrary = library
        if let context {
            switch context {
            case .library:
                library.activePlaylistID = nil
            case .playlist(let playlistID):
                library.activePlaylistID = playlistID
            }
        }

        do {
            try configureAudioSession()
            let fileURL = library.fileURL(for: track)
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.volume = effectiveVolume
            player.isMeteringEnabled = true
            player.prepareToPlay()

            audioPlayer = player
            currentTrack = track
            duration = player.duration
            elapsedTime = 0
            hasRecordedPlaybackEvent = false
            playbackErrorMessage = nil
            wasPlayingBeforeInterruption = false
            interruptionDepth = 0
            library.select(track)
            updateNowPlaying()

            if autoplay {
                play()
            } else {
                transitionToPausedStateAfterLoad()
            }
        } catch {
            pause()
            playbackErrorMessage = "\(track.title) could not be played: \(error.localizedDescription)"
            resetParadeSignal(reason: .loadFailure, isPlaying: false)
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    /// 再生中の曲と再生位置を触らずに、次曲/前曲の文脈(行列/巻物)だけを
    /// 見えているスコープへ合わせる。同じ曲の行タップは load でやり直さず
    /// これで文脈だけ引き継ぐ(頭出しバグの回避)。
    func adoptContext(_ context: PlaybackContext, from library: AudioLibraryStore) {
        remoteLibrary = library
        switch context {
        case .library:
            library.activePlaylistID = nil
        case .playlist(let playlistID):
            library.activePlaylistID = playlistID
        }
    }

    func play() {
        guard let audioPlayer else {
            playbackErrorMessage = "No track is loaded yet."
            resetParadeSignal(reason: .playFailure, isPlaying: false)
            return
        }
        guard audioPlayer.play() else {
            playbackErrorMessage = "Playback could not start."
            isPlaying = false
            stopTimer()
            stopMetering()
            resetParadeSignal(reason: .playFailure, isPlaying: false)
            updateNowPlaying()
            return
        }
        playbackErrorMessage = nil
        isPlaying = true
        startTimer()
        startMetering()
        updateNowPlaying()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
        stopMetering()
        resetParadeSignal(reason: .pause, isPlaying: false)
        syncProgress()
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
        resetParadeSignal(reason: .seek, isPlaying: isPlaying)
        audioPlayer.currentTime = min(max(time, 0), audioPlayer.duration)
        syncProgress()
        updateNowPlaying()
    }

    func playNext() {
        guard let library = remoteLibrary, let track = library.nextTrack(after: currentTrack) else { return }
        load(track, from: library, autoplay: true)
    }

    func playPrevious() {
        guard let library = remoteLibrary, let track = library.previousTrack(before: currentTrack) else { return }
        load(track, from: library, autoplay: true)
    }

    func playMostRecent(from library: AudioLibraryStore) {
        guard let track = library.mostRecentTrack() else { return }
        load(track, from: library, autoplay: true, context: .library)
    }

    func stopForDeletedTrack(_ track: AudioTrack) {
        guard currentTrack?.id == track.id else { return }
        clearLoudnessMatch()
        audioPlayer?.stop()
        audioPlayer = nil
        currentTrack = nil
        isPlaying = false
        elapsedTime = 0
        duration = 0
        playbackErrorMessage = nil
        wasPlayingBeforeInterruption = false
        interruptionDepth = 0
        stopTimer()
        stopMetering()
        resetParadeSignal(reason: .stop, isPlaying: false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func refreshCurrentTrackMetadata(_ track: AudioTrack) {
        guard currentTrack?.id == track.id else { return }
        currentTrack = track
        updateNowPlaying()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
    }

    private func applyEffectiveVolume() {
        audioPlayer?.volume = effectiveVolume
    }

    private func startTimer() {
        stopTimer()
        // .commonモードで登録 — スクロール中も進行表示が止まらないように
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startMetering() {
        stopMetering()
        // .commonモードで登録 — スクロール中も提灯と妖怪が音に付いてくるように
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeter()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateMeter() {
        guard isPlaying else { return }
        let sampledAt = ProcessInfo.processInfo.systemUptime
        guard let audioPlayer, audioPlayer.numberOfChannels > 0 else {
            paradeSignals.ingest(level: nil, isPlaying: isPlaying, sampledAt: sampledAt)
            return
        }
        audioPlayer.updateMeters()
        // 片チャンネルが無音のステレオ音源でも反応するよう、全チャンネルの最大値を取る
        var decibels = -160.0
        for channel in 0..<audioPlayer.numberOfChannels {
            let channelPower = Double(audioPlayer.averagePower(forChannel: channel))
            guard channelPower.isFinite else {
                paradeSignals.ingest(level: nil, isPlaying: isPlaying, sampledAt: sampledAt)
                return
            }
            decibels = max(decibels, channelPower)
        }
        let normalized = min(max((decibels + 48) / 48, 0), 1)
        // 立ち上がりは速く、引きはゆっくり — 提灯の火のように
        if normalized > smoothedAudioLevel {
            smoothedAudioLevel = smoothedAudioLevel * 0.35 + normalized * 0.65
        } else {
            smoothedAudioLevel = smoothedAudioLevel * 0.82 + normalized * 0.18
        }
        paradeSignals.ingest(level: smoothedAudioLevel, isPlaying: isPlaying, sampledAt: sampledAt)
    }

    private func resetParadeSignal(reason: ParadeSignalResetReason, isPlaying: Bool) {
        smoothedAudioLevel = 0
        paradeSignals.reset(reason: reason, isPlaying: isPlaying)
    }

    private func tick() {
        syncProgress()
        recordPlaybackEventIfNeeded()
        if let audioPlayer, !audioPlayer.isPlaying, isPlaying {
            if elapsedTime >= max(duration - 0.25, 0) {
                recordPlaybackEventIfNeeded(didFinish: true)
                playNext()
            } else {
                pause()
            }
        }
    }

    /// 再生イベント(半分以上の再生または完走)を、ロードごとに一度だけ統計へ記録する。
    private func recordPlaybackEventIfNeeded(didFinish: Bool = false) {
        guard !hasRecordedPlaybackEvent, let currentTrack else { return }
        let passedHalf = duration > 0 && elapsedTime >= duration / 2
        guard didFinish || passedHalf else { return }
        hasRecordedPlaybackEvent = true
        remoteLibrary?.recordPlayback(for: currentTrack.id)
    }

    private func syncProgress() {
        elapsedTime = audioPlayer?.currentTime ?? 0
        duration = audioPlayer?.duration ?? duration
    }

    private func transitionToPausedStateAfterLoad() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
        stopMetering()
        syncProgress()
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        let nowPlayingArtist: String
        if let artist = currentTrack.artist?.trimmingCharacters(in: .whitespacesAndNewlines), !artist.isEmpty {
            nowPlayingArtist = artist
        } else {
            nowPlayingArtist = "Yagyo Player"
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: nowPlayingArtist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsedTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]

        if let artworkImage = UIImage(named: "DefaultArtwork") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in artworkImage }
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private static func timeText(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
