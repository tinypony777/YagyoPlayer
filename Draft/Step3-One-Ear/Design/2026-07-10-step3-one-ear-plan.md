# Step 3「一本の耳」Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Replace AVAudioPlayer-only metering with reliable AVAudioEngine playback and one shared, on-device loudness/silence/onset engine whose versioned aggregate results persist in library.json.

**Architecture:** PlaybackController remains the MainActor policy/UI facade and delegates transport to an injectable backend. AVAudioEngine exposes source-format PCM before app volume to a bounded realtime worker, while OfflineTrackAnalyzer reads the stored file in chunks; both own separate instances of the same PerceptionDSPCore. A pinned local libebur128 C target supplies BS.1770 loudness, Accelerate supplies causal onset analysis, and AudioLibraryStore commits only finite, hash/version-bound caches.

**Tech Stack:** Swift 6.0, SwiftUI, AVFoundation/AVFAudio, MediaPlayer, Accelerate, Synchronization atomics, CryptoKit, XCTest, XcodeGen, vendored libebur128 1.2.6.

## Global Constraints

- Deployment target remains iOS 26.0 and SWIFT_VERSION remains 6.0.
- Vendor libebur128 v1.2.6 from commit 67b33abe1558160ed76ada1322329b0e9e058b02 with the complete MIT notice.
- Build must not fetch a remote loudness/DSP package.
- Cache algorithm ID is exactly yagyo-perception-v1-libebur128-1.2.6.
- Scope is Integrated, Momentary, and Short-term loudness, silence, and onset only. Do not add LRA, true peak, beat/tempo/key, section detection, ML classification, or audio processing.
- Playback audio and analysis remain on-device; no audio or results are uploaded.
- The analysis tap observes source-format PCM before user volume. Mono stays mono; labelled LFE maps to EBUR128_UNUSED.
- Supported loudness layouts are mono, stereo, and unambiguously labelled Core Audio 3.0/4.0/5.0/5.1/7.1. Never guess an ambiguous multichannel order.
- The render callback never waits, performs I/O, calls DSP/libebur128, mutates Published state, or creates a Task per buffer.
- Realtime overload drops analysis work, never audio work.
- Load, seek, stop/deletion, graph rebuild, format change, or PCM discontinuity creates a new DSP generation.
- Existing PlaybackController public behavior and Step 1 privacy rules remain compatible.
- AudioTrack.analysis is optional and legacy library.json must decode unchanged.
- No complete onset timestamp or silence-range arrays are persisted.
- All stored/published doubles are finite or nil.
- Every production change follows a witnessed red-green TDD cycle and ends with a focused commit.
- Regenerate and commit YagyoPlayer.xcodeproj/project.pbxproj whenever sources, tests, targets, or dependencies change.
- Do not enable the intentionally manual-only GitHub iOS workflows; Xcode/Simulator and Xcode Cloud remain the gates.

---

## File Structure

### New production files

- Vendor/libebur128/ebur128.c — pinned upstream implementation.
- Vendor/libebur128/ebur128.h — pinned upstream API.
- Vendor/libebur128/COPYING — upstream MIT license.
- Vendor/libebur128/ORIGIN.md — source/tag/commit/date/file hashes.
- Vendor/libebur128/module.modulemap — CEBUR128 Clang module.
- YagyoPlayer/Analysis/AudioPCM.swift — channel roles, format validation, zero-allocation PCM adapter.
- YagyoPlayer/Analysis/AnalysisResults.swift — shared live/offline value types and status.
- YagyoPlayer/Analysis/EBUR128Meter.swift — Swift ownership/error facade over libebur128.
- YagyoPlayer/Analysis/SilenceDetector.swift — versioned hysteresis and duration accounting.
- YagyoPlayer/Analysis/OnsetDetector.swift — causal SuperFlux-style detector.
- YagyoPlayer/Analysis/PerceptionDSPCore.swift — single consume/snapshot/finalize contract.
- YagyoPlayer/Analysis/RealtimePerceptionPipeline.swift — bounded generation-tagged worker.
- YagyoPlayer/Models/AudioAnalysis.swift — persistent cache/request/result values.
- YagyoPlayer/Services/AudioPlaybackBackend.swift — transport interface and schedule identity.
- YagyoPlayer/Services/LegacyAudioPlayerPlaybackBackend.swift — temporary migration backend; deleted in Task 8.
- YagyoPlayer/Services/AudioEnginePlaybackBackend.swift — production AVAudioEngine transport.
- YagyoPlayer/Services/AudioFileHasher.swift — reusable 1 MiB chunk SHA-256.
- YagyoPlayer/Services/OfflineTrackAnalyzer.swift — full-file shared-core caller.
- YagyoPlayer/Services/TrackAnalysisCoordinator.swift — serial utility-priority scheduler.

### New test/support files

- YagyoPlayerTests/TestSupport/FakeAudioPlaybackBackend.swift
- YagyoPlayerTests/Fixtures/PCMFixtureFactory.swift
- YagyoPlayerTests/Fixtures/WAVFixtureWriter.swift
- YagyoPlayerTests/Analysis/LibEBUR128LinkageTests.swift
- YagyoPlayerTests/Analysis/AudioPCMTests.swift
- YagyoPlayerTests/Analysis/EBUR128MeterTests.swift
- YagyoPlayerTests/Analysis/SilenceDetectorTests.swift
- YagyoPlayerTests/Analysis/OnsetDetectorTests.swift
- YagyoPlayerTests/Analysis/PerceptionDSPCoreTests.swift
- YagyoPlayerTests/RealtimePerceptionPipelineTests.swift
- YagyoPlayerTests/AudioEnginePlaybackBackendTests.swift
- YagyoPlayerTests/AudioAnalysisTests.swift
- YagyoPlayerTests/OfflineTrackAnalyzerTests.swift
- YagyoPlayerTests/TrackAnalysisCoordinatorTests.swift
- Package.swift
- Validation/AudioConformanceTests/EBUFixtureManifest.swift
- Validation/AudioConformanceTests/EBUFixtureSHA256.txt
- Validation/AudioConformanceTests/LoudnessConformanceTests.swift

### Existing files modified

- project.yml and regenerated YagyoPlayer.xcodeproj/project.pbxproj
- YagyoPlayer/Services/PlaybackController.swift
- YagyoPlayer/Models/AudioTrack.swift
- YagyoPlayer/Services/AudioLibraryStore.swift
- YagyoPlayer/YagyoPlayerApp.swift
- YagyoPlayer/Views/ContentView.swift
- corresponding existing tests
- README.md, docs/PRODUCT_DIRECTION.md, docs/AUDIO_ANALYSIS_VALIDATION.md

---

### Task 1: Establish the Mac baseline and isolate PlaybackController policy

**Files:**

- Create: YagyoPlayer/Services/AudioPlaybackBackend.swift
- Create temporarily: YagyoPlayer/Services/LegacyAudioPlayerPlaybackBackend.swift
- Create: YagyoPlayer/Analysis/AnalysisResults.swift
- Create: YagyoPlayerTests/TestSupport/FakeAudioPlaybackBackend.swift
- Modify: YagyoPlayer/Services/PlaybackController.swift
- Modify: YagyoPlayerTests/PlaybackControllerTests.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: existing AudioTrack, AudioLibraryStore, PlaybackContext, AVAudioSession/Now Playing policy.
- Produces: RealtimeAnalysisSnapshot, PlaybackScheduleIdentity, AudioPlaybackBackendEvent, AudioPlaybackBackend, deterministic fake backend, unchanged public PlaybackController API.

- [ ] **Step 1: Capture a fresh baseline before source edits**

Run:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -resultBundlePath /tmp/YagyoPlayer-Step3-Baseline.xcresult
~~~

Expected: 34 existing test methods pass. If Xcode Cloud remains error while this local command passes, record it as infrastructure state, not a Step 3 regression.

- [ ] **Step 2: Write failing backend-seam characterization tests**

Add tests with these exact names and assertions:

- testLoadWithoutAutoplaySelectsTrackAndPublishesBackendDuration
- testAutoplayDelegatesPlayAndStartsTimers
- testPlayPauseVolumeAndClampedSeekDelegateToBackend
- testNextAndPreviousWrapWithinLibraryQueue
- testNextUsesActivePlaylistQueue
- testHalfPlayedRecordsStatisticsOnlyOncePerLoad
- testMatchingFinishRecordsOnceAndAdvancesQueue
- testStaleFinishAfterSeekDoesNotAdvanceQueue
- testStaleFinishAfterLoadDoesNotAdvanceQueue
- testStaleFinishAfterStopOrDeletionDoesNotAdvanceQueue
- testStopForDeletedTrackClearsBackendAndPublishedState
- testNowPlayingMirrorsElapsedDurationAndPlaybackRate

Convert existing interruption/route tests to FakeAudioPlaybackBackend so no test skips merely because Simulator audio output is unavailable.

The fake must capture load/play/pause/seek/stop calls and expose:

~~~swift
func emit(_ event: AudioPlaybackBackendEvent)
func suspendRebuild() async
func finishRebuild()
func suspendInterruptionPreparation() async
func finishInterruptionPreparation()
~~~

- [ ] **Step 3: Run the focused tests and witness RED**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/PlaybackControllerTests
~~~

Expected: compile failure because the backend protocol/injecting initializer do not exist.

- [ ] **Step 4: Add the backend contract**

~~~swift
struct PlaybackScheduleIdentity: Equatable, Hashable, Sendable {
    let trackID: AudioTrack.ID
    let generation: UInt64
}

enum AudioPlaybackBackendEvent: Equatable, Sendable {
    case finished(PlaybackScheduleIdentity)
    case engineConfigurationChanged(PlaybackScheduleIdentity)
}

@MainActor
protocol AudioPlaybackBackend: AnyObject {
    var onEvent: (@MainActor @Sendable (AudioPlaybackBackendEvent) -> Void)? { get set }
    var currentSchedule: PlaybackScheduleIdentity? { get }
    var duration: TimeInterval { get }
    var position: TimeInterval { get }
    var isPlaying: Bool { get }
    var volume: Float { get set }

    func load(url: URL, trackID: AudioTrack.ID) throws
    func play() throws
    func pause()
    func seek(to seconds: TimeInterval) throws
    func stop()
    func rebuildAfterConfigurationChange() async throws
    func prepareToResumeAfterInterruption() async throws
    func realtimeAnalysisSnapshot() -> RealtimeAnalysisSnapshot
}
~~~

Create the live value type in this task so the backend seam compiles before the DSP tasks:

~~~swift
struct RealtimeAnalysisSnapshot: Equatable, Sendable {
    let level: Double
    let momentaryLUFS: Double?
    let shortTermLUFS: Double?
    let isSilent: Bool
    let onsetStrength: Double
    let onsetSequence: UInt64
    let droppedAnalysisBlockCount: UInt64
    let hasDiscontinuity: Bool

    static let unavailable = RealtimeAnalysisSnapshot(
        level: 0, momentaryLUFS: nil, shortTermLUFS: nil,
        isSilent: false, onsetStrength: 0, onsetSequence: 0,
        droppedAnalysisBlockCount: 0, hasDiscontinuity: false
    )
}
~~~

Provide a temporary LegacyAudioPlayerPlaybackBackend that wraps the current AVAudioPlayer behavior. Move smoothing to PlaybackController; retain raw max-channel -48...0 dB mapping in the backend.

PlaybackController initializer:

~~~swift
init(
    backend: (any AudioPlaybackBackend)? = nil,
    notificationCenter: NotificationCenter = .default,
    activateAudioSession: @escaping () throws -> Void =
        PlaybackController.activateSystemAudioSession
)
~~~

Add module-internal pollPlaybackState() and pollRealtimeAnalysis() so tests drive time deterministically.

- [ ] **Step 5: Regenerate and verify GREEN**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/PlaybackControllerTests
~~~

Expected: every PlaybackControllerTests case passes with no audio-environment skip.

- [ ] **Step 6: Commit**

~~~bash
git add YagyoPlayer/Services/AudioPlaybackBackend.swift \
  YagyoPlayer/Services/LegacyAudioPlayerPlaybackBackend.swift \
  YagyoPlayer/Analysis/AnalysisResults.swift \
  YagyoPlayer/Services/PlaybackController.swift \
  YagyoPlayerTests/PlaybackControllerTests.swift \
  YagyoPlayerTests/TestSupport/FakeAudioPlaybackBackend.swift \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "refactor: isolate playback controller policy"
~~~

---

### Task 2: Vendor and link libebur128 1.2.6

**Files:**

- Create: Vendor/libebur128/ebur128.c
- Create: Vendor/libebur128/ebur128.h
- Create: Vendor/libebur128/COPYING
- Create: Vendor/libebur128/ORIGIN.md
- Create: Vendor/libebur128/module.modulemap
- Create: YagyoPlayerTests/Analysis/LibEBUR128LinkageTests.swift
- Modify: project.yml
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Produces: importable CEBUR128 module linked to app/test target without remote dependency.

- [ ] **Step 1: Write the failing linkage test**

~~~swift
import XCTest
import CEBUR128

final class LibEBUR128LinkageTests: XCTestCase {
    func testVendoredLibraryReportsPinnedVersion() {
        var major: Int32 = 0
        var minor: Int32 = 0
        var patch: Int32 = 0
        ebur128_get_version(&major, &minor, &patch)
        XCTAssertEqual([major, minor, patch], [1, 2, 6])
    }
}
~~~

- [ ] **Step 2: Run and witness RED**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/LibEBUR128LinkageTests
~~~

Expected RED: no such module CEBUR128.

- [ ] **Step 3: Retrieve only the approved upstream files**

~~~bash
UPSTREAM_DIR="$(mktemp -d /tmp/libebur128.XXXXXX)"
git clone https://github.com/jiixyj/libebur128.git "$UPSTREAM_DIR"
git -C "$UPSTREAM_DIR" checkout 67b33abe1558160ed76ada1322329b0e9e058b02
mkdir -p Vendor/libebur128
cp "$UPSTREAM_DIR/ebur128/ebur128.c" Vendor/libebur128/
cp "$UPSTREAM_DIR/ebur128/ebur128.h" Vendor/libebur128/
cp "$UPSTREAM_DIR/COPYING" Vendor/libebur128/
shasum -a 256 Vendor/libebur128/ebur128.c \
  Vendor/libebur128/ebur128.h Vendor/libebur128/COPYING
~~~

Expected hashes:

- ebur128.c: c2fc562f1088cacab4d21250b6e04996ef36c7694ea901e08cc4d64eb542b78d
- ebur128.h: a988fa03828bcdd6258e6c52300d709a58727272a9ce6cd3fbf351f090517111
- COPYING: d6b4754bb67bdd08b97d5d11b2d7434997a371585a78fe77007149df3af8d09c

ORIGIN.md records upstream URL, tag v1.2.6, full commit, retrieval date 2026-07-10, included files, hashes, and no local source modifications.

module.modulemap:

~~~modulemap
module CEBUR128 {
    header "ebur128.h"
    export *
}
~~~

- [ ] **Step 4: Add the XcodeGen C static-library target**

Add this exact target under targets:

~~~yaml
  CEBUR128:
    type: library.static
    platform: iOS
    deploymentTarget: "26.0"
    sources:
      - path: Vendor/libebur128/ebur128.c
      - path: Vendor/libebur128/ebur128.h
        buildPhase: headers
        headerVisibility: public
    settings:
      base:
        PRODUCT_MODULE_NAME: CEBUR128
        DEFINES_MODULE: YES
        CLANG_ENABLE_MODULES: YES
        MODULEMAP_FILE: "$(SRCROOT)/Vendor/libebur128/module.modulemap"
        HEADER_SEARCH_PATHS:
          - "$(SRCROOT)/Vendor/libebur128"
        PUBLIC_HEADERS_FOLDER_PATH: include/CEBUR128
        SKIP_INSTALL: YES
~~~

Add a linked target dependency, - target: CEBUR128, to both YagyoPlayer and YagyoPlayerTests. The test bundle must link the archive because LibEBUR128LinkageTests calls ebur128_get_version directly. Add - sdk: Accelerate.framework to YagyoPlayer now for Task 4. Do not add a remote package.

- [ ] **Step 5: Regenerate and verify GREEN plus device build**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/LibEBUR128LinkageTests
xcodebuild build \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
~~~

- [ ] **Step 6: Verify deterministic project generation and commit**

~~~bash
cp YagyoPlayer.xcodeproj/project.pbxproj /tmp/yagyo-step3-pbxproj
xcodegen generate
cmp /tmp/yagyo-step3-pbxproj YagyoPlayer.xcodeproj/project.pbxproj
git add Vendor/libebur128 project.yml \
  YagyoPlayer.xcodeproj/project.pbxproj \
  YagyoPlayerTests/Analysis/LibEBUR128LinkageTests.swift
git commit -m "build: vendor libebur128 1.2.6"
~~~

---

### Task 3: Add labelled PCM and the libebur128 Swift facade

**Files:**

- Create: YagyoPlayer/Analysis/AudioPCM.swift
- Create: YagyoPlayer/Analysis/EBUR128Meter.swift
- Create: YagyoPlayerTests/Fixtures/PCMFixtureFactory.swift
- Create: YagyoPlayerTests/Fixtures/WAVFixtureWriter.swift
- Create: YagyoPlayerTests/Analysis/AudioPCMTests.swift
- Create: YagyoPlayerTests/Analysis/EBUR128MeterTests.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: CEBUR128.
- Produces: PCMSourceDescription, AnalysisPCMFormat, AudioChannelRole, AVAudioPCMBufferAdapter, AudioSampleBlock, offline result values, EBUR128Meter.

- [ ] **Step 1: Write failing PCM/channel-map tests**

Cover exact cases:

- mono without layout -> center;
- stereo without layout -> left/right;
- labelled Core Audio 3.0 -> left/right/center;
- labelled MPEG 4.0 -> left/right/center/center-surround and labelled quad/ITU 2.2 -> left/right/left-surround/right-surround;
- labelled Core Audio 5.0 -> left/right/center/left-surround/right-surround;
- labelled 5.1 and 7.1 preserve roles and LFE;
- ambiguous/unlabelled multichannel exposes nil analysisFormat without guessing while PCM copying remains available for live level;
- interleaved Float32 order is unchanged;
- noninterleaved Float32 is interleaved into caller storage;
- a caller-selected source frame range is copied exactly;
- undersized destination rejects;
- repeated copies reuse the same caller-owned storage address; render-path allocation is verified separately with Instruments.

Run:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioPCMTests
~~~

Expected RED: PCMSourceDescription, the adapter, and AudioSampleBlock do not exist.

- [ ] **Step 2: Define the PCM contract**

~~~swift
enum AudioChannelRole: Hashable, Sendable {
    case left, right, center, lfe
    case leftCenter, rightCenter
    case leftSurround, rightSurround
    case leftSurroundDirect, rightSurroundDirect
    case rearSurroundLeft, rearSurroundRight, centerSurround
}

struct PCMSourceDescription: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: Int
    // nil means absent or ambiguous multichannel labels.
    let channelRoles: [AudioChannelRole]?
}

struct AnalysisPCMFormat: Equatable, Sendable {
    let sampleRate: Double
    let channelRoles: [AudioChannelRole]
    var channelCount: Int { channelRoles.count }
    init(sampleRate: Double, channelRoles: [AudioChannelRole]) throws
}

struct AVAudioPCMBufferAdapter: Sendable {
    let sourceDescription: PCMSourceDescription
    let analysisFormat: AnalysisPCMFormat?
    init(format: AVAudioFormat) throws

    // Validated, nonthrowing, allocation-free hot path.
    func copyInterleavedSamples(
        from buffer: AVAudioPCMBuffer,
        sourceFrameOffset: Int,
        frameCount: Int,
        into destination: UnsafeMutableBufferPointer<Float>
    ) -> Bool
}

struct AudioSampleBlock {
    let format: AnalysisPCMFormat
    let frameCount: Int
    let streamStartFrame: Int64
    let interleavedSamples: UnsafeBufferPointer<Float>
}
~~~

AudioSampleBlock is a non-Sendable, synchronous borrowed view. Its sample pointer must not escape consume. Both offline scratch storage and realtime pool slots construct this same value before calling the shared core.

Validate/throw in adapter init whenever possible. Store only immutable numeric format/channel/copy-strategy data; never retain AVAudioFormat, AVAudioChannelLayout, AVAudioPCMBuffer, or a closure. The render-path copy returns false for incompatible range/capacity without constructing an Error. Adapter init accepts Float32 PCM with up to eight channels even when a surround layout is absent or ambiguous; analysisFormat is then nil so playback/raw level still work while loudness/onset and the offline cache become unsupported.

Only these labelled role sequences create AnalysisPCMFormat:

- mono: center;
- stereo: left, right;
- 3.0: left, right, center;
- 4.0 MPEG: left, right, center, centerSurround;
- 4.0 quad/ITU 2.2: left, right, leftSurround, rightSurround;
- 5.0: left, right, center, leftSurround, rightSurround;
- 5.1: left, right, center, lfe, leftSurround, rightSurround;
- unambiguous 7.1 Core Audio variants using left/right/center/lfe plus either leftSurround/rightSurround and leftCenter/rightCenter, or leftSurround/rightSurround and rearSurroundLeft/rearSurroundRight.

Resolve only kAudioChannelLayoutTag_Mono, Stereo, MPEG_3_0_A/B, MPEG_4_0_A/B, Quadraphonic, ITU_2_2, MPEG_5_0_A/B/C/D, MPEG_5_1_A/B/C/D, MPEG_7_1_A/B/C, and AudioUnit_7_1 through their channel descriptions, then require one of the exact role multisets above while preserving source order. Custom descriptions are accepted only when every label maps uniquely and the resulting multiset is identical to one of those layouts. Reject duplicate, unknown, discrete, or ambiguous labels.

Map roles exactly:

| AudioChannelRole | libebur128 channel |
|---|---|
| left | EBUR128_Mp030 |
| right | EBUR128_Mm030 |
| center | EBUR128_Mp000 |
| lfe | EBUR128_UNUSED |
| leftCenter / rightCenter | EBUR128_MpSC / EBUR128_MmSC |
| leftSurround / rightSurround | EBUR128_Mp110 / EBUR128_Mm110 |
| leftSurroundDirect / rightSurroundDirect | EBUR128_Mp090 / EBUR128_Mm090 |
| rearSurroundLeft / rearSurroundRight | EBUR128_Mp135 / EBUR128_Mm135 |
| centerSurround | EBUR128_Mp180 |

Add isolated-channel gain tests for every role, both MPEG and quad/ITU 4.0, and both accepted 7.1 role variants; never infer support merely from channel count.

- [ ] **Step 3: Add offline result types to AnalysisResults**

~~~swift
enum TrackAnalysisStatus: String, Codable, Equatable, Hashable, Sendable {
    case complete, silent, tooShort, unsupported
}

struct OfflineTrackAnalysis: Equatable, Sendable {
    let status: TrackAnalysisStatus
    let integratedLUFS: Double?
    let maximumMomentaryLUFS: Double?
    let maximumShortTermLUFS: Double?
    let analyzedDuration: TimeInterval
    let silentDuration: TimeInterval
    let silentRatio: Double
    let onsetCount: Int
    let meanOnsetRate: Double
}
~~~

- [ ] **Step 4: Write failing loudness facade tests**

Use a 10-second 48 kHz 1 kHz sine at amplitude 0.1. Assert:

- mono/one-sided Integrated: -23.003598632937894 (accuracy 0.01);
- dual-channel Integrated: -19.99329867629808 (accuracy 0.01);
- mono Momentary: -23.00359554324374 (accuracy 0.01);
- mono Short-term: -23.003595543243016 (accuracy 0.01);
- Momentary unavailable before 400 ms;
- Short-term unavailable before 3 seconds;
- LFE-only samples do not change loudness;
- all-zero result is internal negative infinity but external nil;
- identical PCM at chunk sizes 64/257/1024/4096 agrees within 1e-9 LU.

Run:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/EBUR128MeterTests
~~~

Expected RED: EBUR128Meter and LoudnessReading do not exist.

- [ ] **Step 5: Implement EBUR128Meter**

~~~swift
enum LoudnessReading: Equatable {
    case unavailable
    case negativeInfinity
    case finite(Double)
    var externalValue: Double? {
        guard case .finite(let value) = self else { return nil }
        return value
    }
}

final class EBUR128Meter {
    private(set) var consumedFrameCount: Int64 = 0
    init(format: AnalysisPCMFormat) throws
    func addFrames(
        _ interleavedSamples: UnsafeBufferPointer<Float>,
        frameCount: Int
    ) throws
    func momentary() throws -> LoudnessReading
    func shortTerm() throws -> LoudnessReading
    func integrated() throws -> LoudnessReading
}
~~~

Use EBUR128_MODE_I | EBUR128_MODE_S only. Explicitly map every role with ebur128_set_channel; lfe maps to EBUR128_UNUSED. Destroy state in deinit. A successful -HUGE_VAL maps to negativeInfinity; all other error/nonfinite results throw.

- [ ] **Step 6: Run tests, regenerate, and commit**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioPCMTests \
  -only-testing:YagyoPlayerTests/EBUR128MeterTests
git add YagyoPlayer/Analysis \
  YagyoPlayerTests/Analysis/AudioPCMTests.swift \
  YagyoPlayerTests/Analysis/EBUR128MeterTests.swift \
  YagyoPlayerTests/Fixtures \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: add labeled loudness analysis input"
~~~

---

### Task 4: Implement deterministic silence, onset, and PerceptionDSPCore

**Files:**

- Create: YagyoPlayer/Analysis/SilenceDetector.swift
- Create: YagyoPlayer/Analysis/OnsetDetector.swift
- Create: YagyoPlayer/Analysis/PerceptionDSPCore.swift
- Create: YagyoPlayerTests/Analysis/SilenceDetectorTests.swift
- Create: YagyoPlayerTests/Analysis/OnsetDetectorTests.swift
- Create: YagyoPlayerTests/Analysis/PerceptionDSPCoreTests.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: AnalysisPCMFormat, EBUR128Meter, Accelerate.
- Produces: PerceptionDSPProcessing and PerceptionDSPCore used unchanged by live/offline callers.

- [ ] **Step 1: Write failing silence tests**

At 48 kHz assert exact frame accounting:

- -70 LUFS enters and credits 19,200 frames;
- value above -70 does not enter;
- negative infinity enters;
- -65 remains silent;
- value above -65 exits and credits no exit hop;
- each later silent hop credits 4,800 frames;
- all-zero under 400 ms is entirely silent;
- nonzero under 400 ms is not entirely silent;
- final silent frames clamp to analyzed frames.

Run:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/SilenceDetectorTests
~~~

Expected RED: SilenceDetector does not exist.

- [ ] **Step 2: Implement SilenceDetector**

~~~swift
struct SilenceSummary: Equatable {
    let isEntirelySilent: Bool
    let silentFrameCount: Int64
}

struct SilenceDetector {
    private(set) var isSilent = false
    private(set) var silentFrameCount: Int64 = 0
    init(sampleRate: Double)
    mutating func observe(
        momentary: LoudnessReading,
        windowEndFrame: Int64
    )
    func finalize(
        totalFrameCount: Int64,
        allSamplesWereZero: Bool
    ) -> SilenceSummary
}
~~~

Observe on an exact 100 ms grid, first at 400 ms. Entry is <= -70, exit is strictly > -65.

- [ ] **Step 3: Write failing onset tests**

Cover 44.1/48/88.2/96/176.4/192 kHz FFT sizes; silence/steady tone; isolated/repeated impulses with pinned event frame indices/counts; vibrato-like steady tone; LFE-only impulse; energy-preserving non-LFE downmix; one-frame decision delay; a separately testable peak picker accepting synthetic event times exactly 80 ms apart; rejected candidate not moving the anchor; zero-filled history; exact one-second boundary membership; even-count median/MAD; chunk invariance at 64/257/1024/4096 and deterministic random chunks; final partial window discarded.

Run:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/OnsetDetectorTests
~~~

Expected RED: OnsetDetector and OnsetPeakPicker do not exist.

- [ ] **Step 4: Implement causal OnsetDetector exactly**

~~~swift
struct OnsetEvent: Equatable, Sendable {
    let time: TimeInterval
    let strength: Double
    let sequence: UInt64
}

struct OnsetPeakPicker {
    mutating func consider(
        previousPreviousFlux: Double,
        previousFlux: Double,
        currentFlux: Double,
        previousThreshold: Double,
        previousEventTime: TimeInterval
    ) -> Bool
}

final class OnsetDetector {
    init(format: AnalysisPCMFormat) throws
    static func fftSize(for sampleRate: Double) -> Int
    func consume(
        interleavedSamples: UnsafeBufferPointer<Float>,
        frameCount: Int,
        startFrame: Int64
    ) throws
    func snapshot() -> (count: Int, latest: OnsetEvent?)
}
~~~

Exact algorithm:

- downmix non-LFE channels as sum / sqrt(nonLFEChannelCount);
- FFT 2048 at 44.1/48, 4096 at 88.2/96, 8192 at 176.4/192, clamp 512...8192 otherwise;
- hop FFT/4, periodic Hann, raw Accelerate complex magnitude with no 1/N scaling, then log(1 + 1000*magnitude);
- S[n] is mean positive difference against the three-bin-radius maximum of the previous spectrum;
- let N = floor(sampleRate / hopSize); the adaptive history for frame n is the newest N previous flux frames whose centre times are in [centre(n) - 1.0 s, centre(n)), discarding any older qualifying frame and prepending zeros until exactly N entries exist;
- median of an even count is the arithmetic mean of the two central sorted values; MAD uses the same rule over absolute deviations;
- T[n] = max(median + 1.5*MAD, 1e-7);
- decide n-1 once n exists: S[n-1] > T[n-1], S[n-1] > S[n-2], S[n-1] >= S[n];
- event time is centre of n-1;
- accept when at least 80 ms after the last accepted event;
- strength clamp((S-T)/max(T,1e-12),0,1);
- anchor STFT at generation frame zero and discard final partial window.

Pin impulse-fixture expected event frame indices from the reference implementation before production code. Test the exact 80 ms refractory boundary through OnsetPeakPicker's synthetic timestamps rather than assuming an STFT hop grid lands on 80 ms.

- [ ] **Step 5: Write failing shared-core tests**

Cover contiguous start-frame enforcement; status precedence silent -> tooShort -> complete; pinned sine loudness; max-M fixtures whose optimal 400 ms window is shifted by 20 ms; all finite/nil outputs; mono/one-sided stereo; 5.1 LFE exclusion; required sample rates; exact silence/onset aggregate equivalence; loudness within 1e-9 under every chunking; raw level uses max-channel RMS and maps -48...0 to 0...1.

Run:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/PerceptionDSPCoreTests
~~~

Expected RED: PerceptionDSPProcessing and PerceptionDSPCore do not exist.

- [ ] **Step 6: Implement the single shared core**

~~~swift
protocol PerceptionDSPProcessing: AnyObject {
    func consume(_ block: AudioSampleBlock) throws
    func snapshot() -> RealtimeAnalysisSnapshot
    func finalize() throws -> OfflineTrackAnalysis
}

final class PerceptionDSPCore: PerceptionDSPProcessing {
    init(format: AnalysisPCMFormat) throws
    func consume(_ block: AudioSampleBlock) throws
    func snapshot() -> RealtimeAnalysisSnapshot
    func finalize() throws -> OfflineTrackAnalysis
}
~~~

Reject a block whose format differs from the construction format or whose streamStartFrame is not contiguous. Split arbitrary blocks at exact 10 ms boundaries. Internally sample max-M candidates every 10 ms starting at 400 ms so the EBU file-based shifted-window cases are observable, but publish the live Momentary value and feed SilenceDetector only every tenth reading on the approved 100 ms cadence. Query/publish Short-term every 100 ms starting at 3 s. Both live and offline core instances maintain the same internal max-M candidates, so aggregate equivalence is unchanged. Do not retain AudioSampleBlock storage and do not put attack/release smoothing in this core.

- [ ] **Step 7: Run, regenerate, and commit**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/SilenceDetectorTests \
  -only-testing:YagyoPlayerTests/OnsetDetectorTests \
  -only-testing:YagyoPlayerTests/PerceptionDSPCoreTests
git add YagyoPlayer/Analysis \
  YagyoPlayerTests/Analysis \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: add shared perception DSP core"
~~~

---

### Task 5: Add the versioned cache, reusable hashing, and atomic store commit

**Files:**

- Create: YagyoPlayer/Models/AudioAnalysis.swift
- Create: YagyoPlayer/Services/AudioFileHasher.swift
- Create: YagyoPlayerTests/AudioAnalysisTests.swift
- Modify: YagyoPlayer/Models/AudioTrack.swift
- Modify: YagyoPlayer/Services/AudioLibraryStore.swift
- Modify: YagyoPlayerTests/AudioTrackTests.swift
- Modify: YagyoPlayerTests/AudioLibraryStoreTests.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: OfflineTrackAnalysis, existing AudioTrack contentHash, existing atomic library.json persistence.
- Produces: TrackAnalysisCache, TrackAnalysisRequest, TrackAnalysisResult, AudioFileHasher, stale-analysis discovery, atomic commit/rollback.

- [ ] **Step 1: Write failing cache and compatibility tests**

Add these exact cases:

- testLegacyTrackJSONDecodesWithNilAnalysis
- testTrackAnalysisCacheRoundTripsEveryStatus
- testTrackAnalysisCacheRejectsEmptyVersionAndHash
- testTrackAnalysisCacheRejectsNaNAndInfinity
- testTrackAnalysisCacheRejectsNegativeAggregates
- testTrackAnalysisCacheRejectsSilentDurationBeyondAnalyzedDuration
- testTrackAnalysisCacheRejectsRatioOutsideZeroThroughOne
- testMalformedPersistedCacheCannotBypassValidationDuringDecode
- testCacheIsCurrentOnlyWhenAlgorithmAndContentHashMatch

Run:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioAnalysisTests \
  -only-testing:YagyoPlayerTests/AudioTrackTests
~~~

Expected RED: TrackAnalysisCache and AudioTrack.analysis do not exist.

- [ ] **Step 2: Add the persistent value types**

~~~swift
struct TrackAnalysisCache: Codable, Hashable, Sendable {
    static let currentAlgorithmVersion =
        "yagyo-perception-v1-libebur128-1.2.6"

    let algorithmVersion: String
    let sourceContentHash: String
    let analyzedAt: Date
    let status: TrackAnalysisStatus
    let integratedLUFS: Double?
    let maximumMomentaryLUFS: Double?
    let maximumShortTermLUFS: Double?
    let analyzedDuration: TimeInterval
    let silentDuration: TimeInterval
    let silentRatio: Double
    let onsetCount: Int
    let meanOnsetRate: Double

    init?(
        algorithmVersion: String,
        sourceContentHash: String,
        analyzedAt: Date,
        status: TrackAnalysisStatus,
        integratedLUFS: Double?,
        maximumMomentaryLUFS: Double?,
        maximumShortTermLUFS: Double?,
        analyzedDuration: TimeInterval,
        silentDuration: TimeInterval,
        silentRatio: Double,
        onsetCount: Int,
        meanOnsetRate: Double
    )

    init(from decoder: Decoder) throws

    func isCurrent(
        contentHash: String?,
        algorithmVersion: String
    ) -> Bool
}

struct TrackAnalysisRequest: Equatable, Hashable, Sendable {
    let trackID: AudioTrack.ID
    let fileURL: URL
    let expectedContentHash: String?
    let algorithmVersion: String
}

struct TrackAnalysisResult: Equatable, Sendable {
    let trackID: AudioTrack.ID
    let sourceContentHash: String
    let cache: TrackAnalysisCache
}
~~~

Add var analysis: TrackAnalysisCache? to AudioTrack and default it to nil in its initializer. The failable cache initializer rejects empty version/hash, every nonfinite Double, negative duration/rate/count, silentDuration greater than analyzedDuration, and a ratio outside 0...1. Implement custom Codable decoding that decodes raw fields and delegates to the same validating initializer; synthesized decoding must not bypass these invariants.

- [ ] **Step 3: Write failing chunked-hashing tests**

- testAudioFileHasherMatchesKnownSHA256AcrossChunkSizes
- testImportAndLegacyBackfillUseAudioFileHasher
- testHasherRejectsNonpositiveChunkSize

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioLibraryStoreTests
~~~

Expected RED: AudioFileHasher does not exist.

- [ ] **Step 4: Extract chunked hashing**

Move the existing import/backfill SHA-256 implementation without changing its byte semantics:

~~~swift
enum AudioFileHasher {
    static let defaultChunkSize = 1_048_576

    static func sha256Hex(
        of url: URL,
        chunkSize: Int = defaultChunkSize
    ) throws -> String
}
~~~

- [ ] **Step 5: Write failing store invalidation/rollback tests**

Add these exact cases:

- testPendingAnalysisIncludesMissingCache
- testPendingAnalysisIncludesStaleAlgorithmVersion
- testPendingAnalysisIncludesStaleContentHash
- testPendingAnalysisIncludesNilManifestHash
- testPendingAnalysisSkipsOnlyMatchingHashAndVersion
- testPendingAnalysisPreservesTrackOrder
- testUpdateAnalysisRejectsDeletedTrack
- testUpdateAnalysisRejectsMissingStoredFile
- testUpdateAnalysisRejectsMismatchedResultAndCacheHash
- testUpdateAnalysisRejectsChangedManifestHash
- testUpdateAnalysisFillsNilHashAndCacheAtomically
- testUpdateAnalysisRollsBackWholeTrackWhenSaveFails
- testSuccessfulUpdateClearsAnalysisPersistenceError

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioLibraryStoreTests
~~~

Expected RED: pendingAnalysisRequests and updateAnalysis do not exist.

- [ ] **Step 6: Implement store discovery and update**

~~~swift
func pendingAnalysisRequests(
    algorithmVersion: String
) -> [TrackAnalysisRequest]

@discardableResult
func updateAnalysis(
    _ result: TrackAnalysisResult
) -> Bool
~~~

pendingAnalysisRequests includes missing-cache, stale-version, stale-hash, and nil-hash tracks in current track order. It skips only a cache whose version and nonnil manifest hash both match.

updateAnalysis:

1. Rejects a missing track or stored file.
2. Requires result.sourceContentHash to equal cache.sourceContentHash.
3. Rejects a nonnil current manifest hash that differs.
4. If the current hash is nil, fills the hash and cache in one mutation.
5. Persists through the existing atomic library.json save.
6. Restores the entire previous AudioTrack on save failure.
7. Publishes "Track analysis could not be saved: …" only for save errors.
8. Clears that error on success; stale/deleted results return false without a user-facing error.

- [ ] **Step 7: Verify and commit**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioAnalysisTests \
  -only-testing:YagyoPlayerTests/AudioTrackTests \
  -only-testing:YagyoPlayerTests/AudioLibraryStoreTests
git add YagyoPlayer/Models/AudioAnalysis.swift \
  YagyoPlayer/Models/AudioTrack.swift \
  YagyoPlayer/Services/AudioFileHasher.swift \
  YagyoPlayer/Services/AudioLibraryStore.swift \
  YagyoPlayerTests/AudioAnalysisTests.swift \
  YagyoPlayerTests/AudioTrackTests.swift \
  YagyoPlayerTests/AudioLibraryStoreTests.swift \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: persist versioned track analysis"
~~~

---

### Task 6: Analyze stored files offline and coordinate serial backfill

**Files:**

- Create: YagyoPlayer/Services/OfflineTrackAnalyzer.swift
- Create: YagyoPlayer/Services/TrackAnalysisCoordinator.swift
- Create: YagyoPlayerTests/OfflineTrackAnalyzerTests.swift
- Create: YagyoPlayerTests/TrackAnalysisCoordinatorTests.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: TrackAnalysisRequest, AudioFileHasher, AVAudioFile, AVAudioPCMBufferAdapter, PerceptionDSPProcessing, AudioLibraryStore.
- Produces: hash-bound analysis results and one serial utility-priority scheduling lane.

- [ ] **Step 1: Write failing offline-analyzer tests**

Add exact cases:

- testAnalyzerHashesBeforeReadingAndReturnsMatchingResult
- testAnalyzerReadsIn4096FrameChunks
- testAnalyzerUsesFileProcessingFormatWithoutStereoConversion
- testAnalyzerPassesContiguousSourceFrameOffsets
- testAnalyzerResultMatchesDirectSharedCore
- testUnsupportedLayoutReturnsFiniteUnsupportedCache
- testChangedFileDuringAnalysisIsRejectedByPostReadHash
- testCancellationStopsBeforeCommitResultIsReturned
- testEmptyFileReturnsUnsupportedWithoutNonfiniteValues

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/OfflineTrackAnalyzerTests
~~~

Expected RED: TrackAnalyzing and OfflineTrackAnalyzer do not exist.

- [ ] **Step 2: Add the offline analyzer contract**

~~~swift
protocol TrackAnalyzing: Sendable {
    func analyze(_ request: TrackAnalysisRequest) async throws
        -> TrackAnalysisResult
}

actor OfflineTrackAnalyzer: TrackAnalyzing {
    static let readFrameCapacity: AVAudioFrameCount = 4_096

    init(
        hasher: @escaping @Sendable (URL) throws -> String =
            { try AudioFileHasher.sha256Hex(of: $0) },
        now: @escaping @Sendable () -> Date = { Date() },
        coreFactory: @escaping @Sendable
            (AnalysisPCMFormat) throws -> any PerceptionDSPProcessing = {
                try PerceptionDSPCore(format: $0)
            }
    )

    func analyze(_ request: TrackAnalysisRequest) async throws
        -> TrackAnalysisResult
}
~~~

For each request:

1. Check cancellation.
2. Hash the stored file.
3. Reject a nonnil expectedContentHash mismatch as stale.
4. Open AVAudioFile and validate its processingFormat through one adapter.
5. Reuse one 4,096-frame PCM buffer and one interleaved Float buffer.
6. For a supported analysisFormat, build borrowed AudioSampleBlock values over that scratch buffer and feed contiguous file-frame offsets into one fresh shared core.
7. Check cancellation between reads.
8. Finalize, then hash the file a second time and reject if it differs from the pre-read hash or expected manifest hash.
9. Validate every aggregate, build the cache with the request algorithm and injected date, and return a result bound to the stable hash.

An adapter whose analysisFormat is nil produces status unsupported with nil LUFS and finite file-duration/zero silence/onset aggregates. Decode/read/hash/DSP failures remain errors and must not be relabelled unsupported.

- [ ] **Step 3: Verify offline analysis GREEN**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/OfflineTrackAnalyzerTests
~~~

- [ ] **Step 4: Write failing coordinator tests**

Add exact cases:

- testEnqueuePendingDeduplicatesTrackIDs
- testCoordinatorNeverRunsMoreThanOneAnalysisConcurrently
- testCoordinatorCommitsSuccessfulResult
- testCoordinatorDoesNotCommitThrownFailureAndAllowsRetry
- testEnqueueTrackIDsAnalyzesOnlyRequestedCurrentTracks
- testCancelDiscardsQueuedWorkAndCancelsInFlightWork
- testLateResultForDeletedOrChangedTrackIsDiscarded
- testCoordinatorRunsWorkAtUtilityPriority

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/TrackAnalysisCoordinatorTests
~~~

Expected RED: TrackAnalysisCoordinator does not exist.

- [ ] **Step 5: Implement the MainActor coordinator**

~~~swift
@MainActor
final class TrackAnalysisCoordinator: ObservableObject {
    @Published private(set) var activeTrackID: AudioTrack.ID?
    @Published private(set) var queuedTrackCount = 0

    init(
        analyzer: any TrackAnalyzing = OfflineTrackAnalyzer(),
        algorithmVersion: String =
            TrackAnalysisCache.currentAlgorithmVersion
    )

    func enqueuePending(in library: AudioLibraryStore)
    func enqueue(
        trackIDs: [AudioTrack.ID],
        in library: AudioLibraryStore
    )
    func cancel()
}
~~~

Use one Task with TaskPriority.utility, an insertion-ordered deduplicating queue, and at most one analyzer call at a time. Re-resolve each queued ID against pendingAnalysisRequests immediately before analysis. Commit only through updateAnalysis. A failure removes the in-flight marker so a later enqueue can retry. cancel clears queued work and cancels the in-flight task.

- [ ] **Step 6: Verify and commit**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/OfflineTrackAnalyzerTests \
  -only-testing:YagyoPlayerTests/TrackAnalysisCoordinatorTests
git add YagyoPlayer/Services/OfflineTrackAnalyzer.swift \
  YagyoPlayer/Services/TrackAnalysisCoordinator.swift \
  YagyoPlayerTests/OfflineTrackAnalyzerTests.swift \
  YagyoPlayerTests/TrackAnalysisCoordinatorTests.swift \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: analyze stored tracks in background"
~~~

---

### Task 7: Add the bounded generation-tagged realtime pipeline

**Files:**

- Create: YagyoPlayer/Analysis/RealtimePerceptionPipeline.swift
- Create: YagyoPlayerTests/RealtimePerceptionPipelineTests.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: AVAudioPCMBufferAdapter, PerceptionDSPProcessing, RealtimeAnalysisSnapshot, Synchronization.Atomic and Mutex from the iOS SDK.
- Produces: a preallocated render-producer/serial-worker boundary with loss diagnostics.

- [ ] **Step 1: Write failing realtime-boundary tests**

Add exact cases:

- testPCMBlocksReusePreallocatedStorage
- testFullQueueDropsIncomingPCMAndIncrementsDiagnostic
- testControlMailboxAcceptsResetAndTerminalBarrierWhenPCMIsFull
- testRapidResetsCoalesceToNewestGenerationWithoutLosingIt
- testFullQueueReturnsFalseWhileWorkerIsSuspended
- testTapBufferLargerThanOneSlotSplitsIntoBoundedBlocks
- testWorkerConsumesCommandsOnOneSerialExecutor
- testResetDiscardsOlderGenerationPCMEndAndFinalize
- testNoncontiguousStartFrameRecreatesCoreAndMarksDiscontinuity
- testEndAndFinalizeRunAfterAllMatchingPCM
- testOlderEndMarkerCannotFinalizeNewGeneration
- testSnapshotPublishesOneSynchronizedWholeValue
- testConcurrentSnapshotStress
- testOnsetSequenceIncreasesMonotonicallyAcrossCoreReset
- testArbitraryChunkingMatchesDirectCoreWhenNothingDrops
- testSnapshotDoesNotExposeNonfiniteValues
- testShutdownIsIdempotent

- [ ] **Step 2: Run the focused suite and witness RED**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/RealtimePerceptionPipelineTests
~~~

Expected RED: RealtimePerceptionPipeline and its fixed-capacity API do not exist.

- [ ] **Step 3: Define the exact pipeline API**

~~~swift
final class RealtimePerceptionPipeline: @unchecked Sendable {
    struct Configuration: Equatable, Sendable {
        let slotCount: Int
        let framesPerSlot: Int
        let maximumChannelCount: Int

        static let production = Configuration(
            slotCount: 32,
            framesPerSlot: 1_024,
            maximumChannelCount: 8
        )
    }

    typealias CoreFactory =
        @Sendable (AnalysisPCMFormat) throws
            -> any PerceptionDSPProcessing

    init(
        configuration: Configuration = .production,
        coreFactory: @escaping CoreFactory = {
            try PerceptionDSPCore(format: $0)
        }
    )

    func enqueueReset(
        generation: UInt64,
        sourceDescription: PCMSourceDescription,
        analysisFormat: AnalysisPCMFormat?
    )

    @discardableResult
    nonisolated func tryEnqueuePCM(
        from buffer: AVAudioPCMBuffer,
        adapter: AVAudioPCMBufferAdapter,
        streamStartFrame: Int64,
        generation: UInt64
    ) -> Bool

    func enqueueEndOfStream(generation: UInt64)
    func enqueueFinalize(generation: UInt64)
    func snapshot() -> RealtimeAnalysisSnapshot
    func shutdown()

    // Test/diagnostic synchronization only; never render-thread code.
    func flush()
}
~~~

- [ ] **Step 4: Implement the fixed-capacity worker**

Preallocate all PCM slots during initialization. The render callback is the only producer of a PCM-only SPSC ring; the serial worker is its only consumer. Control calls never write that ring.

tryEnqueuePCM splits any tap buffer into source ranges of at most framesPerSlot; installTap's requested buffer size is not treated as a hard maximum. It may only copy through the adapter's nonthrowing range API, update fixed storage/atomics, signal the existing worker, and return. It must never allocate, wait, perform I/O, call DSP, mutate Published state, or create a Task. If capacity runs out midway, drop that subblock and the remaining subblocks, increment the diagnostic for each, and return false; the next accepted streamStartFrame exposes the gap.

Use release/acquire slot ownership explicitly: the render producer finishes PCM/metadata writes before a release store of the write sequence; the worker performs an acquire load before reading; the worker release-publishes the read sequence; the producer acquire-loads it before slot reuse.

Control uses a separate Mutex-protected, non-render mailbox consumed by the same serial worker:

- a latest-reset record contains generation, source/analysis format, and the accepted PCM write sequence captured when reset was requested;
- a terminal record contains generation, end/finalize flags, and its captured PCM write-sequence barrier;
- a newer reset replaces older resets and terminal records, so rapid seek/load/rebuild cannot exhaust control capacity;
- end/finalize for the active generation coalesce into one terminal record;
- the worker applies reset only after it has consumed/discarded PCM through the reset barrier, and applies end/finalize only after it has consumed matching PCM through the terminal barrier;
- stale-generation controls and PCM are discarded.

Because reset is requested before installing the new tap, new-generation PCM always has a sequence after its reset barrier. This preserves the approved single-worker ordering without allowing multiple producers into the SPSC ring.

A new generation, unsupported-to-supported format transition, or unexpected streamStartFrame replaces the worker-confined core. Unsupported analysisFormat still computes raw max-channel RMS but publishes nil loudness/no onset. After a gap, publish hasDiscontinuity true and withhold loudness until the replacement core has enough PCM.

Protect the complete published RealtimeAnalysisSnapshot with Synchronization.Mutex; never read/write individual fields concurrently. The worker owns a pipeline-global onset counter, observes local core sequence deltas after each consume, and overlays that counter so onsetSequence never resets when the core/generation changes. Sanitize every snapshot to finite-or-nil values.

- [ ] **Step 5: Run GREEN and commit**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/RealtimePerceptionPipelineTests
git add YagyoPlayer/Analysis/RealtimePerceptionPipeline.swift \
  YagyoPlayerTests/RealtimePerceptionPipelineTests.swift \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: add bounded realtime perception pipeline"
~~~

---

### Task 8: Replace AVAudioPlayer transport with AVAudioEngine and the pre-volume tap

**Files:**

- Create: YagyoPlayer/Services/AudioEnginePlaybackBackend.swift
- Create: YagyoPlayerTests/AudioEnginePlaybackBackendTests.swift
- Modify: YagyoPlayer/Services/PlaybackController.swift
- Modify: YagyoPlayerTests/PlaybackControllerTests.swift
- Delete: YagyoPlayer/Services/LegacyAudioPlayerPlaybackBackend.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: AudioPlaybackBackend, RealtimePerceptionPipeline, AVAudioEngine, AVAudioPlayerNode, AVAudioMixerNode.
- Produces: source-rate-correct transport, source-format pre-volume analysis, generation-safe completion and recovery.

- [ ] **Step 1: Write failing transport/position tests**

Add exact cases:

- testDurationUsesFileFramesAndSourceSampleRate
- testPositionConvertsFileAndRenderRateDomains
- testPositionClampsToLoadedDuration
- testSeekClampsBelowZeroAndBeyondDuration
- testSeekIncrementsGenerationAndInvalidatesOldCompletion
- testLoadStopAndRebuildInvalidateOldCompletion
- testPauseResumeKeepsScheduleGeneration
- testMatchingDataPlayedBackCompletionCarriesTrackIDAndGeneration
- testRebuildReschedulesAtLastConfirmedFrameAndRemainsPaused
- testInterruptionPreparationRestartsEngineAndConservativelyReschedulesPaused
- testGeneratedWAVLoadsPlaysPausesSeeksAndFinishes

- [ ] **Step 2: Run transport tests and witness RED**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioEnginePlaybackBackendTests
~~~

Expected RED: AudioEnginePlaybackBackend and PlaybackPositionCalculator do not exist.

- [ ] **Step 3: Define the concrete backend**

~~~swift
@MainActor
final class AudioEnginePlaybackBackend: AudioPlaybackBackend {
    enum RenderingMode: Sendable {
        case realtime
        case offline(maximumFrameCount: AVAudioFrameCount)
    }

    init(
        pipeline: RealtimePerceptionPipeline =
            RealtimePerceptionPipeline(),
        notificationCenter: NotificationCenter = .default,
        renderingMode: RenderingMode = .realtime
    )

    @discardableResult
    func renderOffline(
        _ frameCount: AVAudioFrameCount,
        into buffer: AVAudioPCMBuffer
    ) throws -> AVAudioEngineManualRenderingStatus
}

enum PlaybackPositionCalculator {
    static func seconds(
        scheduledStartFileFrame: AVAudioFramePosition,
        fileSampleRate: Double,
        renderedSampleTime: AVAudioFramePosition,
        renderSampleRate: Double,
        duration: TimeInterval
    ) -> TimeInterval
}
~~~

Build this graph:

~~~text
AVAudioPlayerNode (volume = 1)
  -> AVAudioMixerNode (outputVolume = app volume)
  -> AVAudioEngine.mainMixerNode
~~~

Connect player-to-mixer and the player output tap with AVAudioFile.processingFormat. Duration is file.length / source sample rate. Position converts render time to seconds before combining rate domains; never add render frames directly to source frames.

Seek clamps, stops the old schedule, increments generation, resets analysis, schedules the remaining file segment, and resumes only if it was previously playing. Pause confirms position but retains generation. Rebuild increments generation, reconstructs the graph, and reschedules at the last confirmed source frame while paused.

prepareToResumeAfterInterruption conservatively stops any surviving player-node schedule, starts the engine if required, increments generation, resets analysis, and reschedules at the last confirmed source frame while remaining paused after every qualifying interruption. It does not depend on an unobservable scheduleValid flag. The controller calls it on interruption end even when policy will remain paused, and alone decides whether to call play afterward.

- [ ] **Step 4: Write failing tap/controller tests**

Add exact cases:

- testTapReceivesSourceFormatAndExpectedFrameCount
- testTapLevelIsIndependentOfPlaybackMixerVolume
- testTapPreservesMonoInsteadOfDuplicatingStereo
- testTapFrameCursorIncludesDroppedBlocks
- testSeekSendsResetBeforeNewGenerationPCM
- testCompletionQueuesEndAndFinalizeBehindPCM
- testControllerPollAppliesPointSixFiveAttack
- testControllerPollAppliesPointOneEightRelease
- testLoadPauseStopAndDeletionPublishZeroLevel
- testConfigurationChangeResumesOnlyWhenControllerPolicyAllows
- testConfigurationChangeWhilePausedDoesNotResume
- testRouteLossDuringRebuildCancelsAutomaticResume
- testInterruptionDuringRebuildCancelsAutomaticResume
- testLateRouteNotificationCannotRaceAutomaticResume
- testChangedRouteFingerprintCancelsResumeBeforeNotificationDelivery
- testInterruptionEndPreparesLostScheduleBeforePolicyResume

- [ ] **Step 5: Run tap/controller tests and witness RED**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioEnginePlaybackBackendTests \
  -only-testing:YagyoPlayerTests/PlaybackControllerTests
~~~

Expected RED: the production tap, route fingerprint gate, and interruption preparation behavior are absent.

- [ ] **Step 6: Install the pre-volume tap and complete migration**

For every schedule, create an immutable Sendable tap context containing only generation, the Sendable numeric adapter, and an atomic frame cursor. Borrow each AVAudioPCMBuffer synchronously and never retain it. Advance the cursor for every delivered frame and every split subrange, including blocks later dropped by the pipeline, so the next accepted block reveals a discontinuity.

Lifecycle:

1. Stop and remove the old tap.
2. Increment transport generation.
3. Enqueue reset for that same generation with the adapter sourceDescription and optional analysisFormat.
4. Install the source-format tap on player node output bus 0.
5. Schedule and optionally play.
6. The Apple dataPlayedBack callback captures only the identity and dispatches one constant-time closure to MainActor; it never locks the pipeline control mailbox.
7. On MainActor, recheck the identity, enqueue end then finalize behind PCM, and only then emit the matching finished event to PlaybackController.

Engine-configuration notification handlers dispatch out of Apple internal callbacks before teardown. Do not use Task.yield as a route-ordering primitive.

PlaybackController owns a nonisolated final RecoveryGate marked @unchecked Sendable whose only mutable state is a Synchronization.Atomic epoch and Atomic privacy-denial bit. On MainActor it also retains lastTrustedRouteFingerprint, the sorted output port-type/UID pairs captured immediately before each successful user/system play. Every interruption-begin or route-change observer callback increments the atomic epoch before dispatching any MainActor policy work; oldDeviceUnavailable also atomically latches denial in that callback. This makes a delayed MainActor notification task unable to race an automatic resume. Recovery compares against the last trusted pre-change route, never a possibly already-changed route sampled at recovery start. It captures the epoch before awaiting backend work and rechecks the atomics after every suspension. Immediately before any automatic play, require all of:

- playback was desired before recovery;
- no active interruption and no privacy-denial latch;
- RecoveryGate epoch still equals the captured value;
- a fresh AVAudioSession.currentRoute fingerprint exactly equals lastTrustedRouteFingerprint;
- the active track/schedule identity still matches.

If any check fails, remain paused until explicit user play. Tests inject the route provider and suspend backend rebuild/preparation so a route change can be placed at every await boundary.

Only an explicit user play action may clear the privacy-denial latch, and it first re-reads the current route; newDeviceAvailable never resumes by itself.

On interruption end with system resume permission, reactivate the session, await prepareToResumeAfterInterruption, then apply the same route/identity gate. This covers interruptions that stop the engine or lose the player-node schedule even when no engine-configuration notification arrives.

Keep presentation smoothing solely in PlaybackController:

~~~swift
let coefficient = raw.level > audioLevel ? 0.65 : 0.18
audioLevel =
    audioLevel * (1 - coefficient) + raw.level * coefficient
~~~

Load, pause, stop, deletion, and a new generation publish level zero. Delete LegacyAudioPlayerPlaybackBackend only after the production backend and controller suites pass.

- [ ] **Step 7: Verify integration and commit**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioEnginePlaybackBackendTests \
  -only-testing:YagyoPlayerTests/PlaybackControllerTests
xcodebuild build \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
git add YagyoPlayer/Services/AudioEnginePlaybackBackend.swift \
  YagyoPlayer/Services/PlaybackController.swift \
  YagyoPlayerTests/AudioEnginePlaybackBackendTests.swift \
  YagyoPlayerTests/PlaybackControllerTests.swift \
  YagyoPlayer.xcodeproj/project.pbxproj
git add -u YagyoPlayer/Services/LegacyAudioPlayerPlaybackBackend.swift
git commit -m "feat: migrate playback to pre-volume engine analysis"
~~~

---

### Task 9: Schedule analysis after launch and committed imports

**Files:**

- Modify: YagyoPlayer/Services/AudioLibraryStore.swift
- Modify: YagyoPlayer/YagyoPlayerApp.swift
- Modify: YagyoPlayer/Views/ContentView.swift
- Modify: YagyoPlayerTests/AudioLibraryStoreTests.swift
- Modify: YagyoPlayerTests/TrackAnalysisCoordinatorTests.swift
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: existing import flow, TrackAnalysisCoordinator.
- Produces: nonblocking launch backfill and analysis only for successfully persisted imports.

- [ ] **Step 1: Write failing launch/import wiring tests**

Add exact cases:

- testImportReturnsOnlyIDsCommittedToLibraryJSON
- testDuplicateAndFailedImportsReturnNoIDs
- testManifestSaveFailureReturnsNoIDs
- testImportCompletionDoesNotWaitForSuspendedAnalyzer
- testLaunchEnqueuesOnlyPendingTracksAfterLibraryLoad

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioLibraryStoreTests \
  -only-testing:YagyoPlayerTests/TrackAnalysisCoordinatorTests
~~~

Expected RED: importAudioFiles still returns Void and app/import coordinator wiring is absent.

- [ ] **Step 2: Return committed import IDs**

Change the existing API without breaking statement-style callers:

~~~swift
@discardableResult
func importAudioFiles(
    from urls: [URL]
) async -> [AudioTrack.ID]
~~~

Return IDs only after library.json is successfully saved. Return an empty array for empty input, directory setup failure, all duplicate/failed inputs, or manifest-save rollback. Preserve existing user-facing import summaries.

- [ ] **Step 3: Own and inject the coordinator**

YagyoPlayerApp owns one StateObject coordinator and injects it as an environment object. In the root startup task, keep ordering:

~~~swift
library.load()
analysisCoordinator.enqueuePending(in: library)
player.installRemoteCommands(library: library)
~~~

ContentView obtains the coordinator from the environment. After import:

~~~swift
let importedTrackIDs =
    await library.importAudioFiles(from: urls)
analysisCoordinator.enqueue(
    trackIDs: importedTrackIDs,
    in: library
)
~~~

Do not await analysis before presenting the import summary or loading the selected track.

- [ ] **Step 4: Verify and commit**

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/AudioLibraryStoreTests \
  -only-testing:YagyoPlayerTests/TrackAnalysisCoordinatorTests
git add YagyoPlayer/Services/AudioLibraryStore.swift \
  YagyoPlayer/YagyoPlayerApp.swift \
  YagyoPlayer/Views/ContentView.swift \
  YagyoPlayerTests/AudioLibraryStoreTests.swift \
  YagyoPlayerTests/TrackAnalysisCoordinatorTests.swift \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "feat: backfill analysis after launch and import"
~~~

---

### Task 10: Prove standards conformance, Simulator behavior, and product truth

**Files:**

- Create after evidence exists: docs/AUDIO_ANALYSIS_VALIDATION.md
- Create: Package.swift
- Create: Validation/AudioConformanceTests/EBUFixtureManifest.swift
- Create: Validation/AudioConformanceTests/EBUFixtureSHA256.txt
- Create: Validation/AudioConformanceTests/LoudnessConformanceTests.swift
- Modify: README.md
- Modify: docs/PRODUCT_DIRECTION.md
- Regenerate: YagyoPlayer.xcodeproj/project.pbxproj

**Interfaces:**

- Consumes: EBU Loudness Test Set v5.0, generated fixtures, ten SHA-identified comparison tracks, FFmpeg ebur128, Youlean Loudness Meter, Xcode/Simulator/device evidence.
- Produces: executable standards checks and an evidence-complete validation record.

- [ ] **Step 1: Add host-side EBU conformance tests over the production DSP sources**

Do not commit the approximately 87 MB EBU archive/audio corpus. An iOS test host cannot reliably read an arbitrary Mac path, so create a macOS SwiftPM test target rather than copying the corpus into a Simulator sandbox.

Package.swift defines:

- CEBUR128 from Vendor/libebur128 with publicHeadersPath "." and the pinned local C source;
- YagyoAnalysisCore from exactly AnalysisResults.swift, AudioPCM.swift, EBUR128Meter.swift, SilenceDetector.swift, OnsetDetector.swift, and PerceptionDSPCore.swift, linked only with AVFoundation and Accelerate;
- AudioConformanceTests from Validation/AudioConformanceTests.

Use this manifest shape, with no remote dependencies:

~~~swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YagyoAudioValidation",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CEBUR128",
            path: "Vendor/libebur128",
            exclude: ["COPYING", "ORIGIN.md"],
            sources: ["ebur128.c"],
            publicHeadersPath: "."
        ),
        .target(
            name: "YagyoAnalysisCore",
            dependencies: ["CEBUR128"],
            path: "YagyoPlayer/Analysis",
            sources: [
                "AnalysisResults.swift", "AudioPCM.swift",
                "EBUR128Meter.swift", "SilenceDetector.swift",
                "OnsetDetector.swift", "PerceptionDSPCore.swift"
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate")
            ]
        ),
        .testTarget(
            name: "AudioConformanceTests",
            dependencies: ["YagyoAnalysisCore"],
            path: "Validation/AudioConformanceTests",
            resources: [.process("EBUFixtureSHA256.txt")]
        )
    ]
)
~~~

The manifest contains these exact 53 required files/cases:

- seq-3341-1-16bit.wav: final M/S/I = -23.0 ±0.1;
- seq-3341-2-16bit.wav: final M/S/I = -33.0 ±0.1;
- seq-3341-3-16bit-v02.wav, seq-3341-4-16bit-v02.wav, seq-3341-5-16bit-v02.wav: I = -23.0 ±0.1;
- seq-3341-6-5channels-16bit.wav and seq-3341-6-6channels-WAVEEX-16bit.wav: I = -23.0 ±0.1;
- seq-3341-7_seq-3342-5-24bit.wav and seq-3341-2011-8_seq-3342-6-24bit-v02.wav: I = -23.0 ±0.1;
- seq-3341-9-24bit.wav: S remains -23.0 ±0.1 after 3 s;
- seq-3341-10-1-24bit.wav through seq-3341-10-20-24bit.wav: max-S = -23.0 ±0.1 for every file;
- seq-3341-11-24bit.wav: feed 100 ms blocks and assert the maximum S for each consecutive 6 s segment is -38, -37, …, -19 ±0.1;
- seq-3341-12-24bit.wav: M remains -23.0 ±0.1 after 1 s;
- seq-3341-13-1-24bit.wav and seq-3341-13-2-24bit.wav, then the archive's exact seq-3341-13-3-24bit.wav.wav through seq-3341-13-20-24bit.wav.wav names: max-M = -23.0 ±0.1 for every file;
- seq-3341-14-24bit.wav: feed 10 ms blocks and assert the maximum M for each consecutive 800 ms segment is -38, -37, …, -19 ±0.1.

True-peak sequences 15 and later remain explicitly out of Step 3 scope.

The corpus test validates readme version v5.0, all 53 paths, and a checked-in SHA-256 manifest before measuring. It normally skips when YAGYO_EBU_TEST_SET_PATH is absent, but when YAGYO_REQUIRE_EBU=1 it fails rather than skips if any requirement is missing.

Acquire and pin the official archive before deriving the per-file manifest:

~~~bash
curl --fail --location \
  'https://tech.ebu.ch/files/live/sites/tech/files/shared/testmaterial/ebu-loudness-test-setv05.zip' \
  --output /tmp/ebu-loudness-test-setv05.zip
test "$(stat -f %z /tmp/ebu-loudness-test-setv05.zip)" = "91631421"
test "$(shasum -a 256 /tmp/ebu-loudness-test-setv05.zip | awk '{print $1}')" = \
  "9cc500b4df83f7c21855c74dce795ef5209a752bf884253ae57d0ce512efb062"
EBU_EXTRACT_ROOT="$HOME/AudioValidation/ebu-loudness-test-set-v05-9cc500b4"
test ! -e "$EBU_EXTRACT_ROOT"
mkdir -p "$EBU_EXTRACT_ROOT"
ditto -x -k /tmp/ebu-loudness-test-setv05.zip \
  "$EBU_EXTRACT_ROOT"
printf '%s\n' "$EBU_EXTRACT_ROOT"
~~~

The byte count and SHA-256 are pinned from the independently published Gentoo distfile manifest for this exact EBU v5.0 filename. Generate EBUFixtureSHA256.txt once from all audio files inside that verified extraction, using relative paths sorted with LC_ALL=C; the test recursively resolves and recomputes the 53 rows it uses. Do not derive new expected hashes from an unverified archive.

Write the tests and run before adding Package.swift:

~~~bash
swift test --filter LoudnessConformanceTests
~~~

Expected RED: no Package.swift/YagyoAnalysisCore target exists.

- [ ] **Step 2: Run mandatory, non-skipping standards conformance**

~~~bash
set -o pipefail
export YAGYO_EBU_TEST_SET_PATH="$HOME/AudioValidation/ebu-loudness-test-set-v05-9cc500b4"
test -f "$YAGYO_EBU_TEST_SET_PATH/readme.txt"
YAGYO_REQUIRE_EBU=1 \
YAGYO_EBU_TEST_SET_PATH="$YAGYO_EBU_TEST_SET_PATH" \
swift test --filter LoudnessConformanceTests \
  2>&1 | tee /tmp/YagyoPlayer-Step3-EBU.log
rg -n '53 fixtures verified|Executed .* tests, with 0 failures' \
  /tmp/YagyoPlayer-Step3-EBU.log
~~~

Expected: corpus sentinel and all table assertions execute with no skip/failure. Missing corpus, version/hash mismatch, or zero measurement rows is a failing gate.

- [ ] **Step 3: Run full automated Mac gates**

Use the installed iOS 26.5 iPhone 17 Pro destination by UDID to avoid name/runtime ambiguity:

~~~bash
xcodegen generate
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -resultBundlePath /tmp/YagyoPlayer-Step3-Tests.xcresult
xcodebuild build \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild analyze \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project YagyoPlayer.xcodeproj \
  -scheme YagyoPlayer \
  -destination 'platform=iOS Simulator,id=79A3F1B4-721A-4524-A0F4-F58155322B99' \
  -only-testing:YagyoPlayerTests/RealtimePerceptionPipelineTests \
  -enableThreadSanitizer YES \
  -resultBundlePath /tmp/YagyoPlayer-Step3-TSan.xcresult
cp YagyoPlayer.xcodeproj/project.pbxproj /tmp/yagyo-step3-final-pbxproj
xcodegen generate
cmp /tmp/yagyo-step3-final-pbxproj \
  YagyoPlayer.xcodeproj/project.pbxproj
git diff --check
~~~

Expected: all tests pass, Thread Sanitizer reports no ring/snapshot/control-mailbox race, build and analyzer succeed, project generation is deterministic, and no remote DSP package appears in Package.swift, project.yml, or project.pbxproj.

- [ ] **Step 4: Launch, inspect, and profile the app in Simulator**

Boot iPhone 17 Pro iOS 26.5 if needed, install the Debug .app, launch its bundle ID, and capture:

- cold launch/library screen;
- import completion without waiting for analysis;
- playback, pause, seek, next/previous;
- visible level response while volume changes do not alter the pre-volume measurement;
- background/foreground recovery;
- no crash or stale completion after rapid seek/track change.

Capture Allocations and Time Profiler traces while playing, changing tracks, and seeking. Verify no allocation is attributed to AVAudioPCMBufferAdapter.copyInterleavedSamples or RealtimePerceptionPipeline.tryEnqueuePCM, the tap never waits on a lock/semaphore, and analysis-worker CPU does not run on the audio render thread. Store screenshots, simctl logs, and traces in /tmp; commit only concise evidence values, not volatile binaries.

- [ ] **Step 5: Compare reference meters and run real-device privacy gates**

For ten SHA-identified tracks spanning quiet, dense, dynamic, leading/trailing silence, short, mono, and stereo:

- record Yagyo, FFmpeg ebur128, and Youlean Integrated/max-M/max-S;
- require at most 0.1 LU delta, or 0.2 LU only when documented reference rounding explains it;
- compare live/offline chunk sizes 64, 257, 1,024, 4,096 and deterministic random chunks within 1e-9 LU, with exactly equal silence/onset aggregates.

For each comparison track run:

~~~bash
ffmpeg -hide_banner -nostats -i "$AUDIO_FILE" \
  -filter_complex 'ebur128=peak=none:framelog=verbose' \
  -f null - 2> "$AUDIO_FILE.ebur128.log"
~~~

In Youlean Loudness Meter 2 select the EBU R128 / ITU-R BS.1770 preset, disable normalization, reset before each complete-file pass, and record Integrated, max Momentary, and max Short-term at one-decimal display precision. Record the exact app/plugin version and whether standalone or plug-in mode was used.

On a signed physical iPhone, record pass/fail for screen lock, Control Center, Bluetooth/AirPods, Siri/phone interruption, unplug privacy pause, seek, background playback, and engine configuration recovery. Simulator results do not replace these manual privacy/device gates.

- [ ] **Step 6: Write validation evidence and update product truth**

Create docs/AUDIO_ANALYSIS_VALIDATION.md only after replacing every evidence row with actual values. Record:

- spec revision, algorithm ID, libebur128 tag/commit;
- EBU archive URL/SHA/readme version;
- Xcode, macOS, iOS runtime, device, FFmpeg, and Youlean versions;
- channel map, meter settings, all conformance measurements/deltas;
- live/offline and ten-track comparisons;
- every Simulator and physical-device result;
- source baseline versus existing Xcode Cloud infrastructure state;
- explicit final pass/fail conclusion.

Update README.md to describe the source-format pre-volume PCM tap, shared on-device perception engine, and local-only library.json aggregates. Update PRODUCT_DIRECTION.md Step 3 to the evidence-backed state while leaving Step 4 choreography and Step 5 Producer Check as future work.

- [ ] **Step 7: Final review and commit**

~~~bash
git status --short
git diff --check
git diff --stat 0d196565db1197f9cb5a9c1a713b1619515e16d6...HEAD
git add Package.swift Validation/AudioConformanceTests \
  docs/AUDIO_ANALYSIS_VALIDATION.md README.md \
  docs/PRODUCT_DIRECTION.md \
  YagyoPlayer.xcodeproj/project.pbxproj
git commit -m "docs: record Step 3 audio analysis validation"
~~~

If physical-device or third-party-meter evidence is unavailable, do not fabricate it and do not mark Step 3 complete. Commit automated work with the validation document clearly marked as partial, then keep the corresponding checklist items open.

---

## Approved Execution Handoff

The user selected Remote Desktop Commander execution with local Codex and Claude Code.

1. Create an isolated Mac git worktree from agent/step3-one-ear; preserve unrelated local files such as the existing untracked uiview directory.
2. Give Codex one numbered task at a time as implementer, with the approved design and this plan as mandatory context.
3. After every task's focused test and commit, give Claude Code the exact diff and test output for specification/concurrency review.
4. Route review findings back to a fresh Codex task; rerun focused tests before proceeding.
5. Use Xcode 27.0, XcodeGen 2.45.4, and the installed iOS 26.5 iPhone 17 Pro Simulator UDID 79A3F1B4-721A-4524-A0F4-F58155322B99 for deterministic local gates.
6. Keep all implementation commits on agent/step3-one-ear. Do not merge to main without separate user authorization.
