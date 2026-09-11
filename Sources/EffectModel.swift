import Foundation

struct EffectGeometry: Equatable {
    let topHeight: Double
    let topWidth: Double
    let darkness: Double
    static let identity = EffectGeometry(topHeight: 1, topWidth: 1, darkness: 0)
}

enum EffectModel {
    /// How far in front of the reference plane the virtual viewer sits, in screen
    /// heights. A nearer viewpoint distorts harder: at 2.5 the image collapsed to a
    /// sliver well before the lid was closed.
    static let viewerDistance = 4.0
    /// Ceiling on the projected difference angle. Beyond this the projection runs
    /// away faster than it reads as perspective.
    static let maximumDelta = 60.0

    /// Projection of a virtual plane fixed at x onto the moving lid. The bottom edge
    /// is the hinge.
    static func geometry(angle: Double?, threshold: Double) -> EffectGeometry {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, angle < threshold else { return .identity }
        let delta = min(maximumDelta, threshold - angle) * .pi / 180
        let height = 1 / (cos(delta) + 0.2 * sin(delta))
        let width = max(0.08, 1 - height * sin(delta) / viewerDistance)
        let amount = min(1, max(0, 1 - angle / threshold))
        return EffectGeometry(topHeight: height, topWidth: width,
                              darkness: 0.65 * amount * amount * (3 - 2 * amount))
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
