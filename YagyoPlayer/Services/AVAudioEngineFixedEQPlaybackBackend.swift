import AVFoundation
import Foundation
import Synchronization

enum AVAudioEngineFixedEQPlaybackBackendError: LocalizedError, Equatable {
    case unsupportedChannelCount(Int)
    case invalidSampleRate
    case emptyAudioFile
    case audioFileTooLong
    case customAudioUnitUnavailable
    case invalidPreviewRecipe
    case controlMailboxFull
    case invalidSeekPosition

    var errorDescription: String? {
        switch self {
        case .unsupportedChannelCount(let count):
            return "Fixed EQ preview supports mono or stereo audio, not \(count) channels."
        case .invalidSampleRate:
            return "The audio file has an invalid sample rate."
        case .emptyAudioFile:
            return "The audio file does not contain playable frames."
        case .audioFileTooLong:
            return "The audio file is too long for the Fixed EQ preview scheduler."
        case .customAudioUnitUnavailable:
            return "The Fixed EQ audio unit could not be created."
        case .invalidPreviewRecipe:
            return "The Fixed EQ preview recipe failed its safety contract."
        case .controlMailboxFull:
            return "Fixed EQ is still applying an earlier request. Please try again."
        case .invalidSeekPosition:
            return "The requested playback position is invalid."
        }
    }
}

/// Explicit iOS 27 device-preview path. The production/release default remains the
/// AVAudioPlayer adapter until device evidence and release-SDK verification exist.
///
/// Graph topology is fixed for the lifetime of a loaded track:
/// AVAudioPlayerNode -> FixedEQAudioUnit -> main mixer -> output.
@MainActor
@available(iOS 27.0, *)
final class AVAudioEngineFixedEQPlaybackBackend: AudioPlaybackBackend, FixedEQAuditionControlling {
    static let previewTransitionFrameCount = 256

    private static let previewRecipe = FixedEQRecipe(
        id: "step3-outline-preview-v1",
        catalogVersion: 1,
        inputHeadroomDB: -1,
        bands: [
            FixedEQBand(frequencyHz: 180, gainDB: -0.8, q: 0.8),
            FixedEQBand(frequencyHz: 1_800, gainDB: 1, q: 0.9),
            FixedEQBand(frequencyHz: 7_500, gainDB: -0.6, q: 0.8),
        ],
        outputTrimDB: 0
    )

    private let transitionFrameCount: Int
    private var graph: PreviewGraph?
    private var scheduleGeneration: UInt64 = 0
    private var dspGeneration: UInt64 = 0
    private var storedOutputVolume: Float = 0.88

    private(set) var currentSchedule: PlaybackScheduleIdentity?

    init(transitionFrameCount: Int = previewTransitionFrameCount) {
        self.transitionFrameCount = transitionFrameCount
    }

    var duration: TimeInterval {
        guard let graph else { return 0 }
        return Double(graph.file.length) / graph.sampleRate
    }

    var position: TimeInterval {
        guard let graph else { return 0 }
        return Double(graph.currentPlaybackFrame()) / graph.sampleRate
    }

    var isPlaying: Bool {
        guard let graph else { return false }
        return graph.playbackRequested
            && !graph.isPlaybackComplete
            && graph.player.isPlaying
    }

    var outputVolume: Float {
        get { storedOutputVolume }
        set {
            storedOutputVolume = newValue
            graph?.engine.mainMixerNode.outputVolume = newValue
        }
    }

    var fixedEQAuditionState: FixedEQAuditionState {
        guard let graph else { return .waitingForTrack }
        synchronizeDSPTelemetry(in: graph)

        let telemetry = graph.fixedEQ.renderTelemetry
        let isSwitching = graph.playbackRequested
            && (
                graph.pendingSelectionNeedsEnqueue
                    || graph.appliedMode != graph.requestedMode
                    || telemetry.transitionState.isTransitioning
            )
        let appliesOnNextPlay = !graph.playbackRequested
            && (
                graph.pendingSelectionNeedsEnqueue
                    || graph.appliedMode != graph.requestedMode
                    || !graph.requestModes.isEmpty
            )
        return FixedEQAuditionState(
            availability: .ready,
            requestedMode: graph.requestedMode,
            appliedMode: graph.appliedMode,
            isSwitching: isSwitching,
            appliesOnNextPlay: appliesOnNextPlay,
            failureMessage: graph.dspFailureMessage
        )
    }

    func load(url: URL, trackID: AudioTrack.ID) throws {
        let candidate = try makeGraph(url: url, trackID: trackID, startingFrame: 0)

        let priorGraph = graph
        graph = candidate
        priorGraph?.shutdown()
        advanceSchedule(for: trackID)
    }

    func play() throws {
        guard let graph else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }

        synchronizeDSPTelemetry(in: graph)
        if graph.isPlaybackComplete {
            graph.schedule(from: 0)
        }
        if graph.pendingSelectionNeedsEnqueue {
            // A route change may stop the engine while leaving a queued request in
            // the SPSC mailbox. Start the silent graph first so render can drain it;
            // the player remains paused until the newest selection is committed.
            if !graph.engine.isRunning {
                try graph.engine.start()
            }
            try enqueue(graph.requestedMode, in: graph)
            graph.pendingSelectionNeedsEnqueue = false
        }
        if !graph.engine.isRunning {
            try graph.engine.start()
        }
        graph.player.play()
        graph.playbackRequested = true
    }

    func pause() {
        guard let graph else { return }
        graph.fallbackFrame = graph.currentPlaybackFrame()
        graph.player.pause()
        graph.playbackRequested = false
        graph.meter.reset()
        synchronizeDSPTelemetry(in: graph)
    }

    func seek(to seconds: TimeInterval) throws {
        guard let graph else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }
        guard seconds.isFinite else {
            throw AVAudioEngineFixedEQPlaybackBackendError.invalidSeekPosition
        }

        let clampedSeconds = min(max(seconds, 0), duration)
        let frame = min(
            AVAudioFramePosition((clampedSeconds * graph.sampleRate).rounded(.towardZero)),
            graph.file.length
        )
        let shouldResume = graph.playbackRequested && !graph.isPlaybackComplete

        // Starting a route-recovered engine is the only throwing operation. Do it
        // before mutating the committed schedule so seek remains failure-atomic.
        if shouldResume, !graph.engine.isRunning {
            try graph.engine.start()
        }

        // Deliberately keep render-owned IIR history continuous here. A strict
        // post-seek reset needs an asynchronous render-boundary barrier; calling
        // AUAudioUnit.reset while this engine runs would race the render callback.
        graph.schedule(from: frame)
        if shouldResume, frame < graph.file.length {
            graph.player.play()
            graph.playbackRequested = true
        } else {
            graph.playbackRequested = false
        }
        advanceSchedule(for: graph.trackID)
    }

    func stop() {
        graph?.shutdown()
        graph = nil
        scheduleGeneration &+= 1
        currentSchedule = nil
    }

    func normalizedMeterLevel() -> Double? {
        guard let graph else { return nil }
        synchronizeDSPTelemetry(in: graph)
        return graph.meter.normalizedLevel
    }

    func requestFixedEQAuditionMode(_ mode: FixedEQAuditionMode) throws {
        guard let graph else {
            throw AudioPlaybackBackendError.noTrackLoaded
        }
        synchronizeDSPTelemetry(in: graph)

        if graph.playbackRequested {
            guard mode != graph.requestedMode || graph.dspFailureMessage != nil else {
                return
            }
            try enqueue(mode, in: graph)
            graph.requestedMode = mode
            graph.pendingSelectionNeedsEnqueue = false
        } else {
            graph.requestedMode = mode
            // A request already queued just before pause cannot be removed. Publish
            // the latest choice immediately before the next play so newest wins.
            graph.pendingSelectionNeedsEnqueue = true
        }
    }

    func resetFixedEQAudition() throws {
        guard let graph else { return }
        synchronizeDSPTelemetry(in: graph)
        let needsOriginal = graph.requestedMode != .original
            || graph.appliedMode != .original
            || graph.pendingSelectionNeedsEnqueue
            || !graph.requestModes.isEmpty
            || graph.dspFailureMessage != nil
        guard needsOriginal else { return }

        graph.requestedMode = .original
        if graph.playbackRequested {
            do {
                try enqueue(.original, in: graph)
                graph.pendingSelectionNeedsEnqueue = false
            } catch {
                // A route safety request must never leave Fixed EQ audible when its
                // Original command cannot be committed. Preserve the exact schedule,
                // pause it, and retry Original before the next explicit play.
                pause()
                graph.pendingSelectionNeedsEnqueue = true
                throw error
            }
        } else {
            // Preserve the current render schedule. `play()` publishes this newest
            // choice immediately before resuming, superseding any pre-pause request.
            graph.pendingSelectionNeedsEnqueue = true
        }
    }

    private func makeGraph(
        url: URL,
        trackID: AudioTrack.ID,
        startingFrame: AVAudioFramePosition
    ) throws -> PreviewGraph {
        let file = try AVAudioFile(
            forReading: url,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        guard (1...2).contains(channelCount) else {
            throw AVAudioEngineFixedEQPlaybackBackendError.unsupportedChannelCount(channelCount)
        }
        guard format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw AVAudioEngineFixedEQPlaybackBackendError.invalidSampleRate
        }
        guard file.length > 0 else {
            throw AVAudioEngineFixedEQPlaybackBackendError.emptyAudioFile
        }
        guard file.length <= AVAudioFramePosition(AVAudioFrameCount.max) else {
            throw AVAudioEngineFixedEQPlaybackBackendError.audioFileTooLong
        }

        FixedEQAudioUnit.registerComponent()
        let effect = AVAudioUnitEffect(
            audioComponentDescription: FixedEQAudioUnit.componentDescription
        )
        guard let fixedEQ = effect.auAudioUnit as? FixedEQAudioUnit else {
            throw AVAudioEngineFixedEQPlaybackBackendError.customAudioUnitUnavailable
        }
        // This must precede attach/prepare because either may allocate render resources.
        // Failure aborts graph construction; there is no silent zero-frame fallback.
        try fixedEQ.configureTransition(frameCount: transitionFrameCount)

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let meter = PreviewMeterState(channelCount: channelCount)
        let completion = PreviewCompletionState()
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = storedOutputVolume

        player.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeMeterTap(for: meter)
        )

        let candidate = PreviewGraph(
            engine: engine,
            player: player,
            effect: effect,
            fixedEQ: fixedEQ,
            file: file,
            trackID: trackID,
            meter: meter,
            completion: completion
        )
        candidate.tapIsInstalled = true
        candidate.schedule(from: startingFrame)
        engine.prepare()
        return candidate
    }

    /// Construct outside MainActor isolation. AVAudioEngine invokes this block on its
    /// realtime messenger queue, so an inherited actor executor check would trap.
    private nonisolated static func makeMeterTap(
        for meter: PreviewMeterState
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            meter.ingest(buffer)
        }
    }

    private func enqueue(_ mode: FixedEQAuditionMode, in graph: PreviewGraph) throws {
        let generation = dspGeneration &+ 1
        let snapshot: FixedEQSnapshot
        switch mode {
        case .original:
            snapshot = .original(generation: generation)
        case .fixedEQ:
            snapshot = FixedEQSnapshotFactory.make(
                recipe: Self.previewRecipe,
                sampleRate: graph.sampleRate,
                generation: generation
            )
            guard snapshot.mode == .processed else {
                throw AVAudioEngineFixedEQPlaybackBackendError.invalidPreviewRecipe
            }
        }
        guard graph.fixedEQ.enqueue(snapshot) else {
            throw AVAudioEngineFixedEQPlaybackBackendError.controlMailboxFull
        }

        dspGeneration = generation
        graph.requestModes[generation] = mode
    }

    private func synchronizeDSPTelemetry(in graph: PreviewGraph) {
        let telemetry = graph.fixedEQ.renderTelemetry

        if let generation = telemetry.appliedGeneration,
           generation != graph.lastObservedAppliedGeneration {
            graph.lastObservedAppliedGeneration = generation
            if let mode = graph.requestModes[generation] {
                graph.appliedMode = mode
            }
            graph.requestModes = graph.requestModes.filter { $0.key > generation }
        }

        if telemetry.fault != .none || telemetry.status != 0 {
            graph.appliedMode = .original
            graph.dspFailureMessage = "Fixed EQ returned to Original after a render fault."
        } else if telemetry.processResult == .latchedOriginal
            || telemetry.processResult == .invalidBuffers
            || telemetry.isOriginalLatched {
            graph.appliedMode = .original
            graph.dspFailureMessage = "Fixed EQ returned to Original to protect playback."
        } else if let generation = telemetry.appliedGeneration,
                  generation == graph.lastObservedAppliedGeneration {
            graph.dspFailureMessage = nil
        }
    }

    private func advanceSchedule(for trackID: AudioTrack.ID) {
        scheduleGeneration &+= 1
        currentSchedule = PlaybackScheduleIdentity(
            trackID: trackID,
            generation: scheduleGeneration
        )
    }
}

@MainActor
private final class PreviewGraph {
    let engine: AVAudioEngine
    let player: AVAudioPlayerNode
    let effect: AVAudioUnitEffect
    let fixedEQ: FixedEQAudioUnit
    let file: AVAudioFile
    let trackID: AudioTrack.ID
    let meter: PreviewMeterState
    let completion: PreviewCompletionState

    var scheduledStartFrame: AVAudioFramePosition = 0
    var fallbackFrame: AVAudioFramePosition = 0
    var scheduleToken: UInt64 = 0
    var playbackRequested = false
    var tapIsInstalled = false

    var requestedMode: FixedEQAuditionMode = .original
    var appliedMode: FixedEQAuditionMode = .original
    var pendingSelectionNeedsEnqueue = false
    var requestModes: [UInt64: FixedEQAuditionMode] = [:]
    var lastObservedAppliedGeneration: UInt64?
    var dspFailureMessage: String?

    var sampleRate: Double { file.processingFormat.sampleRate }

    var isPlaybackComplete: Bool {
        completion.isFinished(token: scheduleToken)
    }

    init(
        engine: AVAudioEngine,
        player: AVAudioPlayerNode,
        effect: AVAudioUnitEffect,
        fixedEQ: FixedEQAudioUnit,
        file: AVAudioFile,
        trackID: AudioTrack.ID,
        meter: PreviewMeterState,
        completion: PreviewCompletionState
    ) {
        self.engine = engine
        self.player = player
        self.effect = effect
        self.fixedEQ = fixedEQ
        self.file = file
        self.trackID = trackID
        self.meter = meter
        self.completion = completion
    }

    func schedule(from requestedFrame: AVAudioFramePosition) {
        let frame = min(max(requestedFrame, 0), file.length)
        player.stop()
        meter.reset()
        scheduleToken &+= 1
        let token = scheduleToken
        completion.begin(token: token)
        scheduledStartFrame = frame
        fallbackFrame = frame

        let remaining = file.length - frame
        guard remaining > 0 else {
            completion.finish(token: token)
            return
        }
        player.scheduleSegment(
            file,
            startingFrame: frame,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack,
            completionHandler: Self.makeCompletionHandler(
                completion: completion,
                token: token
            )
        )
    }

    /// Player completion is not delivered on MainActor.
    private nonisolated static func makeCompletionHandler(
        completion: PreviewCompletionState,
        token: UInt64
    ) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { _ in
            completion.finish(token: token)
        }
    }

    func currentPlaybackFrame() -> AVAudioFramePosition {
        if isPlaybackComplete {
            fallbackFrame = file.length
            return file.length
        }
        guard playbackRequested,
              let renderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: renderTime) else {
            return fallbackFrame
        }
        let renderedFrames = max(playerTime.sampleTime, 0)
        fallbackFrame = min(scheduledStartFrame + renderedFrames, file.length)
        return fallbackFrame
    }

    func shutdown() {
        playbackRequested = false
        player.stop()
        // Stop render callbacks before removing their tap storage or releasing the AU.
        engine.stop()
        if tapIsInstalled {
            player.removeTap(onBus: 0)
            tapIsInstalled = false
        }
        meter.reset()
    }
}

/// The tap performs fixed loops and one relaxed atomic store only. Conversion to dB
/// stays on the control side in `normalizedLevel`.
private final class PreviewMeterState: @unchecked Sendable {
    private let channelCount: Int
    private let meanSquareBits = Atomic<UInt32>(Float.zero.bitPattern)

    init(channelCount: Int) {
        self.channelCount = channelCount
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channels = buffer.floatChannelData else {
            reset()
            return
        }

        var sum = 0.0
        var channel = 0
        while channel < channelCount {
            let samples = channels[channel]
            var frame = 0
            while frame < frameCount {
                let sample = Double(samples[frame])
                guard sample.isFinite else {
                    reset()
                    return
                }
                sum += sample * sample
                frame += 1
            }
            channel += 1
        }
        let divisor = Double(frameCount * channelCount)
        let meanSquare = Float(sum / divisor)
        meanSquareBits.store(
            meanSquare.isFinite ? meanSquare.bitPattern : 0,
            ordering: .relaxed
        )
    }

    var normalizedLevel: Double {
        let meanSquare = Float(
            bitPattern: meanSquareBits.load(ordering: .relaxed)
        )
        guard meanSquare.isFinite, meanSquare > 0 else { return 0 }
        let decibels = 10 * log10(Double(meanSquare))
        return min(max((decibels + 48) / 48, 0), 1)
    }

    func reset() {
        meanSquareBits.store(0, ordering: .relaxed)
    }
}

private final class PreviewCompletionState: @unchecked Sendable {
    private let activeToken = Atomic<UInt64>(0)
    private let finishedToken = Atomic<UInt64>(0)

    func begin(token: UInt64) {
        finishedToken.store(0, ordering: .relaxed)
        activeToken.store(token, ordering: .releasing)
    }

    func finish(token: UInt64) {
        guard activeToken.load(ordering: .acquiring) == token else { return }
        finishedToken.store(token, ordering: .releasing)
    }

    func isFinished(token: UInt64) -> Bool {
        token != 0 && finishedToken.load(ordering: .acquiring) == token
    }
}
