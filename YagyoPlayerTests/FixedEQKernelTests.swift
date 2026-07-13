import Foundation
import XCTest

@testable import YagyoPlayer

final class FixedEQKernelTests: XCTestCase {
    private let sampleRates = [44_100.0, 48_000.0, 96_000.0]

    func testValidRecipeBuildsProcessedSnapshot() {
        let snapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(inputHeadroomDB: -3, outputTrimDB: -1),
            sampleRate: 48_000,
            generation: 42
        )

        XCTAssertEqual(snapshot.mode, .processed)
        XCTAssertEqual(snapshot.generation, 42)
        XCTAssertEqual(snapshot.bandCount, 3)
        XCTAssertEqual(snapshot.inputHeadroomLinear, Float(pow(10, -3.0 / 20.0)), accuracy: 1e-6)
        XCTAssertEqual(snapshot.outputTrimLinear, Float(pow(10, -1.0 / 20.0)), accuracy: 1e-6)
        XCTAssertTrue(snapshot.coefficients.allFiniteAndStable)
    }

    func testContractBoundariesAndFourOrFiveBandsRemainProcessable() {
        for bandCount in [4, 5] {
            var bands = [
                FixedEQBand(frequencyHz: 120, gainDB: -3, q: 0.5),
                FixedEQBand(frequencyHz: 400, gainDB: 0, q: 1),
                FixedEQBand(frequencyHz: 2_000, gainDB: 0, q: 1),
                FixedEQBand(frequencyHz: 6_000, gainDB: 3, q: 2),
            ]
            if bandCount == 5 {
                bands.append(FixedEQBand(frequencyHz: 12_000, gainDB: -3, q: 0.5))
            }
            let snapshot = FixedEQSnapshotFactory.make(
                recipe: recipe(inputHeadroomDB: -3, bands: bands),
                sampleRate: 48_000,
                generation: UInt64(bandCount)
            )
            let impulse: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
            let result = renderMono(snapshot: snapshot, input: impulse, chunkSizes: [3])

            XCTAssertEqual(snapshot.mode, .processed)
            XCTAssertEqual(snapshot.bandCount, bandCount)
            XCTAssertTrue(result.results.allSatisfy { $0 == .processed })
            XCTAssertTrue(result.output.allSatisfy(\.isFinite))
            XCTAssertNotEqual(result.output[0].bitPattern, impulse[0].bitPattern)
        }
    }

    func testRecipeValidationFailsClosedToOriginal() {
        let validBands = fixtureBands()
        let invalidRecipes = [
            recipe(bands: Array(validBands.prefix(2))),
            recipe(bands: validBands + validBands + [validBands[0]]),
            recipe(bands: replacingBand(validBands, at: 0, gainDB: 3.001)),
            recipe(bands: replacingBand(validBands, at: 0, gainDB: -3.001)),
            recipe(bands: replacingBand(validBands, at: 0, frequencyHz: 0)),
            recipe(bands: replacingBand(validBands, at: 0, frequencyHz: 19.999)),
            recipe(bands: replacingBand(validBands, at: 0, frequencyHz: 20_000.001)),
            recipe(bands: replacingBand(validBands, at: 0, frequencyHz: 24_000)),
            recipe(bands: replacingBand(validBands, at: 0, q: 0.49)),
            recipe(bands: replacingBand(validBands, at: 0, q: 2.01)),
            recipe(bands: replacingBand(validBands, at: 0, frequencyHz: .nan)),
            recipe(bands: replacingBand(validBands, at: 0, gainDB: .infinity)),
            recipe(bands: replacingBand(validBands, at: 0, q: -.infinity)),
            recipe(inputHeadroomDB: 0.001, bands: validBands),
            recipe(inputHeadroomDB: .nan, bands: validBands),
            recipe(bands: validBands, outputTrimDB: 0.001),
            recipe(bands: validBands, outputTrimDB: -.infinity),
            FixedEQRecipe(
                id: "",
                catalogVersion: 1,
                inputHeadroomDB: -3,
                bands: validBands,
                outputTrimDB: 0
            ),
            FixedEQRecipe(
                id: "fixture",
                catalogVersion: 0,
                inputHeadroomDB: -3,
                bands: validBands,
                outputTrimDB: 0
            ),
        ]

        for (index, recipe) in invalidRecipes.enumerated() {
            let snapshot = FixedEQSnapshotFactory.make(
                recipe: recipe,
                sampleRate: 48_000,
                generation: UInt64(index + 1)
            )
            XCTAssertEqual(snapshot.mode, .original, "invalid recipe index \(index)")
        }

        for sampleRate in [Double.nan, .infinity, 0, -48_000] {
            XCTAssertEqual(
                FixedEQSnapshotFactory.make(
                    recipe: fixtureRecipe(),
                    sampleRate: sampleRate,
                    generation: 1
                ).mode,
                .original
            )
        }
    }

    func testInputHeadroomMustCoverSummedPositiveBandGain() {
        let fiveBoosts = (0..<5).map { _ in
            FixedEQBand(frequencyHz: 1_000, gainDB: 3, q: 1)
        }

        XCTAssertEqual(
            FixedEQSnapshotFactory.make(
                recipe: recipe(inputHeadroomDB: 0, bands: fiveBoosts),
                sampleRate: 48_000,
                generation: 1
            ).mode,
            .original
        )
        XCTAssertEqual(
            FixedEQSnapshotFactory.make(
                recipe: recipe(inputHeadroomDB: -14.999, bands: fiveBoosts),
                sampleRate: 48_000,
                generation: 2
            ).mode,
            .original
        )

        let protected = FixedEQSnapshotFactory.make(
            recipe: recipe(inputHeadroomDB: -15, bands: fiveBoosts),
            sampleRate: 48_000,
            generation: 3
        )
        XCTAssertEqual(protected.mode, .processed)
        XCTAssertEqual(protected.inputHeadroomLinear, Float(pow(10, -15.0 / 20.0)), accuracy: 1e-7)
    }

    func testOriginalIsBitTransparentForFiniteMonoAndStereoAcrossChunkSizes() {
        var left = (0..<2_051).map { index in
            Float(sin(Double(index) * 0.071) * 0.75)
        }
        left[0] = 0
        left[1] = -0.0
        left[2] = Float.leastNonzeroMagnitude
        let right = left.reversed()

        for sampleRate in sampleRates {
            _ = sampleRate // Original is deliberately independent of format-specific coefficients.
            for chunkSize in [1, 7, 64, 257, 1_024, 2_048] {
                let mono = renderMono(
                    snapshot: .original(generation: 1),
                    input: left,
                    chunkSizes: [chunkSize]
                )
                XCTAssertTrue(mono.results.allSatisfy { $0 == .original })
                XCTAssertEqual(mono.output.map(\.bitPattern), left.map(\.bitPattern))

                let stereo = renderStereo(
                    snapshot: .original(generation: 1),
                    left: left,
                    right: Array(right),
                    chunkSizes: [chunkSize]
                )
                XCTAssertTrue(stereo.results.allSatisfy { $0 == .original })
                XCTAssertEqual(stereo.left.map(\.bitPattern), left.map(\.bitPattern))
                XCTAssertEqual(stereo.right.map(\.bitPattern), right.map(\.bitPattern))
            }
        }
    }

    func testOriginalSanitizesNonFiniteMonoAndStereoAndLatches() {
        let monoInput: [Float] = [0.25, .nan, .infinity, -.infinity, -0.0]
        let mono = renderMono(
            snapshot: .original(generation: 1),
            input: monoInput,
            chunkSizes: [monoInput.count]
        )

        XCTAssertEqual(mono.results, [.latchedOriginal])
        XCTAssertEqual(mono.output[0].bitPattern, monoInput[0].bitPattern)
        XCTAssertEqual(mono.output[1], 0)
        XCTAssertEqual(mono.output[2], 0)
        XCTAssertEqual(mono.output[3], 0)
        XCTAssertEqual(mono.output[4].bitPattern, monoInput[4].bitPattern)
        XCTAssertTrue(mono.output.allSatisfy(\.isFinite))

        let rightInput: [Float] = [.nan, -0.5, .infinity, 0.75, -.infinity]
        let stereo = renderStereo(
            snapshot: .original(generation: 1),
            left: monoInput,
            right: rightInput,
            chunkSizes: [monoInput.count]
        )

        XCTAssertEqual(stereo.results, [.latchedOriginal])
        XCTAssertTrue(stereo.left.allSatisfy(\.isFinite))
        XCTAssertTrue(stereo.right.allSatisfy(\.isFinite))
        XCTAssertEqual(stereo.left, [0.25, 0, 0, 0, -0.0])
        XCTAssertEqual(stereo.right, [0, -0.5, 0, 0.75, 0])
    }

    func testImpulseIsFiniteAndChunkInvariantAndResetClearsTail() {
        let snapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(),
            sampleRate: 48_000,
            generation: 1
        )
        var impulse = [Float](repeating: 0, count: 4_096)
        impulse[0] = 1

        let whole = renderMono(snapshot: snapshot, input: impulse, chunkSizes: [4_096])
        let chunked = renderMono(
            snapshot: snapshot,
            input: impulse,
            chunkSizes: [1, 7, 64, 257, 1_024, 2_048]
        )

        XCTAssertTrue(whole.output.allSatisfy(\.isFinite))
        XCTAssertEqual(whole.output.map(\.bitPattern), chunked.output.map(\.bitPattern))

        var kernel = FixedEQKernel(snapshot: snapshot)
        var impulseOutput = [Float](repeating: 0, count: impulse.count)
        XCTAssertEqual(processMono(impulse, output: &impulseOutput, kernel: &kernel), .processed)
        kernel.reset()
        let silence = [Float](repeating: 0, count: 512)
        var silenceOutput = [Float](repeating: 1, count: silence.count)
        XCTAssertEqual(processMono(silence, output: &silenceOutput, kernel: &kernel), .processed)
        XCTAssertTrue(silenceOutput.allSatisfy { $0.bitPattern == Float.zero.bitPattern })
    }

    func testPeakingCenterResponseAcrossSupportedSampleRates() {
        for sampleRate in sampleRates {
            for gainDB in [-3.0, 3.0] {
                let duration = 2.0
                let sampleCount = Int(sampleRate * duration)
                let input = (0..<sampleCount).map { index in
                    Float(0.1 * sin(2 * .pi * 1_000 * Double(index) / sampleRate))
                }
                let bands = [
                    FixedEQBand(frequencyHz: 1_000, gainDB: gainDB, q: 1),
                    FixedEQBand(frequencyHz: 4_000, gainDB: 0, q: 1),
                    FixedEQBand(frequencyHz: 8_000, gainDB: 0, q: 1),
                ]
                let snapshot = FixedEQSnapshotFactory.make(
                    recipe: recipe(
                        inputHeadroomDB: -max(gainDB, 0),
                        bands: bands
                    ),
                    sampleRate: sampleRate,
                    generation: 1
                )
                let output = renderMono(
                    snapshot: snapshot,
                    input: input,
                    chunkSizes: [257]
                ).output
                let warmup = Int(sampleRate)
                let inputRMS = rms(input[warmup...])
                let outputRMS = rms(output[warmup...])
                let measuredDB = 20 * log10(outputRMS / inputRMS)
                let measuredEQGainDB = measuredDB + max(gainDB, 0)

                XCTAssertEqual(
                    measuredEQGainDB,
                    gainDB,
                    accuracy: 0.06,
                    "sampleRate \(sampleRate)"
                )
            }
        }
    }

    func testInputHeadroomAndOutputTrimNeverAmplify() {
        for attenuationDB in [0.0, -1.0, -6.020_599_913, -24.0, -300.0] {
            let snapshot = FixedEQSnapshotFactory.make(
                recipe: fixtureRecipe(
                    inputHeadroomDB: attenuationDB,
                    gains: [0, 0, 0],
                    outputTrimDB: attenuationDB
                ),
                sampleRate: 48_000,
                generation: 1
            )
            XCTAssertEqual(snapshot.mode, .processed)
            XCTAssertGreaterThan(snapshot.inputHeadroomLinear, 0)
            XCTAssertLessThanOrEqual(snapshot.inputHeadroomLinear, 1)
            XCTAssertGreaterThan(snapshot.outputTrimLinear, 0)
            XCTAssertLessThanOrEqual(snapshot.outputTrimLinear, 1)
        }

        let halfSnapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(
                inputHeadroomDB: 0,
                gains: [0, 0, 0],
                outputTrimDB: -6.020_599_913
            ),
            sampleRate: 48_000,
            generation: 1
        )
        let input: [Float] = [0.5, -0.25, 0]
        let output = renderMono(snapshot: halfSnapshot, input: input, chunkSizes: [3]).output
        XCTAssertEqual(output[0], 0.25, accuracy: 1e-6)
        XCTAssertEqual(output[1], -0.125, accuracy: 1e-6)
        XCTAssertEqual(output[2], 0, accuracy: 1e-6)
    }

    func testProcessedSignalsStayFiniteForDCNoiseDenormalsAndProtectedFiveBandPeak() {
        let fixtureSnapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(),
            sampleRate: 48_000,
            generation: 1
        )

        let dc = [Float](repeating: 0.25, count: 4_096)
        let dcResult = renderMono(snapshot: fixtureSnapshot, input: dc, chunkSizes: [257])
        XCTAssertTrue(dcResult.results.allSatisfy { $0 == .processed })
        XCTAssertTrue(dcResult.output.allSatisfy(\.isFinite))

        var randomState: UInt64 = 0x4D59_5DF4_D0F3_3173
        let noise: [Float] = (0..<8_192).map { _ in
            randomState = randomState &* 6_364_136_223_846_793_005 &+ 1
            let unit = Double(randomState >> 11) / Double(UInt64.max >> 11)
            return Float((unit * 2 - 1) * 0.5)
        }
        let noiseResult = renderMono(
            snapshot: fixtureSnapshot,
            input: noise,
            chunkSizes: [1, 7, 64, 257]
        )
        XCTAssertTrue(noiseResult.results.allSatisfy { $0 == .processed })
        XCTAssertTrue(noiseResult.output.allSatisfy(\.isFinite))

        var denormalKernel = FixedEQKernel(snapshot: fixtureSnapshot)
        let denormals = [Float](
            repeating: Float.leastNormalMagnitude * 0.5,
            count: 64
        )
        var denormalOutput = [Float](repeating: 0, count: denormals.count)
        XCTAssertEqual(
            processMono(denormals, output: &denormalOutput, kernel: &denormalKernel),
            .processed
        )
        XCTAssertTrue(denormalOutput.allSatisfy(\.isFinite))
        let silence = [Float](repeating: 0, count: 64)
        var postDenormalSilence = [Float](repeating: 1, count: silence.count)
        XCTAssertEqual(
            processMono(silence, output: &postDenormalSilence, kernel: &denormalKernel),
            .processed
        )
        XCTAssertTrue(postDenormalSilence.allSatisfy { $0.bitPattern == Float.zero.bitPattern })

        let fiveBoosts = (0..<5).map { _ in
            FixedEQBand(frequencyHz: 1_000, gainDB: 3, q: 1)
        }
        let fiveBandSnapshot = FixedEQSnapshotFactory.make(
            recipe: recipe(inputHeadroomDB: -15, bands: fiveBoosts),
            sampleRate: 48_000,
            generation: 2
        )
        let peakFixture = (0..<48_000).map { index in
            Float(0.9 * sin(2 * .pi * 1_000 * Double(index) / 48_000))
        }
        let peakResult = renderMono(
            snapshot: fiveBandSnapshot,
            input: peakFixture,
            chunkSizes: [2_048]
        )
        XCTAssertEqual(fiveBandSnapshot.mode, .processed)
        XCTAssertTrue(peakResult.results.allSatisfy { $0 == .processed })
        XCTAssertTrue(peakResult.output.allSatisfy(\.isFinite))
        XCTAssertLessThanOrEqual(peakResult.output.map { abs($0) }.max() ?? .infinity, 0.95)
    }

    func testMonoAndStereoChannelsKeepIndependentState() {
        let snapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(),
            sampleRate: 48_000,
            generation: 1
        )
        var impulse = [Float](repeating: 0, count: 1_024)
        impulse[0] = 1
        let silence = [Float](repeating: 0, count: impulse.count)

        let mono = renderMono(snapshot: snapshot, input: impulse, chunkSizes: [257])
        let stereo = renderStereo(
            snapshot: snapshot,
            left: impulse,
            right: silence,
            chunkSizes: [257]
        )

        XCTAssertEqual(mono.output.map(\.bitPattern), stereo.left.map(\.bitPattern))
        XCTAssertTrue(stereo.right.allSatisfy { $0.bitPattern == Float.zero.bitPattern })
    }

    func testSnapshotAppliesOnlyBetweenProcessCalls() {
        let identity = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(inputHeadroomDB: 0, gains: [0, 0, 0], outputTrimDB: 0),
            sampleRate: 48_000,
            generation: 1
        )
        let attenuated = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(
                inputHeadroomDB: 0,
                gains: [0, 0, 0],
                outputTrimDB: -6.020_599_913
            ),
            sampleRate: 48_000,
            generation: 2
        )
        let input = [Float](repeating: 0.5, count: 64)
        var firstOutput = [Float](repeating: 0, count: input.count)
        var secondOutput = [Float](repeating: 0, count: input.count)
        var kernel = FixedEQKernel(snapshot: identity)

        XCTAssertEqual(processMono(input, output: &firstOutput, kernel: &kernel), .processed)
        kernel.apply(attenuated)
        XCTAssertEqual(processMono(input, output: &secondOutput, kernel: &kernel), .processed)

        XCTAssertTrue(firstOutput.allSatisfy { $0.bitPattern == Float(0.5).bitPattern })
        XCTAssertTrue(secondOutput.allSatisfy { abs($0 - 0.25) < 1e-6 })
    }

    func testInvalidDSPStateLatchesOriginalUntilExplicitValidSnapshot() throws {
        let invalidBand = BiquadCoefficients(
            b0: .infinity,
            b1: 0,
            b2: 0,
            a1: 0,
            a2: 0
        )
        let invalidCoefficients = try XCTUnwrap(FixedEQCoefficientSet([
            invalidBand,
            .identity,
            .identity,
        ]))
        let invalidSnapshot = FixedEQSnapshot(
            generation: 1,
            mode: .processed,
            bandCount: 3,
            coefficients: invalidCoefficients,
            inputHeadroomLinear: 1,
            outputTrimLinear: 1
        )
        let validSnapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(),
            sampleRate: 48_000,
            generation: 2
        )
        var kernel = FixedEQKernel(snapshot: invalidSnapshot)
        let normal = [Float](repeating: 0.25, count: 16)
        var bypassed = [Float](repeating: 0, count: normal.count)

        XCTAssertEqual(processMono(normal, output: &bypassed, kernel: &kernel), .latchedOriginal)
        XCTAssertTrue(kernel.isOriginalLatched)
        XCTAssertEqual(bypassed.map(\.bitPattern), normal.map(\.bitPattern))

        kernel.reset()
        XCTAssertTrue(kernel.isOriginalLatched)
        var stillBypassed = [Float](repeating: 0, count: normal.count)
        XCTAssertEqual(processMono(normal, output: &stillBypassed, kernel: &kernel), .original)
        XCTAssertEqual(stillBypassed.map(\.bitPattern), normal.map(\.bitPattern))

        kernel.apply(validSnapshot)
        var recovered = [Float](repeating: 0, count: normal.count)
        XCTAssertEqual(processMono(normal, output: &recovered, kernel: &kernel), .processed)
        XCTAssertFalse(kernel.isOriginalLatched)
        XCTAssertNotEqual(recovered[0].bitPattern, normal[0].bitPattern)
    }

    func testInvalidFrameCountNeverPartiallyProcesses() {
        let snapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(),
            sampleRate: 48_000,
            generation: 1
        )
        var kernel = FixedEQKernel(snapshot: snapshot)
        let input = [Float](repeating: 0.25, count: 4)
        var output = [Float](repeating: -99, count: 4)
        let before = output
        var result: FixedEQProcessResult = .processed

        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                result = kernel.process(
                    inputLeft: inputBuffer,
                    inputRight: nil,
                    outputLeft: outputBuffer,
                    outputRight: nil,
                    frameCount: 5
                )
            }
        }

        XCTAssertEqual(result, .invalidBuffers)
        XCTAssertEqual(output, before)
        XCTAssertTrue(kernel.isOriginalLatched)
    }

    func testProcessedPathRejectsAliasedBuffersWithoutMutation() {
        let snapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(),
            sampleRate: 48_000,
            generation: 1
        )
        var kernel = FixedEQKernel(snapshot: snapshot)
        var samples: [Float] = [0.25, -0.5, 0.75]
        let before = samples
        var result: FixedEQProcessResult = .processed

        samples.withUnsafeMutableBufferPointer { buffer in
            result = kernel.process(
                inputLeft: UnsafeBufferPointer(buffer),
                inputRight: nil,
                outputLeft: buffer,
                outputRight: nil,
                frameCount: buffer.count
            )
        }

        XCTAssertEqual(result, .invalidBuffers)
        XCTAssertEqual(samples.map(\.bitPattern), before.map(\.bitPattern))
        XCTAssertTrue(kernel.isOriginalLatched)
    }

    func testStereoRejectsCrossChannelAndSharedOutputAliases() {
        let frameCount = 8
        let inputLeftPointer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        let inputRightPointer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        let outputLeftPointer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        let outputRightPointer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer {
            inputLeftPointer.deallocate()
            inputRightPointer.deallocate()
            outputLeftPointer.deallocate()
            outputRightPointer.deallocate()
        }
        inputLeftPointer.initialize(repeating: 0.25, count: frameCount)
        inputRightPointer.initialize(repeating: -0.5, count: frameCount)
        outputLeftPointer.initialize(repeating: -99, count: frameCount)
        outputRightPointer.initialize(repeating: -98, count: frameCount)

        let snapshot = FixedEQSnapshotFactory.make(
            recipe: fixtureRecipe(),
            sampleRate: 48_000,
            generation: 1
        )
        let inputLeft = UnsafeBufferPointer(start: inputLeftPointer, count: frameCount)
        let inputRight = UnsafeBufferPointer(start: inputRightPointer, count: frameCount)
        let outputLeft = UnsafeMutableBufferPointer(start: outputLeftPointer, count: frameCount)
        let outputRight = UnsafeMutableBufferPointer(start: outputRightPointer, count: frameCount)
        var kernel = FixedEQKernel(snapshot: snapshot)

        XCTAssertEqual(
            kernel.process(
                inputLeft: inputLeft,
                inputRight: inputRight,
                outputLeft: outputLeft,
                outputRight: UnsafeMutableBufferPointer(
                    start: inputLeftPointer,
                    count: frameCount
                ),
                frameCount: frameCount
            ),
            .invalidBuffers
        )
        XCTAssertTrue(inputLeft.allSatisfy { $0 == 0.25 })

        kernel.apply(snapshot)
        XCTAssertEqual(
            kernel.process(
                inputLeft: inputLeft,
                inputRight: inputRight,
                outputLeft: UnsafeMutableBufferPointer(
                    start: inputRightPointer,
                    count: frameCount
                ),
                outputRight: outputRight,
                frameCount: frameCount
            ),
            .invalidBuffers
        )
        XCTAssertTrue(inputRight.allSatisfy { $0 == -0.5 })

        kernel.apply(snapshot)
        XCTAssertEqual(
            kernel.process(
                inputLeft: inputLeft,
                inputRight: inputRight,
                outputLeft: outputLeft,
                outputRight: outputLeft,
                frameCount: frameCount
            ),
            .invalidBuffers
        )
    }

    private func fixtureBands(gains: [Double] = [1.5, -1, 0.75]) -> [FixedEQBand] {
        [
            FixedEQBand(frequencyHz: 120, gainDB: gains[0], q: 0.7),
            FixedEQBand(frequencyHz: 1_000, gainDB: gains[1], q: 1),
            FixedEQBand(frequencyHz: 8_000, gainDB: gains[2], q: 1.4),
        ]
    }

    private func fixtureRecipe(
        inputHeadroomDB: Double = -3,
        gains: [Double] = [1.5, -1, 0.75],
        outputTrimDB: Double = -0.5
    ) -> FixedEQRecipe {
        recipe(
            inputHeadroomDB: inputHeadroomDB,
            bands: fixtureBands(gains: gains),
            outputTrimDB: outputTrimDB
        )
    }

    private func recipe(
        inputHeadroomDB: Double = -3,
        bands: [FixedEQBand],
        outputTrimDB: Double = 0
    ) -> FixedEQRecipe {
        FixedEQRecipe(
            id: "fixture",
            catalogVersion: 1,
            inputHeadroomDB: inputHeadroomDB,
            bands: bands,
            outputTrimDB: outputTrimDB
        )
    }

    private func replacingBand(
        _ bands: [FixedEQBand],
        at index: Int,
        frequencyHz: Double? = nil,
        gainDB: Double? = nil,
        q: Double? = nil
    ) -> [FixedEQBand] {
        var result = bands
        let current = result[index]
        result[index] = FixedEQBand(
            frequencyHz: frequencyHz ?? current.frequencyHz,
            gainDB: gainDB ?? current.gainDB,
            q: q ?? current.q
        )
        return result
    }

    private func renderMono(
        snapshot: FixedEQSnapshot,
        input: [Float],
        chunkSizes: [Int]
    ) -> (output: [Float], results: [FixedEQProcessResult]) {
        var kernel = FixedEQKernel(snapshot: snapshot)
        var output = [Float](repeating: 0, count: input.count)
        var results: [FixedEQProcessResult] = []

        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                var offset = 0
                var chunkIndex = 0
                while offset < input.count {
                    let requested = chunkSizes[chunkIndex % chunkSizes.count]
                    let frameCount = min(requested, input.count - offset)
                    let range = offset..<(offset + frameCount)
                    results.append(kernel.process(
                        inputLeft: UnsafeBufferPointer(rebasing: inputBuffer[range]),
                        inputRight: nil,
                        outputLeft: UnsafeMutableBufferPointer(rebasing: outputBuffer[range]),
                        outputRight: nil,
                        frameCount: frameCount
                    ))
                    offset += frameCount
                    chunkIndex += 1
                }
            }
        }
        return (output, results)
    }

    private func renderStereo(
        snapshot: FixedEQSnapshot,
        left: [Float],
        right: [Float],
        chunkSizes: [Int]
    ) -> (left: [Float], right: [Float], results: [FixedEQProcessResult]) {
        precondition(left.count == right.count)
        var kernel = FixedEQKernel(snapshot: snapshot)
        var outputLeft = [Float](repeating: 0, count: left.count)
        var outputRight = [Float](repeating: 0, count: right.count)
        var results: [FixedEQProcessResult] = []

        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                outputLeft.withUnsafeMutableBufferPointer { outputLeftBuffer in
                    outputRight.withUnsafeMutableBufferPointer { outputRightBuffer in
                        var offset = 0
                        var chunkIndex = 0
                        while offset < left.count {
                            let requested = chunkSizes[chunkIndex % chunkSizes.count]
                            let frameCount = min(requested, left.count - offset)
                            let range = offset..<(offset + frameCount)
                            results.append(kernel.process(
                                inputLeft: UnsafeBufferPointer(rebasing: leftBuffer[range]),
                                inputRight: UnsafeBufferPointer(rebasing: rightBuffer[range]),
                                outputLeft: UnsafeMutableBufferPointer(rebasing: outputLeftBuffer[range]),
                                outputRight: UnsafeMutableBufferPointer(rebasing: outputRightBuffer[range]),
                                frameCount: frameCount
                            ))
                            offset += frameCount
                            chunkIndex += 1
                        }
                    }
                }
            }
        }
        return (outputLeft, outputRight, results)
    }

    private func processMono(
        _ input: [Float],
        output: inout [Float],
        kernel: inout FixedEQKernel
    ) -> FixedEQProcessResult {
        precondition(input.count == output.count)
        var result: FixedEQProcessResult = .invalidBuffers
        input.withUnsafeBufferPointer { inputBuffer in
            output.withUnsafeMutableBufferPointer { outputBuffer in
                result = kernel.process(
                    inputLeft: inputBuffer,
                    inputRight: nil,
                    outputLeft: outputBuffer,
                    outputRight: nil,
                    frameCount: input.count
                )
            }
        }
        return result
    }

    private func rms<C: Collection>(_ values: C) -> Double where C.Element == Float {
        let sum = values.reduce(0.0) { partial, value in
            partial + Double(value) * Double(value)
        }
        return sqrt(sum / Double(values.count))
    }
}
