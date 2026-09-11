import Foundation

struct EffectGeometry: Equatable {
    let topHeight: Double
    let topWidth: Double
    let darkness: Double
    static let identity = EffectGeometry(topHeight: 1, topWidth: 1, darkness: 0)
}

enum EffectModel {
    /// Where the virtual viewer sits, in screen heights, with the hinge at the
    /// origin: `eyeDistance` in front of it and `eyeHeight` above it. The lower the
    /// eye the less of the reference plane is lost beyond the lid's top edge; the
    /// farther the eye the less the top narrows. 2.5 forward and 0.5 up was the
    /// original tuning and cropped half the image at a 30° lid.
    static let eyeDistance = 4.0
    static let eyeHeight = 0.0
    /// Ceiling on the difference between the reference angle and the lid. Past it
    /// the projection freezes while blur and dimming keep deepening, because the
    /// exact projection runs away as the lid approaches the eye's line of sight.
    static let maximumDelta = 60.0
    /// A lid this close to the keyboard is closed for practical purposes and the
    /// projection is degenerate there (the eye lies in the lid plane).
    private static let minimumLid = 5.0

    /// The screen is treated as fixed at the reference angle x while the lid is
    /// really at y. Each point of the content on plane x is projected along the
    /// eye's ray onto the lid, so the eye sees the content where it would be if
    /// the lid had not moved. The hinge is shared by both planes, so the bottom
    /// edge stays put and only the top edge moves: `topHeight` is where the
    /// content's top lands along the lid (>1 is past its edge and cropped) and
    /// `topWidth` is the width scale there.
    static func geometry(angle: Double?, threshold: Double) -> EffectGeometry {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, angle < threshold else { return .identity }
        let amount = min(1, max(0, 1 - angle / threshold))
        let darkness = 0.65 * amount * amount * (3 - 2 * amount)
        let x = threshold * .pi / 180
        let y = max(angle, threshold - maximumDelta, minimumLid) * .pi / 180
        // Side view: z toward the eye, y up. The content's top edge on plane x, the
        // eye, and the lid plane's normal.
        let (pz, py) = (cos(x), sin(x))
        let (ez, ey) = (eyeDistance, eyeHeight)
        let (nz, ny) = (-sin(y), cos(y))
        // Ray E + t(P - E) meets the lid plane n·Q = 0 at t = -(n·E) / (n·(P-E)).
        let b = nz * (pz - ez) + ny * (py - ey)
        guard b != 0 else { return .identity }
        let t = -(nz * ez + ny * ey) / b
        guard t > 0, t <= 1 else { return .identity }
        let (qz, qy) = (ez + t * (pz - ez), ey + t * (py - ey))
        let along = qz * cos(y) + qy * sin(y)
        // t is also the lateral scale: the top edge projects toward the eye's centre line.
        return EffectGeometry(topHeight: min(3, along), topWidth: max(0.08, t), darkness: darkness)
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
