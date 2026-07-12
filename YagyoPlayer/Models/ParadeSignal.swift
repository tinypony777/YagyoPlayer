import Foundation

struct ParadeSignalConfiguration: Equatable, Sendable {
    let quietEnterLevel: Double
    let quietExitLevel: Double
    let quietDwell: TimeInterval
    let strongMinimumLevel: Double
    let strongBaselineDelta: Double
    let baselineTimeConstant: TimeInterval
    let strongCooldown: TimeInterval
    let strongRearmLevel: Double
    let strongRearmDelta: Double
    let anticipateDuration: TimeInterval
    let openDuration: TimeInterval
    let recoverDuration: TimeInterval
    let warmupDuration: TimeInterval
    let maximumSampleGap: TimeInterval

    static let production = Self(
        quietEnterLevel: 0.08, quietExitLevel: 0.14, quietDwell: 0.70,
        strongMinimumLevel: 0.55, strongBaselineDelta: 0.18,
        baselineTimeConstant: 0.80, strongCooldown: 0.45,
        strongRearmLevel: 0.32, strongRearmDelta: 0.06,
        anticipateDuration: 0.07, openDuration: 0.27,
        recoverDuration: 0.20, warmupDuration: 0.30,
        maximumSampleGap: 0.50
    )
}

struct ParadeSignalInput: Equatable, Sendable {
    let isPlaying: Bool
    let level: Double?
    let sampledAt: TimeInterval
}

struct ParadeSignalSnapshot: Equatable, Sendable {
    enum Activity: Equatable, Sendable { case stopped, unavailable, quietProxy, normal }
    enum StrongPhase: Equatable, Sendable { case inactive, anticipate, open, recover }
    enum LevelBand: Equatable, Sendable { case unavailable, low, medium, high }

    fileprivate(set) var level: Double = 0
    fileprivate(set) var activity: Activity = .stopped
    fileprivate(set) var strongPhase: StrongPhase = .inactive
    fileprivate(set) var strongSequence: UInt64 = 0

    static func preview(
        activity: Activity,
        level: Double? = nil,
        strongPhase: StrongPhase = .inactive,
        strongSequence: UInt64 = 0
    ) -> Self {
        let defaultLevel: Double
        switch activity {
        case .stopped, .unavailable:
            defaultLevel = 0
        case .quietProxy:
            defaultLevel = 0.05
        case .normal:
            defaultLevel = 0.5
        }

        let resolvedLevel = level.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil } ?? defaultLevel
        return Self(
            level: resolvedLevel,
            activity: activity,
            strongPhase: strongPhase,
            strongSequence: strongSequence
        )
    }

    var levelBand: LevelBand {
        guard activity != .unavailable else { return .unavailable }
        if level < 0.20 { return .low }
        if level < 0.65 { return .medium }
        return .high
    }

    func accessibilityValue(residentName: String?, isUshimitsu: Bool) -> String {
        let stateDescription: String
        switch activity {
        case .stopped:
            stateDescription = "一時停止"
        case .unavailable:
            stateDescription = "再生中、音量表示を利用できません"
        case .quietProxy:
            stateDescription = "再生中、音量は低め"
        case .normal where strongPhase != .inactive:
            stateDescription = "再生中、音量が強く上昇"
        case .normal:
            switch levelBand {
            case .unavailable:
                stateDescription = "再生中、音量表示を利用できません"
            case .low:
                stateDescription = "再生中、音量は低め"
            case .medium:
                stateDescription = "再生中、音量は中くらい"
            case .high:
                stateDescription = "再生中、音量は高め"
            }
        }

        var parts = [stateDescription]
        if let residentName, !residentName.isEmpty {
            parts.append("先導は\(residentName)")
        }
        if isUshimitsu {
            parts.append("丑三つ時")
        }
        return parts.joined(separator: "、")
    }
}

struct ParadeSignalReducer: Sendable {
    let configuration: ParadeSignalConfiguration
    private(set) var snapshot = ParadeSignalSnapshot()

    private var baseline: Double?
    private var lastSampleAt: TimeInterval?
    private var quietCandidateAt: TimeInterval?
    private var warmupUntil: TimeInterval?
    private var strongStartedAt: TimeInterval?
    private var lastStrongAt: TimeInterval?
    private var strongArmed = false

    init(configuration: ParadeSignalConfiguration = .production) {
        self.configuration = configuration
    }

    mutating func ingest(_ input: ParadeSignalInput) -> ParadeSignalSnapshot {
        guard input.isPlaying else {
            return reset(isPlaying: false)
        }

        guard let rawLevel = input.level, rawLevel.isFinite else {
            return reset(isPlaying: true)
        }

        let level = min(max(rawLevel, 0), 1)
        let now = input.sampledAt

        guard let lastSampleAt, let baseline else {
            return seed(level: level, sampledAt: now)
        }

        let deltaTime = now - lastSampleAt
        guard deltaTime >= 0, deltaTime <= configuration.maximumSampleGap else {
            return seed(level: level, sampledAt: now)
        }

        snapshot.level = level
        updateQuietActivity(level: level, sampledAt: now)

        let baselineDelta = level - baseline
        updateStrongState(level: level, baselineDelta: baselineDelta, sampledAt: now)

        let alpha = 1 - exp(-deltaTime / configuration.baselineTimeConstant)
        self.baseline = baseline + alpha * baselineDelta
        self.lastSampleAt = now

        return snapshot
    }

    mutating func reset(isPlaying: Bool) -> ParadeSignalSnapshot {
        clearTemporalState()
        snapshot.level = 0
        snapshot.activity = isPlaying ? .unavailable : .stopped
        snapshot.strongPhase = .inactive
        return snapshot
    }

    private mutating func seed(level: Double, sampledAt now: TimeInterval) -> ParadeSignalSnapshot {
        clearTemporalState()
        baseline = level
        lastSampleAt = now
        quietCandidateAt = level <= configuration.quietEnterLevel ? now : nil
        warmupUntil = now + configuration.warmupDuration

        snapshot.level = level
        snapshot.activity = .normal
        snapshot.strongPhase = .inactive
        return snapshot
    }

    private mutating func updateQuietActivity(level: Double, sampledAt now: TimeInterval) {
        if snapshot.activity == .quietProxy {
            if level >= configuration.quietExitLevel {
                quietCandidateAt = nil
                snapshot.activity = .normal
            }
            return
        }

        snapshot.activity = .normal
        guard level <= configuration.quietEnterLevel else {
            quietCandidateAt = nil
            return
        }

        let candidateAt = quietCandidateAt ?? now
        quietCandidateAt = candidateAt
        if now - candidateAt >= configuration.quietDwell {
            snapshot.activity = .quietProxy
        }
    }

    private mutating func updateStrongState(
        level: Double,
        baselineDelta: Double,
        sampledAt now: TimeInterval
    ) {
        let warmupFinished = warmupUntil.map { now >= $0 } ?? true
        let cooldownFinished = lastStrongAt.map { now - $0 >= configuration.strongCooldown } ?? true

        if !strongArmed,
           warmupFinished,
           cooldownFinished,
           level <= configuration.strongRearmLevel || baselineDelta <= configuration.strongRearmDelta {
            strongArmed = true
        }

        if strongArmed,
           level >= configuration.strongMinimumLevel,
           baselineDelta >= configuration.strongBaselineDelta {
            snapshot.strongSequence += 1
            strongStartedAt = now
            lastStrongAt = now
            strongArmed = false
        }

        updateStrongPhase(sampledAt: now)
    }

    private mutating func updateStrongPhase(sampledAt now: TimeInterval) {
        guard let strongStartedAt else {
            snapshot.strongPhase = .inactive
            return
        }

        let elapsed = now - strongStartedAt
        let openStartedAt = configuration.anticipateDuration
        let recoverStartedAt = openStartedAt + configuration.openDuration
        let finishedAt = recoverStartedAt + configuration.recoverDuration

        switch elapsed {
        case ..<openStartedAt:
            snapshot.strongPhase = .anticipate
        case ..<recoverStartedAt:
            snapshot.strongPhase = .open
        case ..<finishedAt:
            snapshot.strongPhase = .recover
        default:
            snapshot.strongPhase = .inactive
            self.strongStartedAt = nil
        }
    }

    private mutating func clearTemporalState() {
        baseline = nil
        lastSampleAt = nil
        quietCandidateAt = nil
        warmupUntil = nil
        strongStartedAt = nil
        lastStrongAt = nil
        strongArmed = false
    }
}
