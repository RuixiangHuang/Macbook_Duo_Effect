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
check(foldedGeometry.topHeight > 1 && foldedGeometry.topWidth < 1, "closing stretches and narrows around bottom hinge")
check(foldedGeometry.darkness > 0 && foldedGeometry.darkness < 1, "closing dims image")
check(EffectModel.geometry(angle: nil, threshold: 90) == .identity, "missing angle resets projection")
for x in [10.0, 90, 140] {
    for a in 0...140 {
        let g = EffectModel.geometry(angle: Double(a), threshold: x)
        check(g.topHeight.isFinite && g.topWidth > 0 && g.darkness <= 0.65, "bounded geometry")
    }
}
var motion = EffectMotion()
let targetGeometry = EffectModel.geometry(angle: 45, threshold: 90)
motion.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60)
check(motion.radius > 0 && motion.radius < 20, "blur interpolates per frame")
check(motion.geometry.topWidth > targetGeometry.topWidth && motion.geometry.topWidth < 1, "perspective interpolates rather than jumping")
check(motion.geometry.darkness > 0 && motion.geometry.darkness < targetGeometry.darkness, "darkness interpolates")
var at60 = EffectMotion(), at120 = EffectMotion()
for _ in 0..<6 { at60.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60) }
for _ in 0..<12 { at120.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 120) }
check(abs(at60.radius - at120.radius) < 0.000001, "motion independent of frame rate")
motion.advance(radius: 0, geometry: .identity, deltaTime: 1.0 / 60)
check(motion.radius == 0 && motion.geometry == .identity, "clear boundary never has smoothing lag")
if failures > 0 { exit(1) }
print("PASS: effect boundaries, invalid inputs, monotonicity and HID decoding")
