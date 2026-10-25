import ImageIO
import Vision

/// Finds people in the camera image with Apple Vision, on the phone.
final class PersonDetector {
    private let request = VNDetectHumanRectanglesRequest()

    init() {
        request.upperBodyOnly = false
    }

    /// Normalized sensor-image points (origin top-left, same layout as the depth map)
    /// at the center of each person found.
    func detect(in image: CVPixelBuffer, orientation: ImageOrientation) -> [SIMD2<Float>] {
        let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: orientation.cgOrientation)
        guard (try? handler.perform([request])) != nil, let people = request.results else { return [] }
        return people.filter { $0.confidence > 0.5 }.map { person in
            let box = person.boundingBox
            return orientation.sensorPoint(fromVision: SIMD2(Float(box.midX), Float(box.midY)))
        }
    }
}

private extension ImageOrientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}
