/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Supporting code for the sample app.
*/

import Foundation
import MetalKit
import AVFoundation

extension ViewController {
    
    func setupMetal() {
        metalDevice = MTLCreateSystemDefaultDevice()
        metalCommandQueue = metalDevice.makeCommandQueue()
        
        cameraView.device = metalDevice
        cameraView.isPaused = true
        cameraView.enableSetNeedsDisplay = false
        cameraView.delegate = self
        cameraView.framebufferOnly = false
        cameraView.layer.isOpaque = false
    }
    
    func setupCoreImage() {
        ciContext = CIContext(mtlDevice: metalDevice)
    }
}

class AlphaFrameFilter: CIFilter {
  static var kernel: CIColorKernel? = {
    return CIColorKernel(source: """
kernel vec4 alphaFrame(__sample s, __sample m) {
  return vec4( s.rgb, m.r );
}
""")
  }()

  var inputImage: CIImage?
  var maskImage: CIImage?
  
  override var outputImage: CIImage? {
    let kernel = AlphaFrameFilter.kernel!

    guard let inputImage = inputImage, let maskImage = maskImage else {
      return nil
    }
    
    let args = [inputImage as AnyObject, maskImage as AnyObject]
    return kernel.apply(extent: inputImage.extent, arguments: args)
  }
}
