import Foundation

struct EffectGeometry: Equatable {
    let topHeight: Double
    let topWidth: Double
    let darkness: Double
    static let identity = EffectGeometry(topHeight: 1, topWidth: 1, darkness: 0)
}

enum EffectModel {
    /// The viewer's eye is level with the top edge of the reference screen and
    /// this many screen heights in front of it, looking straight at it. Nearer
    /// means the lid's top, which leans toward the eye, looms larger and the
    /// content's top must be drawn narrower to match. Very far means no taper.
    static let eyeDistance = 5.0
    /// How much of the foreshortening is applied vertically: a plane tilted away
    /// by x - y appears cos(x - y) as tall, and at 1 the content's top lands
    /// exactly there, leaving the strip above it empty. 0 keeps the full height.
    static let verticalShrink = 0.3

    /// The screen is treated as fixed at the reference angle x while the lid is
    /// really at y, so relative to the lid the content tilts away by x - y. Its
    /// top edge is drawn narrower by tan(x - y) / eyeDistance (`topWidth`), and
    /// lower by the foreshortening cos(x - y) scaled by `verticalShrink`
    /// (`topHeight` <= 1). Both keep the image on the screen: the projection's
    /// own stretch past the lid's top edge is deliberately not applied.
    /// `strength` scales how much of the geometry is applied: 0 leaves the
    /// image flat, 1 is the full taper and shrink.
    static func geometry(angle: Double?, threshold: Double, strength: Double = 1) -> EffectGeometry {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, angle < threshold else { return .identity }
        let amount = min(1, max(0, 1 - angle / threshold))
        let darkness = 0.65 * amount * amount * (3 - 2 * amount)
        let k = strength.isFinite ? min(1, max(0, strength)) : 1
        let delta = min(89.0, threshold - angle) * .pi / 180
        let taper = 1 - tan(delta) / eyeDistance
        let shrink = 1 - verticalShrink * (1 - cos(delta))
        // Clamp after blending so the bounds hold exactly at every strength.
        return EffectGeometry(topHeight: max(0.05, 1 - k * (1 - shrink)),
                              topWidth: max(0.08, 1 - k * (1 - taper)), darkness: darkness)
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
