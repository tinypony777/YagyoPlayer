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
            audioPlayer?.volume = volume
        }
    }

    /// いま鳴っている音の大きさ(0...1)。夜行絵巻の妖怪や提灯がこれに反応する。
    @Published private(set) var audioLevel: Double = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var meterTimer: Timer?
    private var remoteCommandsInstalled = false
    private weak var remoteLibrary: AudioLibraryStore?

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
            player.volume = volume
            player.isMeteringEnabled = true
            player.prepareToPlay()

            audioPlayer = player
            currentTrack = track
            duration = player.duration
            elapsedTime = 0
            library.select(track)
            updateNowPlaying()

            if autoplay {
                play()
            } else {
                transitionToPausedStateAfterLoad()
            }
        } catch {
            pause()
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let audioPlayer else { return }
        audioPlayer.play()
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
        syncProgress()
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        guard let audioPlayer else { return }
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
        audioPlayer?.stop()
        audioPlayer = nil
        currentTrack = nil
        isPlaying = false
        elapsedTime = 0
        duration = 0
        stopTimer()
        stopMetering()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
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
        audioLevel = 0
    }

    private func updateMeter() {
        guard let audioPlayer, isPlaying, audioPlayer.numberOfChannels > 0 else { return }
        audioPlayer.updateMeters()
        // 片チャンネルが無音のステレオ音源でも反応するよう、全チャンネルの最大値を取る
        var decibels = -160.0
        for channel in 0..<audioPlayer.numberOfChannels {
            decibels = max(decibels, Double(audioPlayer.averagePower(forChannel: channel)))
        }
        let normalized = min(max((decibels + 48) / 48, 0), 1)
        // 立ち上がりは速く、引きはゆっくり — 提灯の火のように
        if normalized > audioLevel {
            audioLevel = audioLevel * 0.35 + normalized * 0.65
        } else {
            audioLevel = audioLevel * 0.82 + normalized * 0.18
        }
    }

    private func tick() {
        syncProgress()
        if let audioPlayer, !audioPlayer.isPlaying, isPlaying {
            if elapsedTime >= max(duration - 0.25, 0) {
                playNext()
            } else {
                pause()
            }
        }
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

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: "Yagyo Player",
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
