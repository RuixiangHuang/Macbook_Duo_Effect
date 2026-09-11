import Foundation

struct EffectGeometry: Equatable {
    let topHeight: Double
    let topWidth: Double
    let darkness: Double
    static let identity = EffectGeometry(topHeight: 1, topWidth: 1, darkness: 0)
}

enum EffectModel {
    /// Content beyond this stretch is a sliver at the bottom of the lid anyway;
    /// 1 / cos(x - y) is unbounded as the planes approach a right angle.
    private static let maximumStretch = 3.0

    /// The screen is treated as fixed at the reference angle x while the lid is
    /// really at y, and the viewer looks straight at that reference screen: the
    /// line of sight is perpendicular to plane x and does not move with the lid.
    /// The rays are parallel, so no point of the image moves sideways. Seen along
    /// that line the lid, tilted by x - y, is foreshortened to cos(x - y) of its
    /// height, so the content is stretched by 1 / cos(x - y) along the lid from
    /// the shared hinge and whatever lands past the lid's top edge is not shown:
    /// `topHeight` (> 1) is where the content's top would land, `topWidth` is 1.
    /// `strength` scales how much of that is applied: 0 leaves the image flat
    /// (only dimming and blur), 1 is the full geometry.
    static func geometry(angle: Double?, threshold: Double, strength: Double = 1) -> EffectGeometry {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, angle < threshold else { return .identity }
        let amount = min(1, max(0, 1 - angle / threshold))
        let darkness = 0.65 * amount * amount * (3 - 2 * amount)
        let k = strength.isFinite ? min(1, max(0, strength)) : 1
        let delta = (threshold - angle) * .pi / 180
        let stretch = delta < .pi / 2 ? min(maximumStretch, 1 / cos(delta)) : maximumStretch
        return EffectGeometry(topHeight: 1 + k * (stretch - 1), topWidth: 1, darkness: darkness)
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
