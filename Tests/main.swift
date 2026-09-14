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
check(EffectModel.geometry(angle: 90, threshold: 90) == .identity, "threshold restores clear screen")
check(EffectModel.geometry(angle: nil, threshold: 90) == .identity, "missing sensor clears")
for threshold in [10.0, 90, 114, 140] {
    for strength in [0.0, 0.5, 1] {
        var previousWidth = 1.0, previousDarkness = 0.0
        for angle in stride(from: threshold, through: 0, by: -0.5) {
            let state = EffectModel.geometry(angle: angle, threshold: threshold, strength: strength)
            check(state.topHeight == 1, "no vertical shrink-grow reversal")
            check(state.topWidth <= previousWidth && state.topWidth >= 0.08, "top edge only narrows on closing")
            check(state.darkness >= previousDarkness && state.darkness <= 1, "closing fades monotonically")
            previousWidth = state.topWidth; previousDarkness = state.darkness
        }
    }
}
check(EffectModel.geometry(angle: 45, threshold: 90).topWidth < 1, "perspective remains visible")
check(EffectModel.geometry(angle: 0, threshold: 90).darkness == 1, "closed fades fully to black")
let flat = EffectModel.geometry(angle: 45, threshold: 90, strength: 0)
check(flat.topWidth == 1 && flat.topHeight == 1, "zero perspective remains flat")
var motion = EffectMotion()
let targetGeometry = EffectModel.geometry(angle: 45, threshold: 90)
motion.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60)
check(motion.radius == 20, "blur follows the sensor target immediately")
check(motion.geometry.topWidth < 1 && motion.geometry.topWidth > targetGeometry.topWidth && motion.geometry.topHeight == 1, "trapezoid interpolates without vertical resizing")
check(motion.geometry.darkness > 0 && motion.geometry.darkness < targetGeometry.darkness, "darkness interpolates")
var at60 = EffectMotion(), at120 = EffectMotion()
for _ in 0..<6 { at60.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 60) }
for _ in 0..<12 { at120.advance(radius: 20, geometry: targetGeometry, deltaTime: 1.0 / 120) }
check(at60.radius == 20 && at120.radius == 20, "immediate blur is independent of frame rate")
check(abs(at60.geometry.topWidth - at120.geometry.topWidth) < 0.000001 &&
      abs(at60.geometry.darkness - at120.geometry.darkness) < 0.000001,
      "geometry smoothing is independent of frame rate")
motion.advance(radius: 0, geometry: .identity, deltaTime: 1.0 / 60)
check(motion.radius == 0 && motion.geometry == .identity, "clear boundary never has smoothing lag")
if failures > 0 { exit(1) }
print("PASS: effect boundaries, invalid inputs, monotonicity and HID decoding")
