import AppKit

if CommandLine.arguments.contains("--probe") {
    let sensor = LidSensor()
    if let angle = sensor.read() {
        print("Lid angle: \(angle)° — \(sensor.status.text)")
        exit(0)
    } else {
        print("Sensor unavailable: \(sensor.status.text)")
        exit(1)
    }
}
if CommandLine.arguments.contains("--self-check") {
    print("Bundle: \(Bundle.main.bundleIdentifier ?? "unbundled")")
    print("Built-in display: \(BlurOverlay.builtInScreen != nil)")
    print("Screen Recording permission: \(CGPreflightScreenCaptureAccess())")
    print("Threshold boundary clears: \(EffectModel.radius(angle: 90, threshold: 90, maximum: 32, enabled: true) == 0)")
    exit(0)
}
if CommandLine.arguments.contains("--debug-log-path") {
    print(DebugLog.shared.fileURL.path)
    exit(0)
}
let app = NSApplication.shared
let delegate = AppController()
app.delegate = delegate
app.run()
