import AppKit
import CoreImage
import Metal
@main struct Perf {
 static func main() {
  let device = MTLCreateSystemDefaultDevice()!
  let queue = device.makeCommandQueue()!
  let context = CIContext(mtlCommandQueue:queue, options:[.cacheIntermediates:false])
  let extent = CGRect(x:0,y:0,width:3024,height:1964)
  let input = CIFilter(name:"CICheckerboardGenerator",parameters:["inputWidth":24])!.outputImage!.cropped(to:extent)
  let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:3024,height:1964,mipmapped:false)
  desc.usage = [.shaderRead,.shaderWrite,.renderTarget]; desc.storageMode = .private
  let texture = device.makeTexture(descriptor:desc)!
  for mode in ["CGImage", "Metal"] {
   var times:[Double]=[]
   for i in 0..<65 {
    autoreleasepool {
     let output = EffectProcessor.image(input,radius:32,geometry:EffectModel.geometry(angle:Double(45+i%20),threshold:90))
     let start=CFAbsoluteTimeGetCurrent()
     if mode == "CGImage" {
      let image=context.createCGImage(output,from:extent)!
      // Force evaluation as the compositor eventually does for layer contents.
      _ = image.dataProvider?.data
     } else {
      let command=queue.makeCommandBuffer()!
      context.render(output,to:texture,commandBuffer:command,bounds:extent,colorSpace:CGColorSpace(name:CGColorSpace.sRGB)!)
      command.commit(); command.waitUntilCompleted()
     }
     if i>=5 { times.append((CFAbsoluteTimeGetCurrent()-start)*1000) }
    }
   }
   times.sort();print("\(mode): median=\(times[30])ms p95=\(times[57])ms")
  }
 }
}
