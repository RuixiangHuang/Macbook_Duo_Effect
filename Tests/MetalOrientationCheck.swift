import CoreImage
import Metal
import Foundation
import CoreVideo
@main struct MetalOrientationCheck {
 static func main() {
  let device = MTLCreateSystemDefaultDevice()!
  let commands = device.makeCommandQueue()!
  let context = CIContext(mtlCommandQueue:commands)
  let bounds = CGRect(x:0,y:0,width:16,height:16)
  // ScreenCaptureKit supplies CVPixelBuffers, not procedural CIImage generators.
  // Match that real input path: row zero is blue, bottom row is red.
  var pixelBuffer: CVPixelBuffer?
  let attrs: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                            kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
  precondition(CVPixelBufferCreate(kCFAllocatorDefault,16,16,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&pixelBuffer) == kCVReturnSuccess)
  let buffer = pixelBuffer!
  CVPixelBufferLockBaseAddress(buffer, [])
  let data = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to:UInt8.self)
  let stride = CVPixelBufferGetBytesPerRow(buffer)
  for y in 0..<16 {
   for x in 0..<16 {
    let offset = y * stride + x * 4
    data[offset] = y < 8 ? 255 : 0
    data[offset+1] = 0
    data[offset+2] = y < 8 ? 0 : 255
    data[offset+3] = 255
   }
  }
  CVPixelBufferUnlockBaseAddress(buffer, [])
  let input = CIImage(cvPixelBuffer:buffer)
  let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:16,height:16,mipmapped:false)
  desc.usage = [.shaderRead,.shaderWrite,.renderTarget];desc.storageMode = .shared
  let texture=device.makeTexture(descriptor:desc)!
  let command=commands.makeCommandBuffer()!
  let colorSpace = CGColorSpace(name:CGColorSpace.sRGB)!
  context.render(EffectProcessor.metalImage(input, bounds: bounds),to:texture,commandBuffer:command,bounds:bounds,colorSpace:colorSpace)
  command.commit();command.waitUntilCompleted()
  var bytes=[UInt8](repeating:0,count:16*16*4)
  texture.getBytes(&bytes,bytesPerRow:16*4,from:MTLRegionMake2D(0,0,16,16),mipmapLevel:0)
  // Compare against untransformed Core Image output. Texture memory row order
  // alone is not the final AppKit on-screen direction (the previous test assumed it was).
  let referenceTexture = device.makeTexture(descriptor:desc)!
  let referenceCommand = commands.makeCommandBuffer()!
  context.render(input,to:referenceTexture,commandBuffer:referenceCommand,bounds:bounds,colorSpace:colorSpace)
  referenceCommand.commit(); referenceCommand.waitUntilCompleted()
  var reference = [UInt8](repeating:0,count:bytes.count)
  referenceTexture.getBytes(&reference,bytesPerRow:64,from:MTLRegionMake2D(0,0,16,16),mipmapLevel:0)
  guard bytes == reference else {
   print("FAIL: unexpected coordinate transform: top BGRA=\(Array(bytes[0..<4])) bottom=\(Array(bytes[960..<964]))")
   exit(1)
  }
  print("PASS: presentation adds no vertical flip to the Core Image output")
 }
}
