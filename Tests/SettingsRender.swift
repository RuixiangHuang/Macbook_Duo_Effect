import AppKit
import SwiftUI

// Renders the settings window offscreen in both languages. No screen capture,
// no permission: this checks layout and translation, not the live effect.
// ImageRenderer cannot rasterize AppKit-backed controls, so the language menu,
// the enable toggle and the two sliders appear as placeholder bars.
@MainActor
func render(_ language: Language, to path: String) {
    Localization.shared.language = language
    let model = AppModel()
    model.permission = true
    model.angle = 103
    let renderer = ImageRenderer(content: SettingsView(model: model))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("FAIL: could not render \(language.rawValue)")
        exit(1)
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}

@main
enum SettingsRenderCheck {
    @MainActor
    static func main() {
        render(.english, to: "docs/settings-en.png")
        render(.chinese, to: "docs/settings-zh.png")
        // Restore the shipped default so a render check never rewrites the user's choice.
        Localization.shared.language = .english
        print("PASS: settings window renders in both languages")
    }
}
