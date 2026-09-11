import CoreImage

/// The same image pipeline is used by the live stream and the render verification fixture.
enum EffectProcessor {
    /// Preserve Core Image coordinates for the macOS MTKView presentation path.
    /// Do not add a vertical flip: the AppKit drawable presentation handles orientation.
    static func metalImage(_ image: CIImage, bounds: CGRect) -> CIImage {
        let scaled = image.transformed(by: CGAffineTransform(scaleX: bounds.width / image.extent.width,
                                                             y: bounds.height / image.extent.height))
        return scaled
    }

    static func image(_ input: CIImage, radius: Double, geometry: EffectGeometry) -> CIImage {
        let width = input.extent.width
        let height = input.extent.height
        let inset = width * (1 - geometry.topWidth) / 2
        let transformed = input.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: inset, y: height * geometry.topHeight),
            "inputTopRight": CIVector(x: width - inset, y: height * geometry.topHeight),
            "inputBottomLeft": CIVector(x: 0, y: 0),
            "inputBottomRight": CIVector(x: width, y: 0)
        ])
        let background = CIImage(color: CIColor.black).cropped(to: input.extent)
        let projected = transformed.composited(over: background).cropped(to: input.extent)
        // Distance from the bottom hinge controls the local blur radius.
        // Keep a small blur at the hinge and ramp smoothly to full blur at the camera.
        let mask = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: input.extent.midX, y: input.extent.minY),
            "inputPoint1": CIVector(x: input.extent.midX, y: input.extent.maxY),
            "inputColor0": CIColor(red: 0.05, green: 0.05, blue: 0.05),
            "inputColor1": CIColor.white
        ])!.outputImage!.cropped(to: input.extent)
        let light = 1 - geometry.darkness
        let output = projected.clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [kCIInputRadiusKey: radius, "inputMask": mask])
            .cropped(to: input.extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: light, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: light, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: light, w: 0)
            ])
        return output
    }
}
