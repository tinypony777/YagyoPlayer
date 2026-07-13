import Foundation

struct FixedEQBand: Equatable, Sendable {
    var frequencyHz: Double
    var gainDB: Double
    var q: Double
}

/// A catalog-owned recipe. AI may select `id`, but it never authors these values.
struct FixedEQRecipe: Equatable, Sendable {
    var id: String
    var catalogVersion: Int
    var inputHeadroomDB: Double
    var bands: [FixedEQBand]
    var outputTrimDB: Double
}

enum FixedEQMode: Equatable, Sendable {
    case original
    case processed
}

/// Five fixed slots avoid collection access and allocation on the render side.
struct FixedEQCoefficientSet: Equatable, Sendable {
    let first: BiquadCoefficients
    let second: BiquadCoefficients
    let third: BiquadCoefficients
    let fourth: BiquadCoefficients
    let fifth: BiquadCoefficients

    static let identity = FixedEQCoefficientSet(
        first: .identity,
        second: .identity,
        third: .identity,
        fourth: .identity,
        fifth: .identity
    )

    init?(_ coefficients: [BiquadCoefficients]) {
        guard coefficients.count <= FixedEQRecipeContract.maximumBandCount else {
            return nil
        }
        first = coefficients.indices.contains(0) ? coefficients[0] : .identity
        second = coefficients.indices.contains(1) ? coefficients[1] : .identity
        third = coefficients.indices.contains(2) ? coefficients[2] : .identity
        fourth = coefficients.indices.contains(3) ? coefficients[3] : .identity
        fifth = coefficients.indices.contains(4) ? coefficients[4] : .identity
    }

    private init(
        first: BiquadCoefficients,
        second: BiquadCoefficients,
        third: BiquadCoefficients,
        fourth: BiquadCoefficients,
        fifth: BiquadCoefficients
    ) {
        self.first = first
        self.second = second
        self.third = third
        self.fourth = fourth
        self.fifth = fifth
    }

    var allFiniteAndStable: Bool {
        first.isFiniteAndStable
            && second.isFiniteAndStable
            && third.isFiniteAndStable
            && fourth.isFiniteAndStable
            && fifth.isFiniteAndStable
    }
}

/// Immutable value passed to the render boundary. All expensive design is already complete.
struct FixedEQSnapshot: Equatable, Sendable {
    let generation: UInt64
    let mode: FixedEQMode
    let bandCount: Int
    let coefficients: FixedEQCoefficientSet
    let inputHeadroomLinear: Float
    let outputTrimLinear: Float

    static func original(generation: UInt64) -> FixedEQSnapshot {
        FixedEQSnapshot(
            generation: generation,
            mode: .original,
            bandCount: 0,
            coefficients: .identity,
            inputHeadroomLinear: 1,
            outputTrimLinear: 1
        )
    }
}

enum FixedEQRecipeContract {
    static let minimumBandCount = 3
    static let maximumBandCount = 5
    static let maximumAbsoluteGainDB = 3.0
    static let minimumFrequencyHz = 20.0
    static let maximumFrequencyHz = 20_000.0
    static let maximumNyquistFraction = 0.95

    // Phase 1's deliberately moderate fixture range. Catalog evidence must be updated
    // before widening it; values outside the range fail closed to Original.
    static let minimumQ = 0.5
    static let maximumQ = 2.0
}

/// The only recipe -> render-snapshot boundary. Invalid data never produces a partial chain.
enum FixedEQSnapshotFactory {
    static func make(
        recipe: FixedEQRecipe,
        sampleRate: Double,
        generation: UInt64
    ) -> FixedEQSnapshot {
        guard !recipe.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              recipe.catalogVersion > 0,
              sampleRate.isFinite,
              sampleRate > 0,
              (FixedEQRecipeContract.minimumBandCount...FixedEQRecipeContract.maximumBandCount)
                  .contains(recipe.bands.count),
              let inputHeadroomLinear = attenuationLinear(recipe.inputHeadroomDB),
              let outputTrimLinear = attenuationLinear(recipe.outputTrimDB) else {
            return .original(generation: generation)
        }

        var designed: [BiquadCoefficients] = []
        designed.reserveCapacity(FixedEQRecipeContract.maximumBandCount)
        var summedPositiveGainDB = 0.0
        let maximumFrequencyHz = min(
            FixedEQRecipeContract.maximumFrequencyHz,
            sampleRate * 0.5 * FixedEQRecipeContract.maximumNyquistFraction
        )
        for band in recipe.bands {
            guard band.frequencyHz.isFinite,
                  band.frequencyHz >= FixedEQRecipeContract.minimumFrequencyHz,
                  band.frequencyHz <= maximumFrequencyHz,
                  band.gainDB.isFinite,
                  abs(band.gainDB) <= FixedEQRecipeContract.maximumAbsoluteGainDB,
                  band.q.isFinite,
                  (FixedEQRecipeContract.minimumQ...FixedEQRecipeContract.maximumQ).contains(band.q),
                  let coefficients = BiquadDesigner.peaking(
                      sampleRate: sampleRate,
                      frequencyHz: band.frequencyHz,
                      gainDB: band.gainDB,
                      q: band.q
                  ) else {
                return .original(generation: generation)
            }
            summedPositiveGainDB += max(band.gainDB, 0)
            designed.append(coefficients)
        }

        // Output trim occurs after the cascade and cannot protect its internal state.
        // Reserve at least the sum of every possible positive band contribution.
        guard recipe.inputHeadroomDB <= -summedPositiveGainDB else {
            return .original(generation: generation)
        }

        guard let coefficientSet = FixedEQCoefficientSet(designed),
              coefficientSet.allFiniteAndStable else {
            return .original(generation: generation)
        }

        return FixedEQSnapshot(
            generation: generation,
            mode: .processed,
            bandCount: recipe.bands.count,
            coefficients: coefficientSet,
            inputHeadroomLinear: inputHeadroomLinear,
            outputTrimLinear: outputTrimLinear
        )
    }

    private static func attenuationLinear(_ decibels: Double) -> Float? {
        guard decibels.isFinite, decibels <= 0 else { return nil }
        let doubleValue = pow(10, decibels / 20)
        let value = Float(doubleValue)
        guard doubleValue.isFinite,
              doubleValue > 0,
              doubleValue <= 1,
              value.isFinite,
              value > 0,
              value <= 1 else {
            return nil
        }
        return value
    }
}
