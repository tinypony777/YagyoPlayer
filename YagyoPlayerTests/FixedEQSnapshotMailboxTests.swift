import Darwin
import Dispatch
import Synchronization
import XCTest

@testable import YagyoPlayer

final class FixedEQSnapshotMailboxTests: XCTestCase {
    func testMailboxRejectsOverwriteAndDropsStaleSnapshotsWhenLatestIsConsumed() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              var consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }

        if let duplicateProducer = mailbox.takeProducer() {
            _ = consume duplicateProducer
            XCTFail("producer endpoint must not be available twice")
        }
        if let duplicateConsumer = mailbox.takeConsumer() {
            _ = consume duplicateConsumer
            XCTFail("consumer endpoint must not be available twice")
        }

        XCTAssertEqual(FixedEQSnapshotMailbox.capacity.nonzeroBitCount, 1)

        for generation in 1...FixedEQSnapshotMailbox.capacity {
            XCTAssertTrue(producer.enqueue(.original(generation: UInt64(generation))))
        }
        XCTAssertFalse(producer.enqueue(.original(generation: 99)))

        XCTAssertEqual(consumer.dequeueLatest()?.generation, UInt64(FixedEQSnapshotMailbox.capacity))
        XCTAssertNil(consumer.dequeueLatest())

        XCTAssertTrue(producer.enqueue(.original(generation: 100)))
        XCTAssertEqual(consumer.dequeueLatest()?.generation, 100)
    }

    func testRenderProcessorConsumesNewestSnapshotAtBufferBoundary() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(consumer: consume consumer)
        XCTAssertTrue(producer.enqueue(.original(generation: 10)))
        XCTAssertTrue(producer.enqueue(processedAttenuationSnapshot(generation: 11)))

        let input: [Float] = [0.25, -0.5, 0.75, -1]
        var firstOutput = Array(repeating: Float.nan, count: input.count)
        let firstReport = input.withUnsafeBufferPointer { inputBuffer in
            firstOutput.withUnsafeMutableBufferPointer { outputBuffer in
                processor.process(
                    inputLeft: inputBuffer,
                    inputRight: nil,
                    outputLeft: outputBuffer,
                    outputRight: nil,
                    frameCount: input.count
                )
            }
        }

        XCTAssertEqual(firstReport.appliedGeneration, 11)
        XCTAssertEqual(firstReport.processResult, .processed)
        XCTAssertEqual(firstOutput[0], input[0] * Float(pow(10, -6.0 / 20.0)), accuracy: 1e-6)
        XCTAssertNotEqual(firstOutput, input)

        var secondOutput = Array(repeating: Float.nan, count: input.count)
        let secondReport = input.withUnsafeBufferPointer { inputBuffer in
            secondOutput.withUnsafeMutableBufferPointer { outputBuffer in
                processor.process(
                    inputLeft: inputBuffer,
                    inputRight: nil,
                    outputLeft: outputBuffer,
                    outputRight: nil,
                    frameCount: input.count
                )
            }
        }

        XCTAssertNil(secondReport.appliedGeneration)
        XCTAssertEqual(secondReport.processResult, .processed)
        XCTAssertEqual(secondOutput[0], firstOutput[0], accuracy: 1e-6)
    }

    func testOptInTransitionRampsBothDirectionsAndAcknowledgesOriginalAtNextBoundary() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(
            consumer: consume consumer,
            transitionFrameCount: 4
        )
        let input = Array(repeating: Float(1), count: 4)

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 1, trim: 0.5)))
        let processed = render(input, through: &processor)
        XCTAssertEqual(processed.output, [1, 0.875, 0.75, 0.625])
        XCTAssertEqual(processed.report.appliedGeneration, 1)
        XCTAssertEqual(processed.report.transitionState, .steadyProcessed)

        XCTAssertTrue(producer.enqueue(.original(generation: 2)))
        let fadingToOriginal = render(input, through: &processor)
        XCTAssertEqual(fadingToOriginal.output, [0.5, 0.625, 0.75, 0.875])
        XCTAssertNil(fadingToOriginal.report.appliedGeneration)
        XCTAssertEqual(fadingToOriginal.report.transitionState, .rampingToOriginal)

        let original = render(input, through: &processor)
        XCTAssertEqual(original.output.map(\.bitPattern), input.map(\.bitPattern))
        XCTAssertEqual(original.report.appliedGeneration, 2)
        XCTAssertEqual(original.report.processResult, .original)
        XCTAssertEqual(original.report.transitionState, .steadyOriginal)
    }

    func testTransitionReversesSameRecipeAndFadesDifferentRecipeThroughDry() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(
            consumer: consume consumer,
            transitionFrameCount: 4
        )
        let input = Array(repeating: Float(1), count: 4)

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 1, trim: 0.5)))
        _ = render(input, through: &processor)

        XCTAssertTrue(producer.enqueue(.original(generation: 2)))
        let partialFadeOut = render([1, 1], through: &processor)
        XCTAssertEqual(partialFadeOut.output, [0.5, 0.625])
        XCTAssertEqual(partialFadeOut.report.transitionState, .rampingToOriginal)

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 3, trim: 0.5)))
        let reversed = render([1, 1], through: &processor)
        XCTAssertEqual(reversed.output, [0.75, 0.625])
        XCTAssertEqual(reversed.report.appliedGeneration, 3)
        XCTAssertEqual(reversed.report.transitionState, .steadyProcessed)

        XCTAssertTrue(
            producer.enqueue(
                processedLinearSnapshot(generation: 4, trim: 0.25)
            )
        )
        let replacementFadeOut = render(input, through: &processor)
        XCTAssertEqual(replacementFadeOut.output, [0.5, 0.625, 0.75, 0.875])
        XCTAssertNil(replacementFadeOut.report.appliedGeneration)
        XCTAssertEqual(replacementFadeOut.report.transitionState, .replacingProcessed)

        let replacementFadeIn = render(input, through: &processor)
        XCTAssertEqual(replacementFadeIn.output[0], 1, accuracy: 1e-6)
        XCTAssertEqual(replacementFadeIn.output[1], 0.8125, accuracy: 1e-6)
        XCTAssertEqual(replacementFadeIn.output[2], 0.625, accuracy: 1e-6)
        XCTAssertEqual(replacementFadeIn.output[3], 0.4375, accuracy: 1e-6)
        XCTAssertEqual(replacementFadeIn.report.appliedGeneration, 4)
        XCTAssertEqual(replacementFadeIn.report.transitionState, .steadyProcessed)
    }

    func testTransitionResetRestartsFromDryWithoutLosingPendingGeneration() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(
            consumer: consume consumer,
            transitionFrameCount: 4
        )

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 7, trim: 0.5)))
        let partial = render([1, 1], through: &processor)
        XCTAssertEqual(partial.output, [1, 0.875])
        XCTAssertNil(partial.report.appliedGeneration)

        processor.reset()
        let restarted = render([1, 1, 1, 1], through: &processor)
        XCTAssertEqual(restarted.output, [1, 0.875, 0.75, 0.625])
        XCTAssertEqual(restarted.report.appliedGeneration, 7)
        XCTAssertEqual(restarted.report.transitionState, .steadyProcessed)
    }

    func testTransitionFaultReturnsOriginalAndRequiresExplicitRecoverySnapshot() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(
            consumer: consume consumer,
            transitionFrameCount: 4
        )

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 1, trim: 0.5)))
        let fault = render([1, .nan, .infinity, -.infinity], through: &processor)
        XCTAssertEqual(fault.output, [1, 0, 0, 0])
        XCTAssertEqual(fault.report.processResult, .latchedOriginal)
        XCTAssertEqual(fault.report.transitionState, .steadyOriginal)

        let stillLatched = render([1, 1, 1, 1], through: &processor)
        XCTAssertEqual(stillLatched.output, [1, 1, 1, 1])
        XCTAssertEqual(stillLatched.report.processResult, .original)
        XCTAssertNil(stillLatched.report.appliedGeneration)

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 2, trim: 0.5)))
        let recovered = render([1, 1, 1, 1], through: &processor)
        XCTAssertEqual(recovered.output, [1, 0.875, 0.75, 0.625])
        XCTAssertEqual(recovered.report.appliedGeneration, 2)
        XCTAssertEqual(recovered.report.transitionState, .steadyProcessed)
    }

    func testDisablingTransitionCommitsPendingTargetAtNextBoundary() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(
            consumer: consume consumer,
            transitionFrameCount: 4
        )

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 1, trim: 0.5)))
        _ = render([1, 1, 1, 1], through: &processor)
        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 2, trim: 0.25)))
        _ = render([1, 1], through: &processor)

        processor.configureTransition(frameCount: 0)
        let committed = render([1, 1], through: &processor)
        XCTAssertEqual(committed.output, [0.25, 0.25])
        XCTAssertEqual(committed.report.appliedGeneration, 2)
        XCTAssertEqual(committed.report.transitionState, .steadyProcessed)
    }

    func testSameRecipeReversalPreservesIIRHistory() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(
            consumer: consume consumer,
            transitionFrameCount: 4
        )

        XCTAssertTrue(producer.enqueue(tailSnapshot(generation: 1)))
        _ = render([1, 0, 0, 0], through: &processor)
        XCTAssertTrue(producer.enqueue(.original(generation: 2)))
        _ = render([0], through: &processor)

        XCTAssertTrue(producer.enqueue(tailSnapshot(generation: 3)))
        let reversed = render([0], through: &processor)
        XCTAssertGreaterThan(abs(reversed.output[0]), 1e-8)
        XCTAssertEqual(reversed.report.appliedGeneration, 3)
        XCTAssertEqual(reversed.report.transitionState, .steadyProcessed)
    }

    func testTransitionOutputIsInvariantAcrossRenderChunking() {
        var singleMailbox = FixedEQSnapshotMailbox()
        guard var singleProducer = singleMailbox.takeProducer(),
              let singleConsumer = singleMailbox.takeConsumer() else {
            return XCTFail("single-buffer endpoints must be available")
        }
        var singleProcessor = FixedEQRenderProcessor(
            consumer: consume singleConsumer,
            transitionFrameCount: 7
        )
        XCTAssertTrue(
            singleProducer.enqueue(processedLinearSnapshot(generation: 1, trim: 0.5))
        )
        let single = render(Array(repeating: 1, count: 10), through: &singleProcessor)

        var chunkedMailbox = FixedEQSnapshotMailbox()
        guard var chunkedProducer = chunkedMailbox.takeProducer(),
              let chunkedConsumer = chunkedMailbox.takeConsumer() else {
            return XCTFail("chunked endpoints must be available")
        }
        var chunkedProcessor = FixedEQRenderProcessor(
            consumer: consume chunkedConsumer,
            transitionFrameCount: 7
        )
        XCTAssertTrue(
            chunkedProducer.enqueue(processedLinearSnapshot(generation: 1, trim: 0.5))
        )
        var chunkedOutput: [Float] = []
        var lastReport: FixedEQRenderReport?
        for frameCount in [2, 3, 5] {
            let chunk = render(
                Array(repeating: 1, count: frameCount),
                through: &chunkedProcessor
            )
            chunkedOutput.append(contentsOf: chunk.output)
            lastReport = chunk.report
        }

        XCTAssertEqual(chunkedOutput, single.output)
        XCTAssertEqual(single.report.appliedGeneration, 1)
        XCTAssertEqual(lastReport?.appliedGeneration, 1)
        XCTAssertEqual(lastReport?.transitionState, .steadyProcessed)
    }

    func testLatestSnapshotSupersedesReplacementAtExactDryBoundary() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              let consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        var processor = FixedEQRenderProcessor(
            consumer: consume consumer,
            transitionFrameCount: 4
        )
        let input = Array(repeating: Float(1), count: 4)

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 1, trim: 0.5)))
        _ = render(input, through: &processor)
        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 2, trim: 0.25)))
        let dryBoundary = render(input, through: &processor)
        XCTAssertNil(dryBoundary.report.appliedGeneration)
        XCTAssertEqual(dryBoundary.report.transitionState, .replacingProcessed)

        XCTAssertTrue(producer.enqueue(processedLinearSnapshot(generation: 3, trim: 0.125)))
        let newest = render(input, through: &processor)
        XCTAssertEqual(newest.output, [1, 0.78125, 0.5625, 0.34375])
        XCTAssertEqual(newest.report.appliedGeneration, 3)
        XCTAssertEqual(newest.report.transitionState, .steadyProcessed)
    }

    func testSingleProducerConsumerRemainsMonotonicAcrossRingWraps() {
        var mailbox = FixedEQSnapshotMailbox()
        guard var producer = mailbox.takeProducer(),
              var consumer = mailbox.takeConsumer() else {
            return XCTFail("SPSC endpoints must be available exactly once")
        }
        let state = MailboxStressState()
        let group = DispatchGroup()
        let finalGeneration: UInt64 = 20_000

        group.enter()
        DispatchQueue(label: "FixedEQSnapshotMailboxTests.producer").async {
            defer { group.leave() }
            for generation in 1...finalGeneration {
                while !producer.enqueue(Self.stressSnapshot(generation: generation)) {
                    if state.shouldStop {
                        return
                    }
                    sched_yield()
                }
            }
        }

        group.enter()
        DispatchQueue(label: "FixedEQSnapshotMailboxTests.consumer").async {
            defer { group.leave() }
            var previous: UInt64 = 0
            while previous < finalGeneration, !state.shouldStop {
                guard let snapshot = consumer.dequeueLatest() else {
                    sched_yield()
                    continue
                }
                if snapshot.generation <= previous {
                    state.markNonMonotonic()
                }
                if !Self.stressPayloadIsConsistent(snapshot) {
                    state.markTornPayload()
                }
                previous = snapshot.generation
            }
            state.storeFinal(previous)
        }

        let waitResult = group.wait(timeout: .now() + 5)
        if waitResult == .timedOut {
            state.requestStop()
            _ = group.wait(timeout: .now() + 1)
        }
        XCTAssertEqual(waitResult, .success)
        XCTAssertTrue(state.isMonotonic)
        XCTAssertTrue(state.isPayloadConsistent)
        XCTAssertEqual(state.finalGeneration, finalGeneration)
    }

    private func processedAttenuationSnapshot(
        generation: UInt64,
        id: String = "mailbox-test-attenuation",
        outputTrimDB: Double = -6
    ) -> FixedEQSnapshot {
        FixedEQSnapshotFactory.make(
            recipe: FixedEQRecipe(
                id: id,
                catalogVersion: 1,
                inputHeadroomDB: 0,
                bands: [
                    FixedEQBand(frequencyHz: 200, gainDB: 0, q: 1),
                    FixedEQBand(frequencyHz: 1_000, gainDB: 0, q: 1),
                    FixedEQBand(frequencyHz: 5_000, gainDB: 0, q: 1),
                ],
                outputTrimDB: outputTrimDB
            ),
            sampleRate: 48_000,
            generation: generation
        )
    }

    private func processedLinearSnapshot(
        generation: UInt64,
        trim: Float
    ) -> FixedEQSnapshot {
        FixedEQSnapshot(
            generation: generation,
            mode: .processed,
            bandCount: 3,
            coefficients: .identity,
            inputHeadroomLinear: 1,
            outputTrimLinear: trim
        )
    }

    private func tailSnapshot(generation: UInt64) -> FixedEQSnapshot {
        FixedEQSnapshotFactory.make(
            recipe: FixedEQRecipe(
                id: "mailbox-test-tail",
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
            generation: generation
        )
    }

    private func render(
        _ input: [Float],
        through processor: inout FixedEQRenderProcessor
    ) -> (output: [Float], report: FixedEQRenderReport) {
        var output = Array(repeating: Float.nan, count: input.count)
        let report = input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                processor.process(
                    inputLeft: inputBuffer,
                    inputRight: nil,
                    outputLeft: outputBuffer,
                    outputRight: nil,
                    frameCount: input.count
                )
            }
        }
        return (output, report)
    }

    private static func stressSnapshot(generation: UInt64) -> FixedEQSnapshot {
        let bandCount = Int(generation % 3) + FixedEQRecipeContract.minimumBandCount
        let marker = Float((generation % 997) + 1) / 1_000
        let coefficient = BiquadCoefficients(
            b0: marker,
            b1: -marker,
            b2: marker * 0.5,
            a1: 0,
            a2: 0
        )
        return FixedEQSnapshot(
            generation: generation,
            mode: .processed,
            bandCount: bandCount,
            coefficients: FixedEQCoefficientSet(
                Array(repeating: coefficient, count: bandCount)
            )!,
            inputHeadroomLinear: marker,
            outputTrimLinear: marker * 0.5
        )
    }

    private static func stressPayloadIsConsistent(_ snapshot: FixedEQSnapshot) -> Bool {
        let expectedBandCount = Int(snapshot.generation % 3)
            + FixedEQRecipeContract.minimumBandCount
        let expectedMarker = Float((snapshot.generation % 997) + 1) / 1_000
        return snapshot.mode == .processed
            && snapshot.bandCount == expectedBandCount
            && snapshot.coefficients.first.b0 == expectedMarker
            && snapshot.coefficients.first.b1 == -expectedMarker
            && snapshot.inputHeadroomLinear == expectedMarker
            && snapshot.outputTrimLinear == expectedMarker * 0.5
    }
}

private final class MailboxStressState: @unchecked Sendable {
    private let monotonic = Atomic<Bool>(true)
    private let payloadConsistent = Atomic<Bool>(true)
    private let observedGeneration = Atomic<UInt64>(0)
    private let stopRequested = Atomic<Bool>(false)

    var isMonotonic: Bool {
        monotonic.load(ordering: .acquiring)
    }

    var finalGeneration: UInt64 {
        observedGeneration.load(ordering: .acquiring)
    }

    var isPayloadConsistent: Bool {
        payloadConsistent.load(ordering: .acquiring)
    }

    var shouldStop: Bool {
        stopRequested.load(ordering: .acquiring)
    }

    func markNonMonotonic() {
        monotonic.store(false, ordering: .releasing)
    }

    func markTornPayload() {
        payloadConsistent.store(false, ordering: .releasing)
    }

    func storeFinal(_ generation: UInt64) {
        observedGeneration.store(generation, ordering: .releasing)
    }

    func requestStop() {
        stopRequested.store(true, ordering: .releasing)
    }
}
