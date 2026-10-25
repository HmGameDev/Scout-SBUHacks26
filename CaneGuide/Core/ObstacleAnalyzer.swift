import Foundation
import simd

/// Turns a depth frame into the nearest obstacle distance in each zone, plus the
/// direction of the clearest opening.
///
/// Every depth pixel is projected into gravity-aligned world space, so it works
/// whether the phone is portrait, landscape or tilted. Distances are measured along
/// the smoothed walking heading, not the camera direction, so sweeping the cane
/// scans across the zones instead of rotating them.
enum ObstacleAnalyzer {
    static func analyze(_ frame: DepthFrame, heading: SIMD2<Float>, floorY: Float?) -> AnalysisResult {
        let transform = frame.cameraTransform
        let cameraPosition = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = simd_normalize(SIMD3(heading.x, 0, heading.y))
        let right = simd_cross(forward, SIMD3<Float>(0, 1, 0))

        // First pass: project every sampled pixel and keep the ones inside the corridor.
        var points: [(lateral: Float, ahead: Float, height: Float)] = []
        var heights: [Float] = []
        var sampled = 0
        var valid = 0

        let step = Tuning.sampleStride
        for v in stride(from: 0, to: frame.height, by: step) {
            for u in stride(from: 0, to: frame.width, by: step) {
                sampled += 1
                let index = v * frame.width + u
                let d = frame.depth[index]
                guard d.isFinite, d > 0.1, d <= Tuning.maxRange + 1 else { continue }
                if let confidence = frame.confidence, confidence[index] < 1 { continue }
                valid += 1

                let world = worldPoint(frame, u: Float(u), v: Float(v), depth: d)
                let offset = world - cameraPosition
                let ahead = simd_dot(offset, forward)
                guard ahead <= Tuning.maxRange else { continue }
                heights.append(world.y)
                let lateral = simd_dot(offset, right)
                guard ahead >= Tuning.minForward, abs(lateral) <= Tuning.corridorHalfWidth else { continue }
                points.append((lateral, ahead, world.y))
            }
        }

        let floor = floorY ?? estimateFloor(heights, cameraHeight: cameraPosition.y)
            ?? cameraPosition.y - Tuning.defaultCameraHeight
        let lowestObstacle = floor + Tuning.floorClearance
        let highestObstacle = cameraPosition.y + Tuning.headroom
        // Within the cane's reach the cane itself finds low obstacles (and is in view itself),
        // so only things at about phone height or higher count there: walls, doors, branches.
        let lowestWithinReach = cameraPosition.y - Tuning.withinReachBelowCamera

        // Second pass: floor counts as evidence an area is visible; only raised points are obstacles.
        var zoneSeen = [Int](repeating: 0, count: Zone.allCases.count)
        var zoneHits: [[Float]] = Array(repeating: [], count: Zone.allCases.count)
        var stripSeen = [Int](repeating: 0, count: Tuning.gapStrips)
        var stripHits: [[Float]] = Array(repeating: [], count: Tuning.gapStrips)
        for point in points {
            guard let zone = zone(forLateral: point.lateral) else { continue }
            let strip = strip(forLateral: point.lateral)
            zoneSeen[zone.rawValue] += 1
            stripSeen[strip] += 1
            let lowest = point.ahead < Tuning.caneReach ? max(lowestObstacle, lowestWithinReach) : lowestObstacle
            if point.height >= lowest && point.height <= highestObstacle {
                zoneHits[zone.rawValue].append(point.ahead)
                stripHits[strip].append(point.ahead)
            }
        }

        var zones: [Zone: ZoneObservation] = [:]
        for zone in Zone.allCases where zoneSeen[zone.rawValue] >= Tuning.minSamplesPerZone {
            zones[zone] = ZoneObservation(distance: nearestCluster(zoneHits[zone.rawValue]),
                                          sampleCount: zoneSeen[zone.rawValue])
        }

        // Free distance per strip: nil when the strip wasn't in view.
        let strips: [Float?] = (0..<Tuning.gapStrips).map { i in
            stripSeen[i] >= Tuning.minSamplesPerStrip ? (nearestCluster(stripHits[i]) ?? Tuning.maxRange) : nil
        }

        return AnalysisResult(zones: zones,
                              validFraction: sampled == 0 ? 0 : Float(valid) / Float(sampled),
                              gapOffset: bestGap(strips))
    }

    /// Projects depth pixel (u, v) into world space.
    /// ARKit camera space: +X right, +Y up, -Z forward (image v grows downward).
    static func worldPoint(_ frame: DepthFrame, u: Float, v: Float, depth d: Float) -> SIMD3<Float> {
        let k = frame.intrinsics
        let local = SIMD4((u - k[2][0]) / k[0][0] * d, -(v - k[2][1]) / k[1][1] * d, -d, 1)
        let world = frame.cameraTransform * local
        return SIMD3(world.x, world.y, world.z)
    }

    /// Nearest distance that has a real object behind it: at least `minObstaclePoints`
    /// points within `clusterDepth` of each other. A thin pole close by wins over a big
    /// wall further away, while stray noisy pixels are ignored.
    static func nearestCluster(_ distances: [Float]) -> Float? {
        let needed = Tuning.minObstaclePoints
        guard distances.count >= needed else { return nil }
        let sorted = distances.sorted()
        var end = 0
        for start in sorted.indices {
            end = max(end, start)
            while end < sorted.count && sorted[end] <= sorted[start] + Tuning.clusterDepth { end += 1 }
            if end - start >= needed { return sorted[start + needed / 4] }
        }
        return nil
    }

    /// Gap-seeking (after Shepherd): lateral offset in meters of the clearest opening wide
    /// enough to walk through, preferring straight ahead when several are equally clear.
    static func bestGap(_ strips: [Float?]) -> Float? {
        let middle = Float(strips.count - 1) / 2
        var best: (index: Int, opening: Float)?
        for i in strips.indices {
            // A body-width path needs this strip and its neighbours to be free.
            let window = (max(0, i - 1)...min(strips.count - 1, i + 1)).map { strips[$0] }
            guard window.allSatisfy({ $0 != nil }) else { continue }
            let opening = window.compactMap { $0 }.min()!
            if let current = best {
                let clearlyMoreOpen = opening > current.opening + 0.05
                let asOpenButStraighter = abs(opening - current.opening) <= 0.05
                    && abs(Float(i) - middle) < abs(Float(current.index) - middle)
                guard clearlyMoreOpen || asOpenButStraighter else { continue }
            }
            best = (i, opening)
        }
        return best.map { stripCenter($0.index) }
    }

    /// The floor is the lowest large surface in view. Returns nil when nothing seen is
    /// far enough below the camera to be floor (e.g. the camera only sees a wall).
    static func estimateFloor(_ heights: [Float], cameraHeight: Float) -> Float? {
        guard heights.count >= Tuning.minSamplesPerZone else { return nil }
        let floor = lowPercentile(heights, Tuning.floorPercentile)
        return floor <= cameraHeight - Tuning.minCameraHeight ? floor : nil
    }

    static func zone(forLateral lateral: Float) -> Zone? {
        if abs(lateral) <= Tuning.centerHalfWidth { return .center }
        if lateral < 0 && lateral >= -Tuning.corridorHalfWidth { return .left }
        if lateral > 0 && lateral <= Tuning.corridorHalfWidth { return .right }
        return nil
    }

    private static var stripWidth: Float { 2 * Tuning.corridorHalfWidth / Float(Tuning.gapStrips) }

    static func strip(forLateral lateral: Float) -> Int {
        min(Tuning.gapStrips - 1, max(0, Int((lateral + Tuning.corridorHalfWidth) / stripWidth)))
    }

    static func stripCenter(_ index: Int) -> Float {
        -Tuning.corridorHalfWidth + (Float(index) + 0.5) * stripWidth
    }

    static func lowPercentile(_ values: [Float], _ p: Float) -> Float {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Float(sorted.count - 1) * p))]
    }
}
