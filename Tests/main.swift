import Foundation
var failures = 0
func check(_ condition: Bool, _ name: String) {
    if !condition { print("FAIL: \(name)"); failures += 1 }
}
func widthAtGeom(_ g: EffectGeometry) -> Double { g.topRightX - g.topLeftX }
check(EffectModel.radius(angle: 90, threshold: 90, maximum: 30, enabled: true) == 0, "exact threshold clears")
check(EffectModel.radius(angle: 120, threshold: 90, maximum: 30, enabled: true) == 0, "above threshold clears")
check(EffectModel.radius(angle: 0, threshold: 90, maximum: 30, enabled: true) == 30, "closed is maximum")
check(EffectModel.radius(angle: 45, threshold: 90, maximum: 30, enabled: false) == 0, "pause clears")
for bad: Double in [.nan, .infinity, -1, 361] {
    check(EffectModel.radius(angle: bad, threshold: 90, maximum: 30, enabled: true) == 0, "bad angle clears")
}
check(EffectModel.radius(angle: nil, threshold: 90, maximum: 30, enabled: true) == 0, "missing sensor clears")
check(EffectModel.radius(angle: 45, threshold: 0, maximum: 30, enabled: true) == 0, "invalid threshold clears")
var last = 31.0
for angle in 0...90 {
    let value = EffectModel.radius(angle: Double(angle), threshold: 90, maximum: 30, enabled: true)
    check(value <= last && value >= 0, "opening monotonically clears at \(angle)")
    last = value
}
check(LidReport.angle([1, 90, 0]) == 90, "90 degree report")
check(LidReport.angle([1, 14, 1]) == 270, "little endian report")
check(LidReport.angle([1, 255, 255]) == nil, "invalid angle rejected")
check(LidReport.angle([1]) == nil, "truncated report rejected")
check(LidReport.angle([2, 90, 0]) == nil, "wrong report ID rejected")
check(EffectModel.geometry(angle: 90, threshold: 90) == .identity, "threshold restores clear screen")
check(EffectModel.geometry(angle: nil, threshold: 90) == .identity, "missing sensor clears")
for threshold in [10.0, 90, 114, 140] {
    // Below ~50° the screen faces away from a seated viewer; the projection
    // is only meaningful while the eye is in front of the frozen plane.
    let facing = lidEye(threshold).z > 0.5
    for strength in [0.0, 0.5, 1] {
        var previousWidth = 1.0, previousDarkness = 0.0
        for angle in stride(from: threshold, through: 0, by: -0.5) {
            let state = EffectModel.geometry(angle: angle, threshold: threshold, strength: strength)
            check(state.topY >= 0 && state.topY <= 4, "the top edge stays within the projected envelope")
            check(state.bottomY >= 0 && state.bottomY <= 4, "the bottom edge stays within the projected envelope")
            if facing {
                check(widthAtGeom(state) <= previousWidth + 1e-12, "the projected top edge narrows as the fold deepens")
            }
            check(state.topLeftX <= state.topRightX && state.bottomLeftX <= state.bottomRightX, "left stays left of right")
            check(state.darkness >= previousDarkness && state.darkness <= 1, "closing fades monotonically")
            previousWidth = widthAtGeom(state); previousDarkness = state.darkness
        }
    }
}
let fold45 = EffectModel.geometry(angle: 45, threshold: 90)
check(fold45.topY > 1.7 && widthAtGeom(fold45) < 0.3, "well into the fold the top corners leave the panel")
check(abs(fold45.darkness - (1 - 0.5 * cos(45.0 * .pi / 180))) < 1e-12, "the turning panel darkens with cos of the fold")
check(abs(fold45.crease - sin(45.0 * .pi / 180)) < 1e-12, "the crease shadow scales with the fold rotation")
let deep = EffectModel.geometry(angle: 0, threshold: 90)
check(deep.topY >= 3.5 && widthAtGeom(deep) == 0, "the deep tail projects the whole picture off the panel")
check(deep.darkness == 1, "a fully closed lid is fully faded")
let taperDev = { (angle: Double) in abs((EffectModel.geometry(angle: angle, threshold: 90).topRightX - EffectModel.geometry(angle: angle, threshold: 90).topLeftX) - 1) }
check(taperDev(89) < 0.25 * taperDev(85), "fold eases in from rest at the threshold")
// The whole model in one place: where an image corner lands on the tilted
// panel. The eye is stored against the vertical (90°) plane and rotated into
// the image frame at the threshold; the panel plane is
// z·cos δ − y·sin δ = standoff, and heights are measured from the bottom
// active row rather than from the hinge axis.
func lidPanelPoint(imageX: Double, imageY: Double, deltaDegrees: Double,
                   threshold: Double = 90, eye: EyePose = .nominal,
                   aspect: Double = 1.55) -> (x: Double, y: Double) {
    let d = deltaDegrees * .pi / 180
    let c = cos(d), s = sin(d)
    let lean = (threshold - 90) * .pi / 180
    let eyeY = eye.y * cos(lean) - eye.z * sin(lean)
    let eyeZ = eye.y * sin(lean) + eye.z * cos(lean)
    let metrics = LidMetrics.standard
    let dy = imageY - eyeY
    let dz = metrics.standoff - eyeZ
    let t = max(0, min(8, (metrics.standoff - c * eyeZ + s * eyeY) / (c * dz - s * dy)))
    let yAtPanel = eyeY + t * dy
    let xAtPanel = eye.x + t * (imageX - eye.x)
    let height = (yAtPanel + metrics.standoff * s) / c - metrics.hingeDrop
    return (xAtPanel / aspect + 0.5, min(4, max(0, height)))
}
func lidEye(_ threshold: Double, eye: EyePose = .nominal) -> (y: Double, z: Double) {
    let lean = (threshold - 90) * .pi / 180
    return (eye.y * cos(lean) - eye.z * sin(lean), eye.y * sin(lean) + eye.z * cos(lean))
}
func projectedWidth(_ deltaDegrees: Double, threshold: Double = 90) -> Double {
    let left = lidPanelPoint(imageX: -0.775, imageY: LidMetrics.standard.hingeDrop + 1, deltaDegrees: deltaDegrees, threshold: threshold)
    let right = lidPanelPoint(imageX: 0.775, imageY: LidMetrics.standard.hingeDrop + 1, deltaDegrees: deltaDegrees, threshold: threshold)
    return right.x - left.x
}
let widthAt = { (angle: Double, threshold: Double) in
    let g = EffectModel.geometry(angle: angle, threshold: threshold)
    return g.topRightX - g.topLeftX
}
check(abs(widthAt(89, 90) - projectedWidth(0.5)) < 1e-12, "the first degrees ease the rotation while staying a real projection")
check(abs(widthAt(88, 90) - projectedWidth(2)) < 1e-12, "the ease completes two degrees below the threshold")
check(abs(widthAt(90, 94) - projectedWidth(4, threshold: 94)) < 1e-12, "beyond the ease band the projection is untouched")
let foldStart = EffectModel.geometry(angle: 90, threshold: 94)
check(foldStart.topY > 1 && foldStart.topY < 1.02, "the picture's top row is already clipped above the panel at the start of the fold")
let fold55 = EffectModel.geometry(angle: 55, threshold: 94)
check(fold55.topY > 1.4 && widthAtGeom(fold55) < 0.5, "by lid 55° the top of the picture is far out of view")
// Viewport at 80° (10° of rotation): with the seated eye (y = 1.3, z = 1.6)
// the image's top corners project onto the panel at scale u across and
// (y + u·(1 − y)) / cos10 up.
// Millimetre presets convert with the panel's measured height, and a manual
// override reaches the projection.
let tallPanel = LidMetrics(hingeDropMM: 6.5, standoffMM: 4, cameraInsetMM: 3, cameraRecessMM: 1.5,
                           screenHeightMillimetres: 223.4)
check(abs(tallPanel.hingeDrop - 6.5 / 223.4) < 1e-12, "millimetre presets convert to screen heights")
let customLid = LidMetrics(hingeDropMM: 12, standoffMM: 8, cameraInsetMM: 6, cameraRecessMM: 3,
                           screenHeightMillimetres: 223.4)
let customFold = EffectModel.geometry(angle: 70, threshold: 90, metrics: customLid)
let defaultFold = EffectModel.geometry(angle: 70, threshold: 90)
check(customFold.bottomY > defaultFold.bottomY + 0.01, "a larger hinge offset moves the projected bottom edge")
check(MachineModel.identifier.isEmpty == false, "the machine model identifier is readable")

let fold60 = EffectModel.geometry(angle: 80, threshold: 90)
let u10 = projectedWidth(10)
let expectedTopRight = lidPanelPoint(imageX: 0.775, imageY: LidMetrics.standard.hingeDrop + 1, deltaDegrees: 10)
check(abs((fold60.topRightX - fold60.topLeftX) - u10) < 1e-12, "viewport follows the pinhole projection across the panel")
check(abs(fold60.topY - expectedTopRight.y) < 1e-12, "viewport follows the pinhole projection up the panel")
let expectedBottom = lidPanelPoint(imageX: -0.775, imageY: LidMetrics.standard.hingeDrop, deltaDegrees: 10)
check(abs(fold60.bottomY - expectedBottom.y) < 1e-12, "the bottom edge follows the same projection")
check(fold60.bottomY > 0 && fold60.bottomY < 0.05, "the hinge offset lifts the picture's bottom row off the panel's bottom edge")
let flat = EffectModel.geometry(angle: 45, threshold: 90, strength: 0)
check(flat.topLeftX == 0 && flat.topRightX == 1 && flat.topY == 1, "zero perspective remains flat")
check(flat.bottomLeftX == 0 && flat.bottomRightX == 1 && flat.bottomY == 0, "zero perspective keeps the bottom row pinned")

// Measured eye poses drive the opening instead of assuming a centered viewer.
let lowEye = EffectModel.geometry(angle: 80, threshold: 90, eye: EyePose(x: 0, y: 0.7, z: 1.6))
check(lowEye.topY < fold60.topY, "a lower eye still sees the picture's top")
let farEye = EffectModel.geometry(angle: 80, threshold: 90, eye: EyePose(x: 0, y: 1.3, z: 3.2))
check(farEye.topY < fold60.topY, "a farther seat hides slightly less of the top")
let nearEye = EffectModel.geometry(angle: 80, threshold: 90, eye: EyePose(x: 0, y: 1.3, z: 1.0))
check(nearEye.topY > fold60.topY, "a closer seat hides more of the top")
let rightEye = EffectModel.geometry(angle: 80, threshold: 90, eye: EyePose(x: 1.2, y: 1.3, z: 1.6))
check(rightEye.topLeftX > fold60.topLeftX + 0.01 && rightEye.topRightX > fold60.topRightX + 0.01, "lateral eye offset shifts the projection toward the viewer's side")
check(abs((rightEye.topRightX - rightEye.topLeftX) - (fold60.topRightX - fold60.topLeftX)) < 1e-12, "lateral eye offset leaves the sampled width unchanged")
let hingeEye = EffectModel.geometry(angle: 90, threshold: 94, eye: EyePose(x: 0, y: 0, z: 1.6))
check(hingeEye.topY < 1, "an eye level with the hinge keeps the whole picture on the panel — the old centred pose")
// Head-tracking math: a 14 cm face filling 26.6% of a 60° frame sits 0.5 m out.
let centered = FaceGeometry.estimate(faceBox: CGRect(x: 0.367, y: 0.35, width: 0.266, height: 0.3),
                                     frameWidth: 640, frameHeight: 480,
                                     horizontalFOVDegrees: 60, screenHeightMeters: 0.3)!
check(abs(centered.x) < 1e-9 && abs(centered.y) < 1e-9 && abs(centered.z - 0.5 / 0.3) < 0.01, "centered face estimates distance")
let moved = FaceGeometry.estimate(faceBox: CGRect(x: 0.134, y: 0.3, width: 0.266, height: 0.3),
                                  frameWidth: 640, frameHeight: 480,
                                  horizontalFOVDegrees: 60, screenHeightMeters: 0.3)!
check(moved.x > 0.1, "face left of center means the viewer sits to their right")
check(moved.y < 0, "face below the camera axis is below the camera axis")
let eyes = FaceGeometry.estimate(faceBox: CGRect(x: 0.367, y: 0.35, width: 0.266, height: 0.3),
                                 eyeCenter: CGPoint(x: 0.5, y: 0.55),
                                 frameWidth: 640, frameHeight: 480,
                                 horizontalFOVDegrees: 60, screenHeightMeters: 0.3)!
check(eyes.y > 0, "eye landmarks above the face-box centre raise the measured eye")
check(FaceGeometry.estimate(faceBox: CGRect(x: 0.4, y: 0.4, width: 0.95, height: 0.3),
                            frameWidth: 640, frameHeight: 480,
                            horizontalFOVDegrees: 60, screenHeightMeters: 0.3) == nil, "unreasonable face box rejected")
// The camera rides in the lid: world-eye rotation must undo the panel tilt.
let upright = FaceGeometry.worldEye(camera: EyePose(x: 0.2, y: 0.05, z: 1.6), lidAngleDegrees: 90)
let cameraLift = LidMetrics.standard.hingeDrop + 1 - LidMetrics.standard.cameraInset
let cameraStandoff = LidMetrics.standard.standoff - LidMetrics.standard.cameraRecess
check(abs(upright.x - 0.2) < 1e-12 && abs(upright.y - (cameraLift + 0.05)) < 1e-12 && abs(upright.z - (cameraStandoff + 1.6)) < 1e-12, "upright camera leaves the pose in place")
let tilted = FaceGeometry.worldEye(camera: EyePose(x: 0, y: 0, z: 1.6), lidAngleDegrees: 60)
let c30 = cos(30.0 * .pi / 180), s30 = sin(30.0 * .pi / 180)
check(abs(tilted.y - (cameraLift * c30 - (cameraStandoff + 1.6) * s30)) < 1e-12, "lid tilt lifts the measured head toward the hinge")
check(abs(tilted.z - (cameraLift * s30 + (cameraStandoff + 1.6) * c30)) < 1e-12, "lid tilt pushes the measured head outward")
var motion = EffectMotion()
let targetGeometry = EffectModel.geometry(angle: 45, threshold: 90)
motion.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60)
check(motion.radius > 0 && motion.radius < 20, "blur interpolates per frame")
check(motion.geometry.topRightX - motion.geometry.topLeftX < 1, "window interpolates per frame")
check(motion.geometry.topRightX - motion.geometry.topLeftX > targetGeometry.topRightX - targetGeometry.topLeftX, "window lags the target per frame")
check(motion.geometry.topY > 1 && motion.geometry.topY < targetGeometry.topY, "window height interpolates per frame")
check(motion.geometry.darkness > 0 && motion.geometry.darkness < targetGeometry.darkness, "darkness interpolates")
var at60 = EffectMotion(), at120 = EffectMotion()
for _ in 0..<6 { at60.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60) }
for _ in 0..<12 { at120.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 120) }
check(abs(at60.radius - at120.radius) < 0.000001, "motion independent of frame rate")
motion.advance(radius: 0, geometry: .identity, deltaTime: 1.0 / 60)
check(motion.radius == 0 && motion.geometry == .identity, "clear boundary never has smoothing lag")
var filter = AngleFilter()
check(filter.update(nil, at: 1) == nil, "filter passes missing sensor through")
check(filter.update(60, at: 1) == 60, "first reading passes through unfiltered")
let eased = filter.update(61, at: 1.1)!
check(eased > 60 && eased < 61, "quantized step eases toward the new reading")
var settled = AngleFilter()
_ = settled.update(30, at: 0)
var settledValue = 30.0
for step in 1...25 { settledValue = settled.update(31, at: Double(step) * 0.05)! }
check(abs(settledValue - 31) < 0.001, "filter converges on a steady reading")
check(settled.update(80, at: 1.3) == 80, "large jump snaps instead of lagging")
check(settled.update(nil, at: 1.35) == nil, "nil resets the filter state")
var slowFilter = AngleFilter(lookAhead: 0), fastFilter = AngleFilter(lookAhead: 0)
_ = slowFilter.update(30, at: 0)
_ = fastFilter.update(30, at: 0)
let slow = slowFilter.update(40, at: 0.06)!
var fast = 30.0
for step in 1...6 { fast = fastFilter.update(40, at: Double(step) * 0.01)! }
check(abs(slow - fast) < 0.000001, "filter independent of sample rate")
var leading = AngleFilter(), plain = AngleFilter(lookAhead: 0)
_ = leading.update(30, at: 0)
_ = plain.update(30, at: 0)
let led = leading.update(40, at: 0.06)!
let lagged = plain.update(40, at: 0.06)!
check(led > lagged && led <= 40, "look-ahead leads the smoothed angle without overshooting the reading")
if failures > 0 { exit(1) }
print("PASS: effect boundaries, invalid inputs, monotonicity, HID decoding and angle smoothing")
