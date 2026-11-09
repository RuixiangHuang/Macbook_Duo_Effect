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
        // Pinhole viewport: the four vectors are where the image's corners
        // land on the panel, so the fixed image is projected through the eye
        // onto the tilting screen. Nothing is stretched to fit and no mask is
        // used: black appears only where the panel looks past the image.
        let transformed = input.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: width * geometry.topLeftX, y: height * geometry.topY),
            "inputTopRight": CIVector(x: width * geometry.topRightX, y: height * geometry.topY),
            "inputBottomLeft": CIVector(x: width * geometry.bottomLeftX, y: height * geometry.bottomY),
            "inputBottomRight": CIVector(x: width * geometry.bottomRightX, y: height * geometry.bottomY)
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
        let dimmed = projected.clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [kCIInputRadiusKey: radius, "inputMask": mask])
            .cropped(to: input.extent)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: light, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: light, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: light, w: 0)
            ])
        guard geometry.crease > 0.001 else { return dimmed }
        // Crease shadow: a dark seam hugging the hinge, scaling with the fold
        // rotation like the shading model's S(θ). Twelve percent of the
        // height, up to 28% darker at the very seam.
        let depth = 0.28 * min(1, geometry.crease)
        let crease = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: input.extent.midX, y: input.extent.minY),
            "inputPoint1": CIVector(x: input.extent.midX, y: input.extent.minY + height * 0.12),
            "inputColor0": CIColor(red: 1 - depth, green: 1 - depth, blue: 1 - depth, alpha: 1),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ])!.outputImage!.cropped(to: input.extent)
        return dimmed.applyingFilter("CIMultiplyCompositing", parameters: [
            "inputBackgroundImage": crease
        ]).cropped(to: input.extent)
    }
}
