/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app shows how to use Vision person segmentation and detect face
 to perform realtime image masking effects.
*/

import UIKit
import Vision
import MetalKit
import AVFoundation
import CoreImage.CIFilterBuiltins

final class ViewController: UIViewController {
    
    // The Vision requests and the handler to perform them.
    private let requestHandler = VNSequenceRequestHandler()
    private var segmentationRequest = VNGeneratePersonSegmentationRequest()
    
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput!
    private var displayLink: CADisplayLink!
    private var playerItemObserver: NSKeyValueObservation?
    
    private var magic: Bool = false
    
    @IBOutlet weak var cameraView: MTKView! {
        didSet {
            guard metalDevice == nil else { return }
            setupMetal()
            setupCoreImage()
//            setupCaptureSession()
            setupPlayer()
        }
    }
    
    // The Metal pipeline.
    public var metalDevice: MTLDevice!
    public var metalCommandQueue: MTLCommandQueue!
    
    // The Core Image pipeline.
    public var ciContext: CIContext!
    public var currentCIImage: CIImage? {
        didSet {
            cameraView.draw()
        }
    }
    
    // The capture session that provides video frames.
    public var session: AVCaptureSession?
    
    // MARK: - UIAction
    @IBAction func changeMagic(sender: UISwitch) {
        self.magic = sender.isOn
    }
    
    // MARK: - ViewController LifeCycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initializeRequests()
    }
    
    deinit {
        session?.stopRunning()
    }
    
    // MARK: - Prepare Player
    private func setupPlayer() {
        let url = Bundle.main.url(forResource: "video", withExtension: "mp4")!
        let item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(outputSettings: nil)
        item.add(output)

        playerItemObserver = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            self?.playerItemObserver = nil
            self?.setupDisplayLink()
            print("play")
            self?.player?.play()
        }
        
        NotificationCenter.default.addObserver(self,
                                                   selector: #selector(repeatVideo),
                                                   name: .AVPlayerItemDidPlayToEndTime,
                                                   object: self.player?.currentItem)
        player = AVPlayer(playerItem: item) 
    }
    
    @objc func repeatVideo() {
        player?.pause()
            player?.currentItem?.seek(to: .zero, completionHandler: { _ in
                self.player?.play()
            })
    }
    
    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkUpdated(link:)))
        displayLink.preferredFramesPerSecond = 20
        displayLink.add(to: .main, forMode: RunLoop.Mode.common)
    }
    
    @objc private func displayLinkUpdated(link: CADisplayLink) {
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let pixbuf = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        processVideoFrame(pixbuf)
    }
    
    // MARK: - Prepare Requests
    
    private func initializeRequests() {
        
        // Create a request to segment a person from an image.
        segmentationRequest = VNGeneratePersonSegmentationRequest()
        segmentationRequest.qualityLevel = .balanced
        segmentationRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }
    
    // MARK: - Perform Requests
    
    private func processVideoFrame(_ framePixelBuffer: CVPixelBuffer) {
        if self.magic == false {
            self.currentCIImage = CIImage(cvPixelBuffer: framePixelBuffer)
            return
        }
        
        // Perform the requests on the pixel buffer that contains the video frame.
        try? requestHandler.perform([segmentationRequest],
                                    on: framePixelBuffer,
                                    orientation: .right)
        
        // Get the pixel buffer that contains the mask image.
        guard let maskPixelBuffer =
                segmentationRequest.results?.first?.pixelBuffer else { return }
        
        // Process the images.
        blend(original: framePixelBuffer, mask: maskPixelBuffer)
    }
    
    // MARK: - Process Results
    
    // Performs the blend operation.
    private func blend(original framePixelBuffer: CVPixelBuffer,
                       mask maskPixelBuffer: CVPixelBuffer) {
        
        
        // Create CIImage objects for the video frame and the segmentation mask.
        let originalImage = CIImage(cvPixelBuffer: framePixelBuffer).oriented(.right)
        var maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)
        
        // Scale the mask image to fit the bounds of the video frame.
        let scaleX = originalImage.extent.width / maskImage.extent.width
        let scaleY = originalImage.extent.height / maskImage.extent.height
        maskImage = maskImage.transformed(by: .init(scaleX: scaleX, y: scaleY))
        
        let blendFilter = AlphaFrameFilter()
        blendFilter.maskImage = maskImage
        blendFilter.inputImage = originalImage
        
        let blended = blendFilter.outputImage?.oriented(.left)
        
//        var outline = colorized(ciimage: maskImage.oriented(.left), with: .black)
//        
//        let edgeFilter = CIFilter.edges()
//        edgeFilter.inputImage = maskImage.oriented(.left)
//        edgeFilter.intensity = 1
//        
//        let morphologyFilter = CIFilter.morphologyMaximum()
//        morphologyFilter.inputImage = edgeFilter.outputImage
//        morphologyFilter.radius = 100
//        
//        let maskFilter = CIFilter.maskToAlpha()
//        maskFilter.inputImage = morphologyFilter.outputImage
//        
//        let revertFilter = CIFilter.colorInvert()
//        revertFilter.inputImage = maskFilter.outputImage
        
        let final = blended //blended?.composited(over: revertFilter.outputImage!)
        
        // Set the new, blended image as current.
//        currentCIImage = blendFilter.outputImage?.oriented(.left)
        currentCIImage = final
    }
    
    func colorized(ciimage: CIImage?, with color: UIColor) -> CIImage? {
        guard
            let ciimage = ciimage,
            let colorMatrix = CIFilter(name: "CIColorMatrix")
            else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        colorMatrix.setDefaults()
        colorMatrix.setValue(ciimage, forKey: "inputImage")
        colorMatrix.setValue(CIVector(x: r, y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: b, w: 0), forKey: "inputBVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: a), forKey: "inputAVector")
         
        return colorMatrix.outputImage
    }
}
