import ARKit

struct SensorFrame {
    var depth: DepthFrame
    /// Floor height if ARKit has found the floor plane.
    var floorY: Float?
    var trackingOK: Bool
    /// People found in the camera image (normalized sensor points); nil when not checked this frame.
    var people: [SIMD2<Float>]?
    var timestamp: TimeInterval
}

/// Runs an ARKit session (no camera view needed) and delivers LiDAR depth frames
/// at about 30 Hz on a background queue, plus people found in the camera image.
final class DepthSensor: NSObject, ARSessionDelegate {
    static var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Called on the processing queue with each analyzed frame.
    var onFrame: (@Sendable (SensorFrame) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    private let session = ARSession()
    private let queue = DispatchQueue(label: "caneguide.depth", qos: .userInteractive)
    private var frameCount = 0
    private let personDetector = PersonDetector()
    private var lastPersonCheck: TimeInterval = 0

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = queue
    }

    func start() {
        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        config.planeDetection = [.horizontal]
        // Raw depth, not ARKit's smoothed depth: smoothing blends frames together, which
        // smears obstacles into ghosts while the cane sweeps.
        config.frameSemantics = .sceneDepth
        frameCount = 0
        lastPersonCheck = 0
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        guard frameCount % Tuning.frameSkip == 0, let depthData = frame.sceneDepth else { return }

        var trackingOK = false
        if case .normal = frame.camera.trackingState { trackingOK = true }

        // Person detection is slower, so it runs a few times a second.
        var people: [SIMD2<Float>]?
        if frame.timestamp - lastPersonCheck >= Tuning.personCheckInterval {
            lastPersonCheck = frame.timestamp
            people = personDetector.detect(in: frame.capturedImage,
                                           orientation: .from(cameraTransform: frame.camera.transform))
        }

        onFrame?(SensorFrame(depth: Self.makeDepthFrame(depthData, camera: frame.camera),
                             floorY: Self.floorHeight(frame.anchors),
                             trackingOK: trackingOK,
                             people: people,
                             timestamp: frame.timestamp))
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onError?(error.localizedDescription)
    }

    /// Lowest plane ARKit has classified as floor.
    private static func floorHeight(_ anchors: [ARAnchor]) -> Float? {
        guard ARPlaneAnchor.isClassificationSupported else { return nil }
        return anchors.compactMap { anchor -> Float? in
            guard let plane = anchor as? ARPlaneAnchor, case .floor = plane.classification else { return nil }
            return plane.transform.columns.3.y
        }.min()
    }

    /// Copies the depth and confidence buffers out of the frame so ARKit can recycle it.
    private static func makeDepthFrame(_ data: ARDepthData, camera: ARCamera) -> DepthFrame {
        let depthMap = data.depthMap
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let depth: [Float] = copyPixels(depthMap, width: width, height: height)
        let confidence: [UInt8]? = data.confidenceMap.map { copyPixels($0, width: width, height: height) }

        // Intrinsics are given for the full camera image; scale them down to the depth map.
        let scaleX = Float(width) / Float(camera.imageResolution.width)
        let scaleY = Float(height) / Float(camera.imageResolution.height)
        var k = camera.intrinsics
        k[0][0] *= scaleX
        k[1][1] *= scaleY
        k[2][0] *= scaleX
        k[2][1] *= scaleY

        return DepthFrame(depth: depth, confidence: confidence, width: width, height: height,
                          intrinsics: k, cameraTransform: camera.transform)
    }

    private static func copyPixels<T>(_ buffer: CVPixelBuffer, width: Int, height: Int) -> [T] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var pixels: [T] = []
        pixels.reserveCapacity(width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: T.self)
            pixels.append(contentsOf: UnsafeBufferPointer(start: row, count: width))
        }
        return pixels
    }
}
