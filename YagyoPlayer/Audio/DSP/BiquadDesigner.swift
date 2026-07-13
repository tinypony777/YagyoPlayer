import Foundation

/// Render側がそのまま読める、a0正規化済みのDF2T係数。
struct BiquadCoefficients: Equatable, Sendable {
    let b0: Float
    let b1: Float
    let b2: Float
    let a1: Float
    let a2: Float

    static let identity = BiquadCoefficients(
        b0: 1,
        b1: 0,
        b2: 0,
        a1: 0,
        a2: 0
    )

    var isFiniteAndStable: Bool {
        guard b0.isFinite, b1.isFinite, b2.isFinite, a1.isFinite, a2.isFinite else {
            return false
        }

        // Denominator is 1 + a1 z^-1 + a2 z^-2. These are the strict
        // second-order Jury stability conditions, checked again after Float conversion.
        let a1 = Double(a1)
        let a2 = Double(a2)
        return abs(a2) < 1
            && 1 + a1 + a2 > 0
            && 1 - a1 + a2 > 0
            && 1 - a2 > 0
    }
}

/// Coefficient design runs on the control side, never from the render callback.
enum BiquadDesigner {
    /// RBJ Audio EQ Cookbook peaking EQ. Returns nil instead of repairing invalid input.
    static func peaking(
        sampleRate: Double,
        frequencyHz: Double,
        gainDB: Double,
        q: Double
    ) -> BiquadCoefficients? {
        guard sampleRate.isFinite,
              sampleRate > 0,
              frequencyHz.isFinite,
              frequencyHz > 0,
              frequencyHz < sampleRate / 2,
              gainDB.isFinite,
              q.isFinite,
              q > 0 else {
            return nil
        }

        if gainDB == 0 {
            return .identity
        }

        let amplitude = pow(10, gainDB / 40)
        let omega = 2 * Double.pi * frequencyHz / sampleRate
        let sine = sin(omega)
        let cosine = cos(omega)
        let alpha = sine / (2 * q)
        let a0 = 1 + alpha / amplitude

        guard amplitude.isFinite,
              sine.isFinite,
              cosine.isFinite,
              alpha.isFinite,
              a0.isFinite,
              a0 != 0 else {
            return nil
        }

        let coefficients = BiquadCoefficients(
            b0: Float((1 + alpha * amplitude) / a0),
            b1: Float((-2 * cosine) / a0),
            b2: Float((1 - alpha * amplitude) / a0),
            a1: Float((-2 * cosine) / a0),
            a2: Float((1 - alpha / amplitude) / a0)
        )
        return coefficients.isFiniteAndStable ? coefficients : nil
    }
}
