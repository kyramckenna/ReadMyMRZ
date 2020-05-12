

import Foundation
import UIKit
import AVFoundation
import Vision

class VisionViewController: ViewController {
	var request: VNRecognizeTextRequest!
	// Temporal string tracker
	let numberTracker = StringTracker()
	
    @IBOutlet weak var textView: UITextView!
    
    var oldText = ""
    
    override func viewDidLoad() {
		// Set up vision request before letting ViewController set up the camera
		// so that it exists when the first buffer is received.
		request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)

		super.viewDidLoad()
	}
	
	// MARK: - Text recognition
	
	// Vision recognition handler.
	func recognizeTextHandler(request: VNRequest, error: Error?) {
		var numbers = [String]()
		var redBoxes = [CGRect]() // Shows all recognized text lines
		var greenBoxes = [CGRect]() // Shows words that might be serials
		
		guard let results = request.results as? [VNRecognizedTextObservation] else {
			return
		}
		
		let maximumCandidates = 2
        var mrz = [String]()
        
		
		for visionResult in results {
			guard let candidate = visionResult.topCandidates(maximumCandidates).first else { continue }
			
			// Draw red boxes around any detected text, and green boxes around
			// any detected phone numbers. The phone number may be a substring
			// of the visionResult. If a substring, draw a green box around the
			// number and a red box around the full string. If the number covers
			// the full result only draw the green box.
			var numberIsSubstring = true
			
			if let result = candidate.string.extractPhoneNumber() {
				let (range, number) = result
				// Number may not cover full visionResult. Extract bounding box
				// of substring.
				if let box = try? candidate.boundingBox(for: range)?.boundingBox {
					numbers.append(number)
					greenBoxes.append(box)
					numberIsSubstring = !(range.lowerBound == candidate.string.startIndex && range.upperBound == candidate.string.endIndex)
				}
			}
            
			if numberIsSubstring {
                
				redBoxes.append(visionResult.boundingBox)
                
                // The machine-readable zone of a Type 3 travel document spans two lines, and each line is 44 characters long
                if(candidate.string.count > 44){
                    let fixedText = String(candidate.string.filter { !" \n\t\r".contains($0) })
                    mrz.append(fixedText)
                    print(fixedText)
                }
			}
		}
        
        if(mrz != nil){
            if(mrz.count > 1){
                if( mrz[0].starts(with: "P<AUS") || mrz[0].starts(with: "P<IRL") || mrz[0].starts(with: "P<GBR")
                ){
                    let concat = mrz[0] + mrz[1]
                    self.log(text: concat, pauseLog: true)
                }
            }
        }
        
		// Log any found numbers.
		numberTracker.logFrame(strings: numbers)
		show(boxGroups: [(color: UIColor.red.cgColor, boxes: redBoxes), (color: UIColor.green.cgColor, boxes: greenBoxes)])
		
		// Check if we have any temporally stable numbers.
		if let sureNumber = numberTracker.getStableString() {
			showString(string: sureNumber)
			numberTracker.reset(string: sureNumber)
            
		}
	}
    
    // LOGGING EVENTS TO TEXT FILE AND EMAIL THEM TO EMAIL ACCOUNT
    
    func log(text: String, pauseLog: Bool) {
        
        if(oldText != text){
            oldText = text
            DispatchQueue.main.async
            {
                //let newLogText = (self.textView.text ?? "\n") + text + "\n"
                let newLogText = text + "\n"
                self.textView.text = newLogText
                self.textView.scrollRangeToVisible(NSMakeRange(self.textView.text.count - 1,0))
            }
        }
    }
	
	override func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
			// Configure for running in real-time.
			request.recognitionLevel = .fast
			// Language correction won't help recognizing phone numbers. It also
			// makes recognition slower.
			request.usesLanguageCorrection = false
			// Only run on the region of interest for maximum speed.
			request.regionOfInterest = regionOfInterest
			
			let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: textOrientation, options: [:])
			do {
				try requestHandler.perform([request])
			} catch {
				print(error)
			}
		}
	}
	
	// MARK: - Bounding box drawing
	
	// Draw a box on screen. Must be called from main queue.
	var boxLayer = [CAShapeLayer]()
	func draw(rect: CGRect, color: CGColor) {
		let layer = CAShapeLayer()
		layer.opacity = 0.5
		layer.borderColor = color
		layer.borderWidth = 1
		layer.frame = rect
		boxLayer.append(layer)
		previewView.videoPreviewLayer.insertSublayer(layer, at: 1)
	}
	
	// Remove all drawn boxes. Must be called on main queue.
	func removeBoxes() {
		for layer in boxLayer {
			layer.removeFromSuperlayer()
		}
		boxLayer.removeAll()
	}
	
	typealias ColoredBoxGroup = (color: CGColor, boxes: [CGRect])
	
	// Draws groups of colored boxes.
	func show(boxGroups: [ColoredBoxGroup]) {
		DispatchQueue.main.async {
			let layer = self.previewView.videoPreviewLayer
			self.removeBoxes()
			for boxGroup in boxGroups {
				let color = boxGroup.color
				for box in boxGroup.boxes {
					let rect = layer.layerRectConverted(fromMetadataOutputRect: box.applying(self.visionToAVFTransform))
					self.draw(rect: rect, color: color)
				}
			}
		}
	}
}
