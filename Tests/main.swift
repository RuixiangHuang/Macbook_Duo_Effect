import Foundation
var failures = 0
func check(_ condition: Bool, _ name: String) {
    if !condition { print("FAIL: \(name)"); failures += 1 }
}
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
let clearGeometry = EffectModel.geometry(angle: 90, threshold: 90)
check(clearGeometry.topHeight == 1 && clearGeometry.topWidth == 1 && clearGeometry.darkness == 0, "reference plane is identity")
let foldedGeometry = EffectModel.geometry(angle: 45, threshold: 90)
check(foldedGeometry.topHeight > 1 && foldedGeometry.topWidth < 1, "closing stretches past the top edge and narrows the top")
check(foldedGeometry.darkness > 0 && foldedGeometry.darkness < 1, "closing dims image")
check(EffectModel.geometry(angle: nil, threshold: 90) == .identity, "missing angle resets projection")
for x in stride(from: 10.0, through: 140, by: 1) {
    for a in 0...140 {
        let g = EffectModel.geometry(angle: Double(a), threshold: x)
        check(g.topHeight.isFinite && g.topWidth > 0 && g.darkness <= 0.65, "bounded geometry")
        check(g.topHeight <= 3 && g.topWidth >= 0.08, "projection is clamped")
        if Double(a) < x {
            check(g != .identity, "projection never silently drops out below the threshold at \(a)/\(x)")
        }
    }
}
// Strength blends between a flat image and the full projection; dimming is unaffected.
let full = EffectModel.geometry(angle: 45, threshold: 90, strength: 1)
let flat = EffectModel.geometry(angle: 45, threshold: 90, strength: 0)
let half = EffectModel.geometry(angle: 45, threshold: 90, strength: 0.5)
check(flat.topHeight == 1 && flat.topWidth == 1 && flat.darkness == full.darkness, "zero strength is flat but still dims")
check(half.topWidth > full.topWidth && half.topWidth < 1 && half.topHeight > 1 && half.topHeight < full.topHeight, "half strength sits between")
check(EffectModel.geometry(angle: 45, threshold: 90, strength: 7) == full, "strength clamps to 1")
// The eye turns with the lid, so only the angle between the planes matters.
let sameDelta = EffectModel.geometry(angle: 90, threshold: 120)
check(sameDelta.topHeight == EffectModel.geometry(angle: 60, threshold: 90).topHeight, "geometry depends on the difference angle only")
// Stretch grows and the top narrows monotonically as the lid closes; both are bounded.
// (At a few degrees the top lands a hair inside the lid, so start below 1.)
var previousHeight = 0.0, previousWidth = 1.0
for a in stride(from: 89, through: 0, by: -1) {
    let g = EffectModel.geometry(angle: Double(a), threshold: 90)
    check(g.topHeight >= previousHeight && g.topHeight <= 3 && g.topWidth <= previousWidth && g.topWidth >= 0.08,
          "geometry is monotonic and bounded at \(a)")
    previousHeight = g.topHeight; previousWidth = g.topWidth
}
// Closed form at 45° apart, where tan = 1: t = (L - 0.5) / (L + 0.5), top at 0.5 (1 + t) / cos 45°.
let l = EffectModel.eyeDistance
let expectedWidth = (l - 0.5) / (l + 0.5)
let fortyFive = EffectModel.geometry(angle: 45, threshold: 90)
check(abs(fortyFive.topWidth - expectedWidth) < 1e-9 && abs(fortyFive.topHeight - 0.5 * (1 + expectedWidth) / cos(Double.pi / 4)) < 1e-9,
      "45° apart matches the closed form")
// The original tuning was an eye 2.5 screen heights away: at 60° lid that gave 1.035 / 79%.
check(abs(EffectModel.geometry(angle: 60, threshold: 90).topWidth - ((l - 0.5 * tan(Double.pi / 6)) / (l + 0.5 * tan(Double.pi / 6)))) < 1e-9, "30° apart matches the closed form")
var motion = EffectMotion()
let targetGeometry = EffectModel.geometry(angle: 45, threshold: 90)
motion.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60)
check(motion.radius > 0 && motion.radius < 20, "blur interpolates per frame")
check(motion.geometry.topHeight < targetGeometry.topHeight && motion.geometry.topHeight > 1, "perspective interpolates rather than jumping")
check(motion.geometry.darkness > 0 && motion.geometry.darkness < targetGeometry.darkness, "darkness interpolates")
var at60 = EffectMotion(), at120 = EffectMotion()
for _ in 0..<6 { at60.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60) }
for _ in 0..<12 { at120.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 120) }
check(abs(at60.radius - at120.radius) < 0.000001, "motion independent of frame rate")
motion.advance(radius: 0, geometry: .identity, deltaTime: 1.0 / 60)
check(motion.radius == 0 && motion.geometry == .identity, "clear boundary never has smoothing lag")
if failures > 0 { exit(1) }
print("PASS: effect boundaries, invalid inputs, monotonicity and HID decoding")
