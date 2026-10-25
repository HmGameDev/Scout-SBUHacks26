import Foundation
import simd

/// Averages the camera's horizontal direction over time so the left/center/right
/// zones follow where the person is walking, not where the cane is swinging.
struct HeadingSmoother {
    /// Unit vector on the ground plane as (x, z).
    private(set) var heading: SIMD2<Float>?

    mutating func update(cameraForward: SIMD3<Float>, dt: Double) -> SIMD2<Float>? {
        let flat = SIMD2(cameraForward.x, cameraForward.z)
        let length = simd_length(flat)
        // Pointing straight up or down says nothing about walking direction.
        guard length > 0.1 else { return heading }
        let direction = flat / length

        guard let current = heading else {
            heading = direction
            return direction
        }
        let alpha = Float(1 - exp(-max(dt, 0) / Tuning.headingTimeConstant))
        let blended = current + (direction - current) * alpha
        heading = simd_length(blended) > 1e-3 ? simd_normalize(blended) : direction
        return heading
    }
}
