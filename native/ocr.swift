import Foundation
import Vision
import ImageIO

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("Expected a readable image path\n", stderr)
    exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
request.automaticallyDetectsLanguage = true
do {
    try VNImageRequestHandler(cgImage: image).perform([request])
    let elements = (request.results ?? []).compactMap { observation -> [String: Any]? in
        guard let text = observation.topCandidates(1).first else { return nil }
        let rect = observation.boundingBox
        return [
            "text": text.string,
            "confidence": text.confidence,
            "x": rect.minX * Double(image.width),
            "y": (1 - rect.maxY) * Double(image.height),
            "width": rect.width * Double(image.width),
            "height": rect.height * Double(image.height)
        ]
    }
    let data = try JSONSerialization.data(withJSONObject: elements, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
} catch {
    fputs("OCR failed: \(error)\n", stderr)
    exit(1)
}
