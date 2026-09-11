import Foundation

struct EffectGeometry: Equatable {
    let topHeight: Double
    let topWidth: Double
    let darkness: Double
    static let identity = EffectGeometry(topHeight: 1, topWidth: 1, darkness: 0)
}

enum EffectModel {
    /// The viewer looks straight at the lid: the line of sight is perpendicular to
    /// the lid and passes through its middle, and it turns with the lid as it
    /// closes. `eyeDistance` is how far the eye is from the lid along that line,
    /// in screen heights. Larger is closer to a parallel projection: the top edge
    /// at cos(x - y) with no narrowing at all.
    static let eyeDistance = 3.0
    private static let sightFraction = 0.5

    /// The screen is treated as fixed at the reference angle x while the lid is
    /// really at y. Each point of the content on plane x is projected along the
    /// eye's ray onto the lid, so the eye sees the content where it would be if
    /// the lid had not moved. The reference plane leans away from a viewer who
    /// faces the lid, so its content is foreshortened toward the shared hinge:
    /// `topHeight` (< 1) is where the content's top lands along the lid, leaving
    /// the strip above it empty, and `topWidth` is the width scale there.
    /// `strength` scales how much of that is applied: 0 leaves the image flat
    /// (only dimming and blur), 1 is the full geometry.
    static func geometry(angle: Double?, threshold: Double, strength: Double = 1) -> EffectGeometry {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, angle < threshold else { return .identity }
        let amount = min(1, max(0, 1 - angle / threshold))
        let darkness = 0.65 * amount * amount * (3 - 2 * amount)
        let k = strength.isFinite ? min(1, max(0, strength)) : 1
        // Only the angle between the two planes matters, because the eye moves
        // with the lid. Side view in the lid's own frame: u along the lid from
        // the hinge, n its normal toward the viewer.
        let delta = min(180, threshold - angle) * .pi / 180
        let eye = eyeDistance, foot = sightFraction
        // Content top on the reference plane: (cos delta along u, -sin delta along n).
        // Ray from the eye (foot, eye) meets the lid n = 0 at parameter t.
        let t = eye / (eye + sin(delta))
        let along = foot + t * (cos(delta) - foot)
        let height = max(0.05, min(1, along)), width = max(0.08, t)
        return EffectGeometry(topHeight: 1 + k * (height - 1), topWidth: 1 - k * (1 - width), darkness: darkness)
    }

    static func radius(angle: Double?, threshold: Double, maximum: Double, enabled: Bool) -> Double {
        guard enabled, let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, maximum.isFinite, maximum > 0,
              angle < threshold else { return 0 }
        let fraction = min(1, max(0, 1 - angle / threshold))
        return maximum * fraction * fraction * (3 - 2 * fraction)
    }
}

enum LidReport {
    static func angle(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 3, bytes[0] == 1 else { return nil }
        let degrees = Int(bytes[1]) + Int(bytes[2]) * 256
        return degrees <= 360 ? Double(degrees) : nil
    }
}

/// Time-based smoothing shared by blur, projection and dimming. Clearing is immediate.
struct EffectMotion {
    private(set) var radius = 0.0
    private(set) var geometry = EffectGeometry.identity

    mutating func advance(radius target: Double, geometry targetGeometry: EffectGeometry, deltaTime: Double) {
        guard target > 0 else { radius = 0; geometry = .identity; return }
        let blend = 1 - exp(-max(0, deltaTime) / 0.045)
        radius += (target - radius) * blend
        geometry = EffectGeometry(
            topHeight: geometry.topHeight + (targetGeometry.topHeight - geometry.topHeight) * blend,
            topWidth: geometry.topWidth + (targetGeometry.topWidth - geometry.topWidth) * blend,
            darkness: geometry.darkness + (targetGeometry.darkness - geometry.darkness) * blend)
    }
}
