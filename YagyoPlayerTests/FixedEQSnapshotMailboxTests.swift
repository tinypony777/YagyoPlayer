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

    private func processedAttenuationSnapshot(generation: UInt64) -> FixedEQSnapshot {
        FixedEQSnapshotFactory.make(
            recipe: FixedEQRecipe(
                id: "mailbox-test-attenuation",
                catalogVersion: 1,
                inputHeadroomDB: 0,
                bands: [
                    FixedEQBand(frequencyHz: 200, gainDB: 0, q: 1),
                    FixedEQBand(frequencyHz: 1_000, gainDB: 0, q: 1),
                    FixedEQBand(frequencyHz: 5_000, gainDB: 0, q: 1),
                ],
                outputTrimDB: -6
            ),
            sampleRate: 48_000,
            generation: generation
        )
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
