import AppKit
import Vision

let size = NSSize(width: 1400, height: 800)
let image = NSImage(size: size)
image.lockFocus()
NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let text = "CircuitCode OCR fixture: Save changes"
text.draw(
  at: NSPoint(x: 80, y: 360),
  withAttributes: [
    .font: NSFont.systemFont(ofSize: 54, weight: .semibold),
    .foregroundColor: NSColor.black,
  ]
)
image.unlockFocus()

guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
  fatalError("Could not create the OCR fixture image.")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try handler.perform([request])

let recognized = (request.results ?? [])
  .compactMap { $0.topCandidates(1).first?.string }
  .joined(separator: " ")
  .lowercased()

guard recognized.contains("circuitcode"),
      recognized.contains("save changes"),
      (request.results ?? []).allSatisfy({ observation in
        let box = observation.boundingBox
        return box.origin.x >= 0 && box.origin.y >= 0 &&
          box.size.width > 0 && box.size.height > 0 &&
          box.origin.x + box.size.width <= 1 &&
          box.origin.y + box.size.height <= 1
      })
else {
  fatalError("Vision OCR fixture did not recognize expected text: \(recognized)")
}

print("Vision OCR fixture passed: \(recognized)")
