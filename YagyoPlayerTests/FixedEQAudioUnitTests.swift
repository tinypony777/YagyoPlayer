import AVFoundation
@preconcurrency import AudioToolbox
import Darwin
import Dispatch
import Synchronization
import XCTest

@testable import YagyoPlayer

@MainActor
final class FixedEQAudioUnitTests: XCTestCase {
    private static let outputIsSilence = AudioUnitRenderActionFlags(rawValue: 1 << 4)

    func testOriginalIsBitTransparentAndAcknowledgedOnFirstBuffer() throws {
        let left: [Float] = [0.25, -0.5, 0, -0.0, .leastNonzeroMagnitude, 0.75]

        for channelCount in [1, 2] {
            let unit = try makeUnit(channelCount: channelCount, maximumFrames: left.count)
            defer { unit.deallocateRenderResources() }
            let channels = channelCount == 1 ? [left] : [left, Array(left.reversed())]
            let input = RenderInputFixture(channels: channels)
            let output = makeOutput(
                sampleRate: 48_000,
                channelCount: channelCount,
                frameCount: left.count
            )

            XCTAssertFalse(unit.canProcessInPlace)
            XCTAssertTrue(unit.enqueue(.original(generation: 101)))
            let outcome = render(
                unit: unit,
                frameCount: left.count,
                outputData: output.mutableAudioBufferList,
                pullInputBlock: input.copyingPullBlock()
            )

            XCTAssertEqual(outcome.status, noErr)
            XCTAssertFalse(outcome.flags.contains(Self.outputIsSilence))
            XCTAssertEqual(unit.lastAppliedGeneration, 101)
            XCTAssertEqual(unit.lastProcessResult, .original)
            XCTAssertEqual(unit.lastRenderFault, .none)
            XCTAssertEqual(unit.lastRenderStatus, noErr)
            XCTAssertFalse(unit.isOriginalLatched)
            for channel in 0..<channelCount {
                XCTAssertEqual(
                    samples(from: output, channel: channel).map(\.bitPattern),
                    channels[channel].map(\.bitPattern)
                )
            }
        }
    }

    func testProcessedSnapshotStartsAtFirstSampleAcrossSupportedFormats() throws {
        let frameCounts = [1, 7, 64, 257]
        var generation: UInt64 = 1

        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
            for channelCount in [1, 2] {
                let unit = try makeUnit(
                    sampleRate: sampleRate,
                    channelCount: channelCount,
                    maximumFrames: frameCounts.max()!
                )
                defer { unit.deallocateRenderResources() }

                for frameCount in frameCounts {
                    let left = (0..<frameCount).map { Float($0 + 1) / Float(frameCount + 1) }
                    let channels = channelCount == 1
                        ? [left]
                        : [left, left.map { -$0 }]
                    let input = RenderInputFixture(channels: channels)
                    let output = makeOutput(
                        sampleRate: sampleRate,
                        channelCount: channelCount,
                        frameCount: frameCount
                    )
                    XCTAssertTrue(unit.enqueue(attenuationSnapshot(generation: generation)))

                    let outcome = render(
                        unit: unit,
                        frameCount: frameCount,
                        outputData: output.mutableAudioBufferList,
                        pullInputBlock: input.copyingPullBlock()
                    )

                    XCTAssertEqual(outcome.status, noErr)
                    XCTAssertEqual(unit.lastAppliedGeneration, generation)
                    XCTAssertEqual(unit.lastProcessResult, .processed)
                    XCTAssertFalse(unit.isOriginalLatched)
                    for channel in 0..<channelCount {
                        let rendered = samples(from: output, channel: channel)
                        for frame in 0..<frameCount {
                            XCTAssertEqual(rendered[frame], channels[channel][frame] * 0.5)
                        }
                    }
                    generation += 1
                }
            }
        }
    }

    func testNewestQueuedSnapshotWinsAtBufferBoundary() throws {
        let unit = try makeUnit(channelCount: 1, maximumFrames: 4)
        defer { unit.deallocateRenderResources() }
        let input = RenderInputFixture(channels: [[1, 0.5, -0.5, -1]])
        let output = makeOutput(channelCount: 1, frameCount: 4)

        XCTAssertTrue(unit.enqueue(.original(generation: 1)))
        XCTAssertTrue(unit.enqueue(attenuationSnapshot(generation: 2)))
        let outcome = render(
            unit: unit,
            frameCount: 4,
            outputData: output.mutableAudioBufferList,
            pullInputBlock: input.copyingPullBlock()
        )

        XCTAssertEqual(outcome.status, noErr)
        XCTAssertEqual(unit.lastAppliedGeneration, 2)
        XCTAssertEqual(samples(from: output, channel: 0), [0.5, 0.25, -0.25, -0.5])
    }

    func testConcurrentRenderAcknowledgementsNeverTearTelemetry() throws {
        let unit = try makeUnit(channelCount: 1, maximumFrames: 4)
        let renderLoop = ConcurrentFixedEQRenderLoop(
            renderBlock: unit.internalRenderBlock,
            frameCount: 4
        )
        let group = DispatchGroup()
        group.enter()
        DispatchQueue(
            label: "FixedEQAudioUnitTests.concurrent-render",
            qos: .userInitiated
        ).async {
            defer { group.leave() }
            renderLoop.run()
        }

        let finalGeneration: UInt64 = 2_000
        var mismatch: String?
        producerLoop: for generation in 1...finalGeneration {
            let snapshot = generation.isMultiple(of: 2)
                ? attenuationSnapshot(generation: generation)
                : .original(generation: generation)
            while !unit.enqueue(snapshot) {
                if let reason = telemetryMismatch(unit.renderTelemetry) {
                    mismatch = reason
                    break producerLoop
                }
                sched_yield()
            }
            if let reason = telemetryMismatch(unit.renderTelemetry) {
                mismatch = reason
                break
            }
        }

        let deadline = Date().addingTimeInterval(5)
        while mismatch == nil,
              unit.renderTelemetry.appliedGeneration != finalGeneration,
              Date() < deadline {
            if let reason = telemetryMismatch(unit.renderTelemetry) {
                mismatch = reason
                break
            }
            sched_yield()
        }

        renderLoop.requestStop()
        let waitResult = group.wait(timeout: .now() + 5)
        let finalTelemetry = unit.renderTelemetry
        unit.deallocateRenderResources()

        XCTAssertEqual(waitResult, .success)
        XCTAssertEqual(renderLoop.lastStatus, noErr)
        XCTAssertNil(mismatch)
        XCTAssertEqual(finalTelemetry.appliedGeneration, finalGeneration)
        XCTAssertNil(telemetryMismatch(finalTelemetry))
    }

    func testNonFiniteInputSanitizesAndLatchRequiresExplicitSnapshot() throws {
        let unit = try makeUnit(channelCount: 1, maximumFrames: 4)
        defer { unit.deallocateRenderResources() }
        XCTAssertTrue(unit.enqueue(attenuationSnapshot(generation: 1)))

        let invalidInput = RenderInputFixture(channels: [[0.25, .nan, .infinity, -.infinity]])
        let invalidOutput = makeOutput(channelCount: 1, frameCount: 4)
        XCTAssertEqual(
            render(
                unit: unit,
                frameCount: 4,
                outputData: invalidOutput.mutableAudioBufferList,
                pullInputBlock: invalidInput.copyingPullBlock()
            ).status,
            noErr
        )
        XCTAssertEqual(samples(from: invalidOutput, channel: 0), [0.25, 0, 0, 0])
        XCTAssertEqual(unit.lastProcessResult, .latchedOriginal)
        XCTAssertTrue(unit.isOriginalLatched)

        let finiteInput = RenderInputFixture(channels: [[0.8, -0.6, 0.4, -0.2]])
        let latchedOutput = makeOutput(channelCount: 1, frameCount: 4)
        XCTAssertEqual(
            render(
                unit: unit,
                frameCount: 4,
                outputData: latchedOutput.mutableAudioBufferList,
                pullInputBlock: finiteInput.copyingPullBlock()
            ).status,
            noErr
        )
        XCTAssertEqual(samples(from: latchedOutput, channel: 0), [0.8, -0.6, 0.4, -0.2])
        XCTAssertTrue(unit.isOriginalLatched)

        XCTAssertTrue(unit.enqueue(attenuationSnapshot(generation: 2)))
        let recoveredOutput = makeOutput(channelCount: 1, frameCount: 4)
        XCTAssertEqual(
            render(
                unit: unit,
                frameCount: 4,
                outputData: recoveredOutput.mutableAudioBufferList,
                pullInputBlock: finiteInput.copyingPullBlock()
            ).status,
            noErr
        )
        XCTAssertEqual(samples(from: recoveredOutput, channel: 0), [0.4, -0.3, 0.2, -0.1])
        XCTAssertEqual(unit.lastAppliedGeneration, 2)
        XCTAssertFalse(unit.isOriginalLatched)
    }

    func testNilOutputPointersReceiveAudioUnitOwnedFallbackBuffers() throws {
        let frameCount = 5
        let unit = try makeUnit(channelCount: 2, maximumFrames: frameCount)
        defer { unit.deallocateRenderResources() }
        let channels: [[Float]] = [
            [0.1, 0.2, 0.3, 0.4, 0.5],
            [-0.1, -0.2, -0.3, -0.4, -0.5],
        ]
        let input = RenderInputFixture(channels: channels)
        let output = AudioBufferList.allocate(maximumBuffers: 2)
        defer { free(output.unsafeMutablePointer) }
        for channel in 0..<2 {
            output[channel].mNumberChannels = 1
            output[channel].mDataByteSize = 0
            output[channel].mData = nil
        }
        XCTAssertTrue(unit.enqueue(.original(generation: 8)))

        let outcome = render(
            unit: unit,
            frameCount: frameCount,
            outputData: output.unsafeMutablePointer,
            pullInputBlock: input.copyingPullBlock()
        )

        XCTAssertEqual(outcome.status, noErr)
        XCTAssertFalse(outcome.flags.contains(Self.outputIsSilence))
        for channel in 0..<2 {
            XCTAssertEqual(Int(output[channel].mDataByteSize), frameCount * MemoryLayout<Float>.stride)
            let pointer = try XCTUnwrap(
                output[channel].mData?.assumingMemoryBound(to: Float.self)
            )
            XCTAssertEqual(
                Array(UnsafeBufferPointer(start: pointer, count: frameCount)).map(\.bitPattern),
                channels[channel].map(\.bitPattern)
            )
        }
    }

    func testPullMayReplaceInputPointers() throws {
        let channels: [[Float]] = [
            [0.2, 0.4, 0.6, 0.8],
            [-0.2, -0.4, -0.6, -0.8],
        ]
        let unit = try makeUnit(channelCount: 2, maximumFrames: 4)
        defer { unit.deallocateRenderResources() }
        let input = RenderInputFixture(channels: channels)
        let output = makeOutput(channelCount: 2, frameCount: 4)
        XCTAssertTrue(unit.enqueue(attenuationSnapshot(generation: 9)))

        let outcome = render(
            unit: unit,
            frameCount: 4,
            outputData: output.mutableAudioBufferList,
            pullInputBlock: input.replacingPullBlock()
        )

        XCTAssertEqual(outcome.status, noErr)
        XCTAssertEqual(samples(from: output, channel: 0), [0.1, 0.2, 0.3, 0.4])
        XCTAssertEqual(samples(from: output, channel: 1), [-0.1, -0.2, -0.3, -0.4])
        XCTAssertEqual(unit.lastAppliedGeneration, 9)

        let secondChannels: [[Float]] = [
            [0.1, 0.3, 0.5, 0.7],
            [-0.1, -0.3, -0.5, -0.7],
        ]
        let secondInput = RenderInputFixture(channels: secondChannels)
        let restoration = PullPointerRestorationObservation(
            previousPointers: input.rawPointers
        )
        let secondOutput = makeOutput(channelCount: 2, frameCount: 4)
        let secondOutcome = render(
            unit: unit,
            frameCount: 4,
            outputData: secondOutput.mutableAudioBufferList,
            pullInputBlock: secondInput.copyingPullBlock(
                restorationObservation: restoration
            )
        )

        XCTAssertEqual(secondOutcome.status, noErr)
        XCTAssertTrue(restoration.didRestoreOwnedPointers)
        XCTAssertEqual(samples(from: secondOutput, channel: 0), [0.05, 0.15, 0.25, 0.35])
        XCTAssertEqual(samples(from: secondOutput, channel: 1), [-0.05, -0.15, -0.25, -0.35])
    }

    func testMissingAndFailingPullInputReturnSilenceWithTelemetry() throws {
        let scenarios: [(AURenderPullInputBlock?, FixedEQAudioUnitRenderFault, OSStatus)] = [
            (nil, .missingPullInput, kAudioUnitErr_NoConnection),
            ({ _, _, _, _, _ in -12_345 }, .pullInputFailure, -12_345),
        ]

        for (pullInputBlock, expectedFault, expectedStatus) in scenarios {
            let unit = try makeUnit(channelCount: 1, maximumFrames: 4)
            defer { unit.deallocateRenderResources() }
            let output = makeOutput(channelCount: 1, frameCount: 4, initialValue: 1)

            let outcome = render(
                unit: unit,
                frameCount: 4,
                outputData: output.mutableAudioBufferList,
                pullInputBlock: pullInputBlock
            )

            XCTAssertEqual(outcome.status, noErr)
            XCTAssertTrue(outcome.flags.contains(Self.outputIsSilence))
            XCTAssertEqual(samples(from: output, channel: 0), [0, 0, 0, 0])
            XCTAssertEqual(unit.lastRenderFault, expectedFault)
            XCTAssertEqual(unit.lastRenderStatus, expectedStatus)
            XCTAssertEqual(unit.lastProcessResult, .invalidBuffers)
            XCTAssertTrue(unit.isOriginalLatched)
        }
    }

    func testRenderBeforeAllocationAndInvalidOutputBusReturnHostErrors() throws {
        let unallocatedUnit = try FixedEQAudioUnit(
            componentDescription: FixedEQAudioUnit.componentDescription
        )
        let unallocatedOutput = makeOutput(
            channelCount: 2,
            frameCount: 4,
            initialValue: 1
        )
        let unallocatedOutcome = render(
            unit: unallocatedUnit,
            frameCount: 4,
            outputData: unallocatedOutput.mutableAudioBufferList,
            pullInputBlock: nil
        )
        XCTAssertEqual(unallocatedOutcome.status, kAudioUnitErr_Uninitialized)
        XCTAssertTrue(unallocatedOutcome.flags.contains(Self.outputIsSilence))
        XCTAssertEqual(unallocatedUnit.lastRenderFault, .notReady)
        XCTAssertEqual(samples(from: unallocatedOutput, channel: 0), [0, 0, 0, 0])
        XCTAssertEqual(samples(from: unallocatedOutput, channel: 1), [0, 0, 0, 0])

        let allocatedUnit = try makeUnit(channelCount: 1, maximumFrames: 4)
        defer { allocatedUnit.deallocateRenderResources() }
        let invalidBusOutput = makeOutput(
            channelCount: 1,
            frameCount: 4,
            initialValue: 1
        )
        let invalidBusOutcome = render(
            unit: allocatedUnit,
            frameCount: 4,
            outputBusNumber: 1,
            outputData: invalidBusOutput.mutableAudioBufferList,
            pullInputBlock: nil
        )
        XCTAssertEqual(invalidBusOutcome.status, kAudioUnitErr_InvalidElement)
        XCTAssertTrue(invalidBusOutcome.flags.contains(Self.outputIsSilence))
        XCTAssertEqual(allocatedUnit.lastRenderFault, .invalidOutputBus)
        XCTAssertEqual(samples(from: invalidBusOutput, channel: 0), [0, 0, 0, 0])
    }

    func testInvalidPulledInputFailsSilentAndLatchesOriginal() throws {
        let unit = try makeUnit(channelCount: 1, maximumFrames: 4)
        defer { unit.deallocateRenderResources() }
        let output = makeOutput(channelCount: 1, frameCount: 4, initialValue: 1)
        let invalidInput: AURenderPullInputBlock = { _, _, _, _, inputData in
            let buffers = UnsafeMutableAudioBufferListPointer(inputData)
            buffers[0].mNumberChannels = 1
            buffers[0].mDataByteSize = 0
            buffers[0].mData = nil
            return noErr
        }

        let outcome = render(
            unit: unit,
            frameCount: 4,
            outputData: output.mutableAudioBufferList,
            pullInputBlock: invalidInput
        )

        XCTAssertEqual(outcome.status, noErr)
        XCTAssertTrue(outcome.flags.contains(Self.outputIsSilence))
        XCTAssertEqual(samples(from: output, channel: 0), [0, 0, 0, 0])
        XCTAssertEqual(unit.lastRenderFault, .invalidInputBuffers)
        XCTAssertEqual(unit.lastRenderStatus, kAudio_ParamError)
        XCTAssertTrue(unit.isOriginalLatched)
    }

    func testFrameOverflowReturnsHostErrorAndZerosOutput() throws {
        let frameCount = 65
        let unit = try makeUnit(channelCount: 1, maximumFrames: 64)
        defer { unit.deallocateRenderResources() }
        let output = makeOutput(channelCount: 1, frameCount: frameCount, initialValue: 1)

        let outcome = render(
            unit: unit,
            frameCount: frameCount,
            outputData: output.mutableAudioBufferList,
            pullInputBlock: nil
        )

        XCTAssertEqual(outcome.status, kAudioUnitErr_TooManyFramesToProcess)
        XCTAssertTrue(outcome.flags.contains(Self.outputIsSilence))
        XCTAssertEqual(samples(from: output, channel: 0), Array(repeating: 0, count: frameCount))
        XCTAssertEqual(unit.lastRenderFault, .frameOverflow)
        XCTAssertEqual(unit.lastRenderStatus, kAudioUnitErr_TooManyFramesToProcess)
        XCTAssertTrue(unit.isOriginalLatched)
    }

    func testUndersizedOutputReturnsHostErrorAndZerosOnlyDeclaredBytes() throws {
        let requestedFrames = 16
        let declaredFrames = 8
        let unit = try makeUnit(channelCount: 1, maximumFrames: requestedFrames)
        defer { unit.deallocateRenderResources() }
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: requestedFrames)
        storage.initialize(repeating: 1, count: requestedFrames)
        defer {
            storage.deinitialize(count: requestedFrames)
            storage.deallocate()
        }
        let output = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(output.unsafeMutablePointer) }
        output[0].mNumberChannels = 1
        output[0].mDataByteSize = UInt32(declaredFrames * MemoryLayout<Float>.stride)
        output[0].mData = UnsafeMutableRawPointer(storage)

        let outcome = render(
            unit: unit,
            frameCount: requestedFrames,
            outputData: output.unsafeMutablePointer,
            pullInputBlock: nil
        )

        XCTAssertEqual(outcome.status, kAudio_ParamError)
        XCTAssertTrue(outcome.flags.contains(Self.outputIsSilence))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: storage, count: declaredFrames)), Array(repeating: 0, count: declaredFrames))
        XCTAssertEqual(
            Array(UnsafeBufferPointer(start: storage + declaredFrames, count: requestedFrames - declaredFrames)),
            Array(repeating: 1, count: requestedFrames - declaredFrames)
        )
        XCTAssertEqual(unit.lastRenderFault, .invalidOutputBuffers)
    }

    func testAliasedInputOutputFailsSilentAndLatchesOriginal() throws {
        let frameCount = 4
        let unit = try makeUnit(channelCount: 1, maximumFrames: frameCount)
        defer { unit.deallocateRenderResources() }
        let output = makeOutput(channelCount: 1, frameCount: frameCount)
        let values: [Float] = [0.2, 0.4, 0.6, 0.8]
        for (index, value) in values.enumerated() {
            output.floatChannelData![0][index] = value
        }
        let alias = BorrowedRenderPointers(
            pointers: [UnsafeMutableRawPointer(output.floatChannelData![0])],
            byteCount: frameCount * MemoryLayout<Float>.stride
        )
        XCTAssertTrue(unit.enqueue(attenuationSnapshot(generation: 12)))

        let outcome = render(
            unit: unit,
            frameCount: frameCount,
            outputData: output.mutableAudioBufferList,
            pullInputBlock: alias.replacingPullBlock()
        )

        XCTAssertEqual(outcome.status, noErr)
        XCTAssertTrue(outcome.flags.contains(Self.outputIsSilence))
        XCTAssertEqual(samples(from: output, channel: 0), [0, 0, 0, 0])
        XCTAssertEqual(unit.lastAppliedGeneration, 12)
        XCTAssertEqual(unit.lastRenderFault, .processorInvalidBuffers)
        XCTAssertEqual(unit.lastRenderStatus, kAudio_ParamError)
        XCTAssertTrue(unit.isOriginalLatched)
    }

    func testResetClearsFilterHistoryAndReallocationKeepsControlEndpoint() throws {
        let unit = try makeUnit(channelCount: 1, maximumFrames: 32)
        defer { unit.deallocateRenderResources() }
        let snapshot = FixedEQSnapshotFactory.make(
            recipe: FixedEQRecipe(
                id: "audio-unit-tail",
                catalogVersion: 1,
                inputHeadroomDB: -3,
                bands: [
                    FixedEQBand(frequencyHz: 500, gainDB: 3, q: 1),
                    FixedEQBand(frequencyHz: 2_000, gainDB: 0, q: 1),
                    FixedEQBand(frequencyHz: 8_000, gainDB: 0, q: 1),
                ],
                outputTrimDB: 0
            ),
            sampleRate: 48_000,
            generation: 20
        )
        XCTAssertEqual(snapshot.mode, .processed)
        XCTAssertTrue(unit.enqueue(snapshot))

        let impulse = RenderInputFixture(channels: [[1]])
        let impulseOutput = makeOutput(channelCount: 1, frameCount: 1)
        XCTAssertEqual(
            render(
                unit: unit,
                frameCount: 1,
                outputData: impulseOutput.mutableAudioBufferList,
                pullInputBlock: impulse.copyingPullBlock()
            ).status,
            noErr
        )

        let silence = RenderInputFixture(channels: [Array(repeating: 0, count: 32)])
        let tailOutput = makeOutput(channelCount: 1, frameCount: 32)
        XCTAssertEqual(
            render(
                unit: unit,
                frameCount: 32,
                outputData: tailOutput.mutableAudioBufferList,
                pullInputBlock: silence.copyingPullBlock()
            ).status,
            noErr
        )
        XCTAssertTrue(samples(from: tailOutput, channel: 0).contains { abs($0) > 1e-8 })

        unit.reset()
        let resetOutput = makeOutput(channelCount: 1, frameCount: 32, initialValue: 1)
        XCTAssertEqual(
            render(
                unit: unit,
                frameCount: 32,
                outputData: resetOutput.mutableAudioBufferList,
                pullInputBlock: silence.copyingPullBlock()
            ).status,
            noErr
        )
        XCTAssertTrue(samples(from: resetOutput, channel: 0).allSatisfy { $0.bitPattern == Float.zero.bitPattern })

        unit.deallocateRenderResources()
        try unit.allocateRenderResources()
        XCTAssertTrue(unit.enqueue(.original(generation: 21)))
        let original = RenderInputFixture(channels: [[0.25]])
        let reallocatedOutput = makeOutput(channelCount: 1, frameCount: 1)
        XCTAssertEqual(
            render(
                unit: unit,
                frameCount: 1,
                outputData: reallocatedOutput.mutableAudioBufferList,
                pullInputBlock: original.copyingPullBlock()
            ).status,
            noErr
        )
        XCTAssertEqual(samples(from: reallocatedOutput, channel: 0), [0.25])
        XCTAssertEqual(unit.lastAppliedGeneration, 21)
    }

    func testOfflineEngineRendersOriginalAndProcessedAcrossFormatMatrix() async throws {
        let frameCount = 131 // two full 64-frame blocks plus an odd 3-frame tail
        var generation: UInt64 = 1_000

        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
            for channelCount in [1, 2] {
                let left = (0..<frameCount).map { frame in
                    Float(sin(Double(frame) * 0.071) * 0.4)
                }
                let channels = channelCount == 1
                    ? [left]
                    : [left, left.enumerated().map { index, value in index.isMultiple(of: 2) ? -value : value }]

                let original = try await renderOffline(
                    channels: channels,
                    sampleRate: sampleRate,
                    maximumFrameCount: 64,
                    snapshot: .original(generation: generation)
                )
                var hostGains: [Float] = []
                for channel in 0..<channelCount {
                    XCTAssertEqual(original[channel].count, frameCount)
                    XCTAssertTrue(original[channel].allSatisfy(\.isFinite))
                    XCTAssertTrue(original[channel].contains { abs($0) > 0.05 })
                    let referenceFrame = try XCTUnwrap(
                        channels[channel].firstIndex { abs($0) > 0.05 }
                    )
                    let hostGain = original[channel][referenceFrame]
                        / channels[channel][referenceFrame]
                    XCTAssertTrue(hostGain.isFinite)
                    XCTAssertTrue((0.25...1.5).contains(hostGain))
                    hostGains.append(hostGain)
                    for frame in 0..<frameCount {
                        XCTAssertEqual(
                            original[channel][frame],
                            channels[channel][frame] * hostGain,
                            accuracy: 2e-6,
                            "Original shape \(sampleRate) Hz channel \(channel) frame \(frame)"
                        )
                    }
                }
                generation += 1

                let processed = try await renderOffline(
                    channels: channels,
                    sampleRate: sampleRate,
                    maximumFrameCount: 64,
                    snapshot: attenuationSnapshot(generation: generation)
                )
                for channel in 0..<channelCount {
                    XCTAssertEqual(processed[channel].count, frameCount)
                    for frame in 0..<frameCount {
                        XCTAssertEqual(
                            processed[channel][frame],
                            channels[channel][frame] * hostGains[channel] * 0.5,
                            accuracy: 2e-6,
                            "Processed \(sampleRate) Hz channel \(channel) frame \(frame)"
                        )
                    }
                }
                generation += 1
            }
        }
    }

    func testMismatchedBusFormatsFailBeforeRenderAllocation() throws {
        let unit = try FixedEQAudioUnit(
            componentDescription: FixedEQAudioUnit.componentDescription
        )
        let inputFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let outputFormat = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)
        )
        try unit.inputBusses[0].setFormat(inputFormat)
        try unit.outputBusses[0].setFormat(outputFormat)
        unit.maximumFramesToRender = 64

        XCTAssertThrowsError(try unit.allocateRenderResources()) { error in
            XCTAssertEqual(error as? FixedEQAudioUnitError, .inputOutputFormatMismatch)
        }
        XCTAssertFalse(unit.renderResourcesAllocated)
    }

    private func makeUnit(
        sampleRate: Double = 48_000,
        channelCount: Int,
        maximumFrames: Int
    ) throws -> FixedEQAudioUnit {
        let unit = try FixedEQAudioUnit(
            componentDescription: FixedEQAudioUnit.componentDescription
        )
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount)
            )
        )
        try unit.inputBusses[0].setFormat(format)
        try unit.outputBusses[0].setFormat(format)
        unit.maximumFramesToRender = AUAudioFrameCount(maximumFrames)
        try unit.allocateRenderResources()
        return unit
    }

    private func makeOutput(
        sampleRate: Double = 48_000,
        channelCount: Int,
        frameCount: Int,
        initialValue: Float = .nan
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount)
        )!
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        )!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                buffer.floatChannelData![channel][frame] = initialValue
            }
        }
        return buffer
    }

    private func samples(from buffer: AVAudioPCMBuffer, channel: Int) -> [Float] {
        Array(
            UnsafeBufferPointer(
                start: buffer.floatChannelData![channel],
                count: Int(buffer.frameLength)
            )
        )
    }

    private func render(
        unit: FixedEQAudioUnit,
        frameCount: Int,
        outputBusNumber: Int = 0,
        outputData: UnsafeMutablePointer<AudioBufferList>,
        pullInputBlock: AURenderPullInputBlock?
    ) -> (status: AUAudioUnitStatus, flags: AudioUnitRenderActionFlags) {
        var flags: AudioUnitRenderActionFlags = []
        var timestamp = AudioTimeStamp()
        let status = withUnsafeMutablePointer(to: &flags) { flagsPointer in
            withUnsafePointer(to: &timestamp) { timestampPointer in
                unit.internalRenderBlock(
                    flagsPointer,
                    timestampPointer,
                    AUAudioFrameCount(frameCount),
                    outputBusNumber,
                    outputData,
                    nil,
                    pullInputBlock
                )
            }
        }
        return (status, flags)
    }

    private func attenuationSnapshot(generation: UInt64) -> FixedEQSnapshot {
        FixedEQSnapshot(
            generation: generation,
            mode: .processed,
            bandCount: 3,
            coefficients: .identity,
            inputHeadroomLinear: 1,
            outputTrimLinear: 0.5
        )
    }

    private func telemetryMismatch(
        _ telemetry: FixedEQAudioUnitRenderTelemetry
    ) -> String? {
        guard telemetry.fault == .none else {
            return "unexpected fault \(telemetry.fault)"
        }
        guard telemetry.status == noErr else {
            return "unexpected status \(telemetry.status)"
        }
        guard !telemetry.isOriginalLatched else {
            return "Original unexpectedly latched"
        }
        guard let generation = telemetry.appliedGeneration else {
            return telemetry.processResult == .original
                ? nil
                : "initial result was \(telemetry.processResult)"
        }
        let expected: FixedEQProcessResult = generation.isMultiple(of: 2)
            ? .processed
            : .original
        return telemetry.processResult == expected
            ? nil
            : "generation \(generation) reported \(telemetry.processResult), expected \(expected)"
    }

    private func renderOffline(
        channels: [[Float]],
        sampleRate: Double,
        maximumFrameCount: AVAudioFrameCount,
        snapshot: FixedEQSnapshot
    ) async throws -> [[Float]] {
        let channelCount = channels.count
        let frameCount = channels[0].count
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount)
            )
        )
        let audioUnitNode = try await instantiateFixedEQNode()
        guard let fixedEQ = audioUnitNode.auAudioUnit as? FixedEQAudioUnit else {
            throw FixedEQOfflineRenderError.unexpectedAudioUnitType
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.attach(audioUnitNode)
        engine.connect(player, to: audioUnitNode, format: format)
        engine.connect(audioUnitNode, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(
            .offline,
            format: format,
            maximumFrameCount: maximumFrameCount
        )
        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        let inputBuffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        inputBuffer.frameLength = AVAudioFrameCount(frameCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                inputBuffer.floatChannelData![channel][frame] = channels[channel][frame]
            }
        }
        guard fixedEQ.enqueue(snapshot) else {
            throw FixedEQOfflineRenderError.mailboxFull
        }
        player.scheduleBuffer(
            inputBuffer,
            at: nil,
            options: [],
            completionHandler: nil
        )
        try engine.start()
        player.play()

        let renderBuffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: maximumFrameCount
            )
        )
        var rendered = Array(repeating: [Float](), count: channelCount)
        for channel in 0..<channelCount {
            rendered[channel].reserveCapacity(frameCount)
        }
        var stalledRenderCount = 0

        while rendered[0].count < frameCount {
            let remaining = frameCount - rendered[0].count
            let requested = min(maximumFrameCount, AVAudioFrameCount(remaining))
            let status = try engine.renderOffline(requested, to: renderBuffer)
            switch status {
            case .success:
                let delivered = Int(renderBuffer.frameLength)
                guard delivered > 0 else {
                    throw FixedEQOfflineRenderError.zeroLengthSuccess
                }
                for channel in 0..<channelCount {
                    rendered[channel].append(
                        contentsOf: UnsafeBufferPointer(
                            start: renderBuffer.floatChannelData![channel],
                            count: delivered
                        )
                    )
                }
                stalledRenderCount = 0
            case .insufficientDataFromInputNode, .cannotDoInCurrentContext:
                stalledRenderCount += 1
                guard stalledRenderCount <= 8 else {
                    throw FixedEQOfflineRenderError.renderStalled(status)
                }
            case .error:
                throw FixedEQOfflineRenderError.engineReportedError
            @unknown default:
                throw FixedEQOfflineRenderError.unknownStatus
            }
        }
        return rendered
    }

    private func instantiateFixedEQNode() async throws -> AVAudioUnit {
        FixedEQAudioUnit.registerComponent()
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(
                with: FixedEQAudioUnit.componentDescription,
                options: []
            ) { audioUnit, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let audioUnit {
                    continuation.resume(returning: audioUnit)
                } else {
                    continuation.resume(
                        throwing: FixedEQOfflineRenderError.instantiationReturnedNil
                    )
                }
            }
        }
    }
}

private enum FixedEQOfflineRenderError: Error {
    case instantiationReturnedNil
    case unexpectedAudioUnitType
    case mailboxFull
    case zeroLengthSuccess
    case renderStalled(AVAudioEngineManualRenderingStatus)
    case engineReportedError
    case unknownStatus
}

private final class RenderInputFixture: @unchecked Sendable {
    private let pointers: [UnsafeMutablePointer<Float>]
    private let channelCount: Int
    private let frameCount: Int

    var rawPointers: [UnsafeMutableRawPointer] {
        pointers.map(UnsafeMutableRawPointer.init)
    }

    init(channels: [[Float]]) {
        precondition(!channels.isEmpty)
        precondition(channels.allSatisfy { $0.count == channels[0].count })
        channelCount = channels.count
        frameCount = channels[0].count
        pointers = channels.map { samples in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
            samples.withUnsafeBufferPointer { source in
                pointer.initialize(from: source.baseAddress!, count: samples.count)
            }
            return pointer
        }
    }

    deinit {
        for pointer in pointers {
            pointer.deinitialize(count: frameCount)
            pointer.deallocate()
        }
    }

    func copyingPullBlock(
        restorationObservation: PullPointerRestorationObservation? = nil
    ) -> AURenderPullInputBlock {
        { [self] _, _, requestedFrameCount, _, inputData in
            let requestedFrames = Int(requestedFrameCount)
            let byteCount = requestedFrames * MemoryLayout<Float>.stride
            let buffers = UnsafeMutableAudioBufferListPointer(inputData)
            guard requestedFrames <= frameCount, buffers.count == channelCount else {
                return kAudio_ParamError
            }
            restorationObservation?.observe(buffers)
            for channel in 0..<channelCount {
                guard let destination = buffers[channel].mData,
                      Int(buffers[channel].mDataByteSize) >= byteCount else {
                    return kAudio_ParamError
                }
                memcpy(destination, pointers[channel], byteCount)
                buffers[channel].mNumberChannels = 1
                buffers[channel].mDataByteSize = UInt32(byteCount)
            }
            return noErr
        }
    }

    func replacingPullBlock() -> AURenderPullInputBlock {
        { [self] _, _, requestedFrameCount, _, inputData in
            let requestedFrames = Int(requestedFrameCount)
            let byteCount = requestedFrames * MemoryLayout<Float>.stride
            let buffers = UnsafeMutableAudioBufferListPointer(inputData)
            guard requestedFrames <= frameCount, buffers.count == channelCount else {
                return kAudio_ParamError
            }
            for channel in 0..<channelCount {
                buffers[channel].mNumberChannels = 1
                buffers[channel].mDataByteSize = UInt32(byteCount)
                buffers[channel].mData = UnsafeMutableRawPointer(pointers[channel])
            }
            return noErr
        }
    }
}

private final class PullPointerRestorationObservation: @unchecked Sendable {
    private let previousPointers: [UnsafeMutableRawPointer]
    private let restored = Atomic<Bool>(false)

    init(previousPointers: [UnsafeMutableRawPointer]) {
        self.previousPointers = previousPointers
    }

    var didRestoreOwnedPointers: Bool {
        restored.load(ordering: .acquiring)
    }

    func observe(_ buffers: UnsafeMutableAudioBufferListPointer) {
        guard buffers.count == previousPointers.count else { return }
        let allRestored = previousPointers.indices.allSatisfy { channel in
            buffers[channel].mData != previousPointers[channel]
        }
        restored.store(allRestored, ordering: .releasing)
    }
}

private final class BorrowedRenderPointers: @unchecked Sendable {
    private let pointers: [UnsafeMutableRawPointer]
    private let byteCount: Int

    init(pointers: [UnsafeMutableRawPointer], byteCount: Int) {
        self.pointers = pointers
        self.byteCount = byteCount
    }

    func replacingPullBlock() -> AURenderPullInputBlock {
        { [self] _, _, requestedFrameCount, _, inputData in
            guard Int(requestedFrameCount) * MemoryLayout<Float>.stride <= byteCount else {
                return kAudio_ParamError
            }
            let buffers = UnsafeMutableAudioBufferListPointer(inputData)
            guard buffers.count == pointers.count else { return kAudio_ParamError }
            for channel in pointers.indices {
                buffers[channel].mNumberChannels = 1
                buffers[channel].mDataByteSize = UInt32(byteCount)
                buffers[channel].mData = pointers[channel]
            }
            return noErr
        }
    }
}

private final class ConcurrentFixedEQRenderLoop: @unchecked Sendable {
    private let renderBlock: AUInternalRenderBlock
    private let pullInputBlock: AURenderPullInputBlock
    private let output: UnsafeMutableAudioBufferListPointer
    private let outputStorage: UnsafeMutablePointer<Float>
    private let frameCount: Int
    private let stopRequested = Atomic<Bool>(false)
    private let observedStatus = Atomic<Int32>(noErr)

    init(renderBlock: @escaping AUInternalRenderBlock, frameCount: Int) {
        self.renderBlock = renderBlock
        self.frameCount = frameCount
        let input = RenderInputFixture(
            channels: [[0.125, -0.25, 0.375, -0.5]]
        )
        pullInputBlock = input.copyingPullBlock()
        let output = AudioBufferList.allocate(maximumBuffers: 1)
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        storage.initialize(repeating: 0, count: frameCount)
        output[0].mNumberChannels = 1
        output[0].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.stride)
        output[0].mData = UnsafeMutableRawPointer(storage)
        self.output = output
        outputStorage = storage
    }

    deinit {
        outputStorage.deinitialize(count: frameCount)
        outputStorage.deallocate()
        free(output.unsafeMutablePointer)
    }

    var lastStatus: OSStatus {
        observedStatus.load(ordering: .acquiring)
    }

    func requestStop() {
        stopRequested.store(true, ordering: .releasing)
    }

    func run() {
        var flags: AudioUnitRenderActionFlags = []
        var timestamp = AudioTimeStamp()
        while !stopRequested.load(ordering: .acquiring) {
            let status = withUnsafeMutablePointer(to: &flags) { flagsPointer in
                withUnsafePointer(to: &timestamp) { timestampPointer in
                    renderBlock(
                        flagsPointer,
                        timestampPointer,
                        AUAudioFrameCount(frameCount),
                        0,
                        output.unsafeMutablePointer,
                        nil,
                        pullInputBlock
                    )
                }
            }
            if status != noErr {
                observedStatus.store(status, ordering: .releasing)
            }
        }
    }
}
