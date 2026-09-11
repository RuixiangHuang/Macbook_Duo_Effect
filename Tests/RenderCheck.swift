import AppKit
import CoreImage

@main struct RenderCheck {
    static func main() throws {
        let width = 480, height = 320
        let fixture = NSImage(size: NSSize(width: width, height: height))
        fixture.lockFocus()
        NSColor(calibratedRed: 0.15, green: 0.22, blue: 0.40, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for row in 0..<3 {
            for col in 0..<5 {
                let rect = NSRect(x: 24 + col * 88, y: 30 + row * 87, width: 70, height: 65)
                NSColor(calibratedHue: CGFloat(row * 5 + col) / 18, saturation: 0.55, brightness: 0.92, alpha: 1).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
                ("\(row * 5 + col + 1)" as NSString).draw(at: NSPoint(x: rect.minX + 25, y: rect.minY + 18), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: NSColor.white])
            }
        }
        fixture.unlockFocus()
        let raw = CIImage(data: fixture.tiffRepresentation!)!
        let input = raw.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / raw.extent.width, y: CGFloat(height) / raw.extent.height))
        let context = CIContext()
        let sheet = NSImage(size: NSSize(width: width * 3, height: height + 50))
        sheet.lockFocus()
        NSColor.black.setFill(); NSRect(x: 0, y: 0, width: width * 3, height: height + 50).fill()
        for (i, angle) in [90.0, 70, 45].enumerated() {
            let geometry = EffectModel.geometry(angle: angle, threshold: 90)
            let radius = EffectModel.radius(angle: angle, threshold: 90, maximum: 32, enabled: true)
            let output = EffectProcessor.image(input, radius: radius, geometry: geometry)
            guard let cg = context.createCGImage(output, from: input.extent) else { fatalError("Rendering failed") }
            assert(cg.width == width && cg.height == height)
            NSImage(cgImage: cg, size: NSSize(width: width, height: height)).draw(in: NSRect(x: i * width, y: 0, width: width, height: height))
            ("x = 90°  |  lid = \(Int(angle))°" as NSString).draw(at: NSPoint(x: i * width + 18, y: height + 15), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white])
        }
        sheet.unlockFocus()
        let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/effect-preview.png"))
        print("PASS: Core Image perspective / blur / dim render at 90°, 70°, 45°")
    }
}
