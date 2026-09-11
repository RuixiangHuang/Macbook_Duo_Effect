import Foundation

struct EffectGeometry: Equatable {
    let topHeight: Double
    let topWidth: Double
    let darkness: Double
    static let identity = EffectGeometry(topHeight: 1, topWidth: 1, darkness: 0)
}

enum EffectModel {
    /// The viewer's eye sits on the reference plane's normal through its middle,
    /// this many screen heights away. Nearer means the lid's top, which leans
    /// toward the eye, looms larger and the content must narrow more to match
    /// the reference screen; 2.5 was the original tuning. Very far approaches a
    /// parallel projection with no narrowing at all.
    static let eyeDistance = 5.0
    /// Content stretched past this is a sliver at the bottom of the lid anyway.
    private static let maximumStretch = 3.0

    /// The screen is treated as fixed at the reference angle x while the lid is
    /// really at y, and the viewer faces that reference screen. Each point of the
    /// content on plane x is projected along the eye's ray onto the lid, so the
    /// eye sees it where it would be if the lid had not moved. The lid leans
    /// toward the eye by x - y, so along the lid the content stretches from the
    /// shared hinge (`topHeight` > 1, the part past the lid's top edge is not
    /// shown) and its top edge, which the eye sees closer and larger than the
    /// reference, is drawn narrower (`topWidth` < 1). `strength` scales how
    /// much of that is applied: 0 leaves the image flat, 1 is the full geometry.
    static func geometry(angle: Double?, threshold: Double, strength: Double = 1) -> EffectGeometry {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, angle < threshold else { return .identity }
        let amount = min(1, max(0, 1 - angle / threshold))
        let darkness = 0.65 * amount * amount * (3 - 2 * amount)
        let k = strength.isFinite ? min(1, max(0, strength)) : 1
        // In the reference plane's frame: u along it from the hinge, n its normal
        // toward the eye at (0.5, L). The content's top is (1, 0); the lid is the
        // line through the origin at x - y toward the eye. The ray from the eye
        // through the top meets that line at parameter t, which is also the
        // lateral scale, and lands at 0.5(1 + t) / cos(x - y) along the lid.
        let delta = min(89.0, threshold - angle) * .pi / 180
        let half = 0.5 * tan(delta)
        let t = (eyeDistance - half) / (eyeDistance + half)
        let stretch = t > 0 ? 0.5 * (1 + t) / cos(delta) : maximumStretch
        // Clamp after blending so the bounds hold exactly at every strength.
        return EffectGeometry(topHeight: min(maximumStretch, 1 + k * (stretch - 1)),
                              topWidth: max(0.08, 1 - k * (1 - t)), darkness: darkness)
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
