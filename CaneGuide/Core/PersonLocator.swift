import Foundation
import simd

/// How the camera image must be rotated to look upright, worked out from gravity,
/// so Apple Vision sees people standing up however the phone is mounted.
enum ImageOrientation: Equatable {
    case up, down, left, right

    static func from(cameraTransform t: simd_float4x4) -> ImageOrientation {
        // How much the sensor image's right (+X) and up (+Y) axes point at the sky.
        let rightUp = t.columns.0.y
        let upUp = t.columns.1.y
        if abs(upUp) >= abs(rightUp) { return upUp >= 0 ? .up : .down }
        return rightUp < 0 ? .right : .left
    }

    /// Converts a Vision point (normalized, upright image, origin bottom-left) to a
    /// normalized sensor-image point (origin top-left, matching the depth map).
    func sensorPoint(fromVision p: SIMD2<Float>) -> SIMD2<Float> {
        switch self {
        case .up: return SIMD2(p.x, 1 - p.y)
        case .down: return SIMD2(1 - p.x, p.y)
        case .right: return SIMD2(1 - p.y, 1 - p.x)
        case .left: return SIMD2(p.y, p.x)
        }
    }
}

/// Uses LiDAR depth to measure how far away a person found by Vision is.
enum PersonLocator {
    /// Forward distance to the nearest person in or near the walking path.
    /// `points` are normalized sensor-image points at the center of each person.
    static func nearest(_ points: [SIMD2<Float>], in frame: DepthFrame, heading: SIMD2<Float>) -> Float? {
        let t = frame.cameraTransform
        let cameraPosition = SIMD3(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        let forward = simd_normalize(SIMD3(heading.x, 0, heading.y))
        let right = simd_cross(forward, SIMD3<Float>(0, 1, 0))

        var nearest: Float?
        for point in points {
            let u = min(frame.width - 1, max(0, Int(point.x * Float(frame.width))))
            let v = min(frame.height - 1, max(0, Int(point.y * Float(frame.height))))
            guard let depth = medianDepth(frame, u: u, v: v, radius: 3) else { continue }

            let offset = ObstacleAnalyzer.worldPoint(frame, u: Float(u), v: Float(v), depth: depth) - cameraPosition
            let ahead = simd_dot(offset, forward)
            let lateral = simd_dot(offset, right)
            guard ahead >= Tuning.minForward, ahead <= Tuning.personRange,
                  abs(lateral) <= Tuning.corridorHalfWidth + Tuning.personSideMargin else { continue }
            nearest = min(nearest ?? .infinity, ahead)
        }
        return nearest
    }

    private static func medianDepth(_ frame: DepthFrame, u: Int, v: Int, radius: Int) -> Float? {
        var values: [Float] = []
        for y in max(0, v - radius)...min(frame.height - 1, v + radius) {
            for x in max(0, u - radius)...min(frame.width - 1, u + radius) {
                let d = frame.depth[y * frame.width + x]
                if d.isFinite && d > 0.1 { values.append(d) }
            }
        }
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}
