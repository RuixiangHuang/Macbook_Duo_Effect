import AppKit
import SwiftUI

// Renders the settings window offscreen in both languages as a layout and
// translation check. No screen capture, no permission. Output goes to .build;
// the images in docs/ are real screenshots of the running app.
// The view is hosted in a real (offscreen) NSWindow and drawn through AppKit,
// so the AppKit-backed controls — the language menu, the toggle, the sliders —
// render as they do in the app. ImageRenderer cannot draw those.
@MainActor
func render(_ language: Language, to path: String) {
    Localization.shared.language = language
    let model = AppModel()
    model.permission = true
    model.angle = 103
    let size = NSSize(width: 480, height: 660)
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: SettingsView(model: model))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    // Let SwiftUI and AppKit settle layout before drawing. The controls draw in
    // their untinted, inactive look: only a genuinely key window in a genuinely
    // active app gets the accent colour, and neither can be had offscreen.
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    host.layoutSubtreeIfNeeded()
    let scale: CGFloat = 2
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        print("FAIL: no bitmap for \(language.rawValue)"); exit(1)
    }
    rep.size = size
    // Ask for a Retina bitmap so the text and controls are crisp.
    guard let hi = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                    pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        print("FAIL: no hi-res bitmap"); exit(1)
    }
    hi.size = size
    host.cacheDisplay(in: host.bounds, to: hi)
    guard let png = hi.representation(using: .png, properties: [:]) else {
        print("FAIL: could not encode \(language.rawValue)"); exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: path))
    window.orderOut(nil)
    window.close()
    print("Wrote \(path)")
}

@main
enum SettingsRenderCheck {
    @MainActor
    static func main() {
        // AppKit needs an application instance to draw controls; keep it invisible.
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        render(.english, to: ".build/settings-en.png")
        render(.chinese, to: ".build/settings-zh.png")
        // Restore the shipped default so a render check never rewrites the user's choice.
        Localization.shared.language = .english
        print("PASS: settings window renders in both languages")
    }
}
