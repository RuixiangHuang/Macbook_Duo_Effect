import CoreImage
import Foundation
@main struct GradientBlurCheck {
 static func main() {
  let context = CIContext()
  let bounds = CGRect(x:0,y:0,width:256,height:256)
  let input = CIFilter(name:"CICheckerboardGenerator",parameters:["inputWidth":8,"inputSharpness":1])!.outputImage!.cropped(to:bounds)
  let output = EffectProcessor.image(input,radius:14,geometry:.identity)
  func contrast(_ y: Int) -> Double {
   // Render a one-row crop in explicit Core Image coordinates, avoiding bitmap row-order assumptions.
   var pixels=[UInt8](repeating:0,count:256*4)
   context.render(output,toBitmap:&pixels,rowBytes:256*4,bounds:CGRect(x:0,y:y,width:256,height:1),format:.RGBA8,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
   let values=(32..<224).map { Double(pixels[$0*4]) }
   return values.max()! - values.min()!
  }
  let hinge = contrast(16), camera = contrast(239)
  print("hinge contrast=\(hinge), camera contrast=\(camera)")
  guard hinge > camera + 20 else { print("FAIL: hinge must retain more detail than camera edge"); exit(1) }
  print("PASS: spatial blur increases from hinge to camera")
 }
}
