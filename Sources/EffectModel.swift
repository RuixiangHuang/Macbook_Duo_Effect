import Foundation
import QuartzCore
import Darwin

struct EffectGeometry: Equatable {
    /// Top edge corners of the collapsing window in normalized panel
    /// coordinates: x across the width, y above the bottom hinge. The sides
    /// converge toward the eye's vanishing point; a lateral eye offset skews
    /// the opening toward the viewer.
    var topLeftX = 0.0
    var topRightX = 1.0
    var topY = 1.0
    /// Bottom edge of the projected image. With the display offset from the
    /// hinge axis these move a little instead of being pinned to the bottom.
    var bottomLeftX = 0.0
    var bottomRightX = 1.0
    var bottomY = 0.0
    /// Brightness multiplier's complement after the progress fade is applied;
    /// kept separate so the renderer can shape it.
    var darkness = 0.0
    /// Crease shadow strength at the hinge (sin of the fold rotation): a dark
    /// seam hugging the bottom edge, as on a folding panel.
    var crease = 0.0
    static let identity = EffectGeometry()
}

/// Viewer eye position in screen-height units: x to the viewer's right of the
/// screen center, y above the bottom hinge, z in front of the panel. The
/// nominal pose is a centered viewer about 50 cm out; a camera calibration
/// replaces it with the measured one.
struct EyePose: Equatable {
    var x = 0.0
    var y = 0.0
    var z = 1.6
    /// A centred seated viewer: level with the panel, about 1.3 screen-heights
    /// above the hinge (the eye sits above the screen's top edge on a laptop).
    static let nominal = EyePose(x: 0, y: 1.3, z: 1.6)
}

/// Where the display sits relative to the lid's hinge axis, in screen-height
/// units. The hinge is not the bottom pixel row: the active area starts behind
/// a small bottom bezel, and the display surface is offset from the axis by
/// roughly half the lid thickness. Recent Apple laptops carry the camera in a
/// notch cut into the active area above the menu bar, so the camera sits just
/// below the top active row and slightly recessed behind the display surface.
///
/// Derived from Apple's tech specs (apple.com/macbook-pro/specs): the 16-inch
/// active area is 3456×2234 at 254 ppi (223.4 mm tall) and the closed body is
/// 16.8 mm, the 14-inch is 3024×1964 (196.4 mm) and 15.5 mm. Splitting that
/// thickness and the bezel gives roughly a 6.5 mm bottom bezel plus hinge
/// offset, a 4 mm lid standoff, a 3 mm notch inset (the menu bar and notch are
/// about 6 mm tall) and a 1.5 mm camera recess. Units below are for the
/// 16-inch panel; the 14-inch differs by about 13%, well inside the bezel
/// estimate.
enum LidGeometry {
    /// Hinge axis to the bottom active row, measured along the lid.
    static let hingeDropMillimetres = 6.5
    /// Hinge axis to the display surface, measured out of the lid.
    static let standoffMillimetres = 4.0
    /// Top active row down to the camera in the notch.
    static let cameraInsetMillimetres = 3.0
    /// Camera depth behind the display surface.
    static let cameraRecessMillimetres = 1.5
}

/// The lid offsets in screen-height units, converted from millimetres with the
/// panel's measured active height. Presets come from `LidGeometry`; the
/// settings can override each value with a locally measured one.
struct LidMetrics: Equatable {
    var hingeDrop: Double
    var standoff: Double
    var cameraInset: Double
    var cameraRecess: Double

    init(hingeDropMM: Double, standoffMM: Double, cameraInsetMM: Double, cameraRecessMM: Double,
         screenHeightMillimetres: Double) {
        let height = screenHeightMillimetres.isFinite && screenHeightMillimetres > 50 ? screenHeightMillimetres : 223.4
        hingeDrop = hingeDropMM / height
        standoff = standoffMM / height
        cameraInset = cameraInsetMM / height
        cameraRecess = cameraRecessMM / height
    }

    static let standard = LidMetrics(
        hingeDropMM: LidGeometry.hingeDropMillimetres,
        standoffMM: LidGeometry.standoffMillimetres,
        cameraInsetMM: LidGeometry.cameraInsetMillimetres,
        cameraRecessMM: LidGeometry.cameraRecessMillimetres,
        screenHeightMillimetres: 223.4)
}

/// The machine's own model identifier, shown in settings next to the preset
/// it drives. Unknown identifiers fall back to the preset values, which cover
/// Apple's current lid design.
enum MachineModel {
    static var identifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "Mac" }
        return String(cString: buffer)
    }

    /// Friendly names for identifiers whose lid geometry is confirmed.
    static func name(for identifier: String) -> String {
        switch identifier {
        case "MacBookPro18,1", "MacBookPro18,2": return "MacBook Pro 16-inch, 2021"
        case "MacBookPro18,3", "MacBookPro18,4": return "MacBook Pro 14-inch, 2021"
        case "Mac14,5", "Mac14,9": return "MacBook Pro 14-inch, 2023"
        case "Mac14,6", "Mac14,10": return "MacBook Pro 16-inch, 2023"
        case "Mac15,3", "Mac15,6", "Mac15,8", "Mac15,10", "Mac15,11": return "MacBook Pro 14-inch, 2023-24"
        case "Mac15,7", "Mac15,9": return "MacBook Pro 16-inch, 2023-24"
        case "Mac16,1", "Mac16,6", "Mac16,8": return "MacBook Pro 14-inch, 2024"
        case "Mac16,5", "Mac16,7": return "MacBook Pro 16-inch, 2024"
        default: return identifier
        }
    }
}

/// Pure camera math for head tracking: turns a detected face box into a
/// camera-frame eye position, then rotates it into the world frame the fold
/// projection uses. Kept free of AVFoundation so it is unit-testable.
enum FaceGeometry {
    /// Average adult face width, meters.
    static let faceWidth = 0.14

    /// Camera-frame eye position: x right, y above the camera axis, z out of
    /// the screen toward the viewer. Vision's origin is bottom-left. Pass the
    /// midpoint between the detected eyes as `eyeCenter` when landmarks are
    /// available: the face-box centre sits at nose level and biases the
    /// measured height low.
    static func estimate(faceBox: CGRect, eyeCenter: CGPoint? = nil,
                         frameWidth: Double, frameHeight: Double,
                         horizontalFOVDegrees: Double, screenHeightMeters: Double) -> EyePose? {
        let centerX = eyeCenter?.x ?? faceBox.midX
        let centerY = eyeCenter?.y ?? faceBox.midY
        guard frameWidth > 0, frameHeight > 0,
              horizontalFOVDegrees.isFinite, horizontalFOVDegrees > 1, horizontalFOVDegrees < 179,
              screenHeightMeters.isFinite, screenHeightMeters > 0.05, screenHeightMeters < 1,
              faceBox.width > 0.02, faceBox.width < 0.9,
              centerX > 0, centerX < 1, centerY > 0, centerY < 1 else { return nil }
        let fov = horizontalFOVDegrees * .pi / 180
        let angularWidth = faceBox.width * fov
        let distance = faceWidth / (2 * tan(angularWidth / 2))
        guard distance.isFinite, distance > 0.2, distance < 2 else { return nil }
        let z = distance / screenHeightMeters
        // The front camera mirrors the viewer: a face left of the image center
        // means the viewer sits to their right.
        let x = z * tan((0.5 - centerX) * fov)
        let verticalFOV = 2 * atan(tan(fov / 2) * frameHeight / frameWidth)
        let y = z * tan((centerY - 0.5) * verticalFOV)
        guard x.isFinite, y.isFinite, z > 0.5, z < 6, abs(x) < 4, abs(y) < 4 else { return nil }
        return EyePose(x: x, y: y, z: z)
    }

    /// Rotates a camera-frame pose into the world frame used by the fold
    /// projection: x right, y above the hinge axis, z out of the display. The
    /// camera rides in the lid's notch, so lid-local coordinates include the
    /// hinge drop, the display standoff, the notch inset below the top row and
    /// the recess behind the glass; tau is the lid's rotation from vertical
    /// (90° open is vertical; closing swings the top toward the viewer).
    static func worldEye(camera: EyePose, lidAngleDegrees: Double,
                         metrics: LidMetrics = .standard) -> EyePose {
        let tau = (90 - lidAngleDegrees) * .pi / 180
        guard tau.isFinite else { return .nominal }
        let c = cos(tau)
        let s = sin(tau)
        let lidY = metrics.hingeDrop + 1 - metrics.cameraInset + camera.y
        let lidZ = metrics.standoff - metrics.cameraRecess + camera.z
        return EyePose(
            x: camera.x,
            y: lidY * c - lidZ * s,
            z: lidY * s + lidZ * c)
    }
}

enum EffectModel {
    /// Angular band over which the fold's rotation eases in below the clear
    /// threshold. Two degrees covers the sensor's one-degree quantization and
    /// a typical hand's slow close, without softening the fold itself.
    static let easeBandDegrees = 2.0
    /// The image is fixed in space behind the panel; the panel is the
    /// viewport you look through. This returns where the image's four corners
    /// land on the panel, seen from the eye — the destination quad that
    /// `CIPerspectiveTransform` maps the image onto. The eye is a pinhole, so
    /// an image corner projects where the eye→corner ray crosses the panel
    /// plane. The hinge axis is offset from the display (see `LidGeometry`),
    /// so the panel plane is `z·cos δ − y·sin δ = standoff` and the panel's
    /// normalized height is measured from the bottom active row, not from the
    /// axis. With the eye above the screen's top edge the top row projects
    /// above the panel from the first degree of the fold and is clipped away,
    /// while the bottom edge moves a little; black appears only where the
    /// panel looks past the image. As the fold deepens the projected corners
    /// pull inward.
    static func geometry(angle: Double?, threshold: Double, strength: Double = 1,
                         eye: EyePose = .nominal, aspect: Double = 1.55,
                         metrics: LidMetrics = .standard) -> EffectGeometry {
        guard let angle, angle.isFinite, (0...360).contains(angle),
              threshold.isFinite, threshold > 0, angle < threshold,
              eye.x.isFinite, eye.y.isFinite, eye.z.isFinite, eye.z > 0.1,
              aspect.isFinite, aspect > 0.5, aspect < 4 else { return .identity }
        let deltaDegrees = min(75, threshold - angle)
        // Ease the rotation itself, not the geometry: every rendered frame
        // stays an exact projection of a real lid angle, and the visual
        // response starts from rest at the threshold. The band is measured in
        // degrees (the sensor reports whole degrees), so it never eats into
        // the fold the way a fraction-of-closing ramp did.
        let ease = min(1, deltaDegrees / Self.easeBandDegrees)
        let easedDelta = deltaDegrees * (ease * ease * (3 - 2 * ease)) * .pi / 180
        let c = cos(easedDelta)
        let s = sin(easedDelta)
        // The eye pose is stored in the world frame (y vertical), but the
        // frozen image lies on the display's plane at the clear threshold, so
        // rotate the eye into that image frame first.
        let lean = (threshold - 90) * .pi / 180
        let leanC = cos(lean)
        let leanS = sin(lean)
        let eyeY = eye.y * leanC - eye.z * leanS
        let eyeZ = eye.y * leanS + eye.z * leanC
        // Where an image corner lands on the tilted panel. The panel plane is
        // z·cos δ − y·sin δ = standoff; t is the ray parameter at that plane,
        // which is 1 at the image and slightly less once the lid has swung
        // toward the viewer. The result is in the panel's normalized
        // coordinates: x across, y above the bottom active row.
        func panelPoint(imageX: Double, imageY: Double) -> (x: Double, y: Double) {
            let dy = imageY - eyeY
            let dz = metrics.standoff - eyeZ
            let denominator = c * dz - s * dy
            guard abs(denominator) > 1e-9 else { return (0.5, 4) }
            let t = max(0, min(8, (metrics.standoff - c * eyeZ + s * eyeY) / denominator))
            let yAtPanel = eyeY + t * dy
            let xAtPanel = eye.x + t * (imageX - eye.x)
            let height = (yAtPanel + metrics.standoff * s) / c - metrics.hingeDrop
            return (xAtPanel / aspect + 0.5, min(4, max(0, height)))
        }
        let halfWidth = aspect / 2
        let topLeft = panelPoint(imageX: -halfWidth, imageY: metrics.hingeDrop + 1)
        let topRight = panelPoint(imageX: halfWidth, imageY: metrics.hingeDrop + 1)
        let bottomLeft = panelPoint(imageX: -halfWidth, imageY: metrics.hingeDrop)
        let bottomRight = panelPoint(imageX: halfWidth, imageY: metrics.hingeDrop)
        let k = strength.isFinite ? min(1, max(0, strength)) : 1
        let progress = min(1, max(0, 1 - angle / threshold))
        let fade = progress * progress * (3 - 2 * progress)
        // Lambertian shading of the turning panel (B(θ) = cosθ^γ with γ = 1),
        // layered on the progress fade so a fully closed lid still reaches
        // black. At a low threshold the fold is shallow, so shading is gentle.
        let brightness = (1 - fade) * max(0, c)
        // Geometry is applied at full strength: the rotation above already
        // carries the ease, so no second ramp distorts the projection.
        return EffectGeometry(
            topLeftX: topLeft.x * k,
            topRightX: 1 + (topRight.x - 1) * k,
            topY: 1 + (topLeft.y - 1) * k,
            bottomLeftX: bottomLeft.x * k,
            bottomRightX: 1 + (bottomRight.x - 1) * k,
            bottomY: bottomLeft.y * k,
            darkness: 1 - brightness,
            crease: s)
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

/// Anti-aliases the raw lid report before it reaches the effect model. The
/// sensor quantizes to whole degrees, so unfiltered angles reach the renderer
/// as 1° steps; this turns them into a continuous signal with rate-independent
/// exponential smoothing. Large jumps (fast lid motion, sensor reconnects)
/// snap instead of lagging behind the hand.
struct AngleFilter {
    private var value: Double?
    private var lastRaw: Double?
    private var rate = 0.0
    private var lastTime = 0.0
    private let timeConstant: Double
    private let lookAhead: Double

    init(timeConstant: Double = 0.12, lookAhead: Double = 0.06) {
        self.timeConstant = timeConstant
        self.lookAhead = lookAhead
    }

    mutating func update(_ raw: Double?, at time: Double = CACurrentMediaTime()) -> Double? {
        guard let raw, raw.isFinite else { value = nil; lastRaw = nil; rate = 0; return nil }
        guard let current = value else {
            value = raw; lastRaw = raw; lastTime = time; rate = 0; return raw
        }
        let deltaTime = max(0, time - lastTime)
        let rawDelta = lastRaw.map { raw - $0 } ?? 0
        lastTime = time
        lastRaw = raw
        guard deltaTime > 0, abs(raw - current) < 45 else { value = raw; rate = 0; return raw }
        let blend = 1 - exp(-deltaTime / timeConstant)
        // The hand's own angular rate, smoothed with the same time constant
        // and only used to lead the filter: predictive lead (τω in the folding
        // model) hides the smoothing lag without adding jitter at rest.
        if abs(rawDelta) < 45 {
            rate += (rawDelta / deltaTime - rate) * blend
        } else {
            rate = 0
        }
        let next = current + (raw - current) * blend
        value = next
        // Never lead past the newest reading, so quantization steps cannot
        // ring or overshoot.
        let gap = raw - next
        let lead = min(abs(rate * lookAhead), abs(gap))
        return next + (gap >= 0 ? lead : -lead)
    }
}

/// Time-based smoothing shared by blur, projection and dimming. Clearing is immediate.
struct EffectMotion {
    private(set) var radius = 0.0
    private(set) var geometry = EffectGeometry.identity

    mutating func advance(radius target: Double, geometry targetGeometry: EffectGeometry, deltaTime: Double) {
        guard target > 0 else { radius = 0; geometry = .identity; return }
        // 30 ms: enough to keep sensor ticks from stepping the picture while
        // staying well below the 120 ms angle filter, so the renderer adds
        // little lag of its own on a 120 Hz panel.
        let blend = 1 - exp(-max(0, deltaTime) / 0.03)
        radius += (target - radius) * blend
        geometry = EffectGeometry(
            topLeftX: geometry.topLeftX + (targetGeometry.topLeftX - geometry.topLeftX) * blend,
            topRightX: geometry.topRightX + (targetGeometry.topRightX - geometry.topRightX) * blend,
            topY: geometry.topY + (targetGeometry.topY - geometry.topY) * blend,
            bottomLeftX: geometry.bottomLeftX + (targetGeometry.bottomLeftX - geometry.bottomLeftX) * blend,
            bottomRightX: geometry.bottomRightX + (targetGeometry.bottomRightX - geometry.bottomRightX) * blend,
            bottomY: geometry.bottomY + (targetGeometry.bottomY - geometry.bottomY) * blend,
            darkness: geometry.darkness + (targetGeometry.darkness - geometry.darkness) * blend,
            crease: geometry.crease + (targetGeometry.crease - geometry.crease) * blend)
    }
}
