// Logic checks for the Core folder. Runs on a Mac without Xcode: ./run-checks.sh
import Foundation
import simd

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print(condition ? "  pass  \(message)" : "  FAIL  \(message)")
    if !condition { failures += 1 }
}
func near(_ value: Float?, _ expected: Float, _ tolerance: Float = 0.05) -> Bool {
    guard let value else { return false }
    return abs(value - expected) <= tolerance
}

// Synthetic depth camera: 256x192, camera at the origin looking along -Z, 1 m above the floor.
let width = 256, height = 192
let fx: Float = 200, fy: Float = 200, cx: Float = 128, cy: Float = 96
let intrinsics = simd_float3x3(columns: (SIMD3(fx, 0, 0), SIMD3(0, fy, 0), SIMD3(cx, cy, 1)))
let floorY: Float = -1.0
let straightAhead = SIMD2<Float>(0, -1)

func makeFrame(_ depthAt: (Int, Int) -> Float) -> DepthFrame {
    var depth = [Float](repeating: 0, count: width * height)
    for v in 0..<height { for u in 0..<width { depth[v * width + u] = depthAt(u, v) } }
    return DepthFrame(depth: depth, confidence: nil, width: width, height: height,
                      intrinsics: intrinsics, cameraTransform: matrix_identity_float4x4)
}
/// Depth of the floor seen by pixel row v (no return above the horizon).
func floorDepth(_ v: Int) -> Float {
    Float(v) > cy ? fy / (Float(v) - cy) : 0
}

print("ObstacleAnalyzer")
do {
    let wall = ObstacleAnalyzer.analyze(makeFrame { _, _ in 1.5 }, heading: straightAhead, floorY: floorY)
    check(near(wall.zones[.center]?.distance, 1.5), "wall at 1.5 m is seen in the center")
    check(near(wall.zones[.left]?.distance, 1.5) && near(wall.zones[.right]?.distance, 1.5), "wall spans left and right")

    let openFloor = ObstacleAnalyzer.analyze(makeFrame { _, v in floorDepth(v) }, heading: straightAhead, floorY: floorY)
    check(Zone.allCases.allSatisfy { openFloor.zones[$0] != nil }, "open floor: all zones in view")
    check(Zone.allCases.allSatisfy { openFloor.zones[$0]?.distance == nil }, "open floor: floor is not an obstacle")
    check(openFloor.validFraction > Tuning.minValidFraction, "open floor has enough valid depth")

    let boxOnLeft = ObstacleAnalyzer.analyze(makeFrame { u, v in
        (u < 60 && (40...150).contains(v)) ? 1.2 : floorDepth(v)
    }, heading: straightAhead, floorY: floorY)
    check(near(boxOnLeft.zones[.left]?.distance, 1.2), "box on the left is detected at 1.2 m")
    check(boxOnLeft.zones[.center]?.distance == nil, "box on the left leaves the center clear")
    check(boxOnLeft.zones[.right]?.distance == nil, "box on the left leaves the right clear")

    let cane = ObstacleAnalyzer.analyze(makeFrame { _, v in v > 150 ? 0.3 : floorDepth(v) }, heading: straightAhead, floorY: floorY)
    check(cane.zones[.center]?.distance == nil, "objects closer than minForward (the cane) are ignored")

    let blank = ObstacleAnalyzer.analyze(makeFrame { _, _ in 0 }, heading: straightAhead, floorY: floorY)
    check(blank.zones.isEmpty && blank.validFraction == 0, "no depth means no zones")
}

print("False stops (cane-mounted phone, floor plane not found yet)")
/// Camera `height` m above the floor at y = 0, pitched down by `pitchDegrees`.
func mountedCamera(height: Float, pitchDegrees: Float) -> simd_float4x4 {
    let a = -pitchDegrees * .pi / 180
    var t = simd_float4x4(simd_quatf(angle: a, axis: SIMD3(1, 0, 0)))
    t.columns.3 = SIMD4(0, height, 0, 1)
    return t
}
/// Depth image of a flat floor (plus optional extras) seen from `transform`.
func mountedFrame(_ transform: simd_float4x4, extra: (Int, Int) -> Float? = { _, _ in nil }) -> DepthFrame {
    var frame = makeFrame { u, v in
        if let d = extra(u, v) { return d }
        let ray = SIMD3((Float(u) - cx) / fx, -(Float(v) - cy) / fy, -1)
        let world = transform * SIMD4(ray, 0)
        return world.y < -1e-3 ? transform.columns.3.y / -world.y : 0
    }
    frame.cameraTransform = transform
    return frame
}
do {
    for (height, pitch) in [(Float(0.8), Float(0)), (0.7, 30), (1.2, 20), (0.9, 45)] {
        let r = ObstacleAnalyzer.analyze(mountedFrame(mountedCamera(height: height, pitchDegrees: pitch)),
                                         heading: straightAhead, floorY: nil)
        check(r.zones[.center] != nil && Zone.allCases.allSatisfy { r.zones[$0]?.distance == nil },
              "floor only, phone \(height) m high, tilted \(Int(pitch))°: no obstacle")
    }

    let tilted = mountedCamera(height: 0.8, pitchDegrees: 30)
    let box = ObstacleAnalyzer.analyze(mountedFrame(tilted) { u, v in
        (100...156).contains(u) && (20...90).contains(v) ? 1.6 : nil
    }, heading: straightAhead, floorY: nil)
    check(box.zones[.center]?.distance != nil, "a real obstacle ahead is still found with the estimated floor")

    let specks = ObstacleAnalyzer.analyze(mountedFrame(tilted) { u, v in
        (u % 37 == 0 && v % 29 == 0) ? 1.0 : nil
    }, heading: straightAhead, floorY: nil)
    check(specks.zones[.center]?.distance == nil, "a few stray noisy pixels don't count as an obstacle")
}


print("HapticPlan")
check(HapticPlan.pulse(forDistance: nil) == nil, "nothing ahead: no vibration")
check(HapticPlan.pulse(forDistance: 0.5)?.intensity == 1.0, "under 1 m: strongest")
check(HapticPlan.pulse(forDistance: 2.5)?.interval == 0.8, "2-3 m: slow taps")
check(HapticPlan.pulse(forDistance: 4) == nil, "beyond 3 m: no vibration")

print("HeadingSmoother")
do {
    var smoother = HeadingSmoother()
    _ = smoother.update(cameraForward: SIMD3(0, 0, -1), dt: 0)
    let swung = smoother.update(cameraForward: SIMD3(1, 0, 0), dt: 1.0 / 15)!
    check(swung.y < -0.9, "one quick cane swing barely moves the heading")
    for _ in 0..<150 { _ = smoother.update(cameraForward: SIMD3(1, 0, 0), dt: 1.0 / 15) }
    check(smoother.heading!.x > 0.99, "a sustained turn moves the heading")
    let down = smoother.update(cameraForward: SIMD3(0, -1, 0), dt: 1.0 / 15)
    check(down == smoother.heading, "pointing straight down keeps the last heading")
}

print("GuidanceEngine")
let frameTime = 1.0 / 15
func zones(_ left: Float?, _ center: Float?, _ right: Float?) -> AnalysisResult {
    AnalysisResult(zones: [
        .left: ZoneObservation(distance: left, sampleCount: 100),
        .center: ZoneObservation(distance: center, sampleCount: 100),
        .right: ZoneObservation(distance: right, sampleCount: 100),
    ], validFraction: 1)
}
/// Feeds the same result for n frames; returns everything announced.
func feed(_ engine: inout GuidanceEngine, _ result: AnalysisResult?, frames: Int, from start: inout Double) -> [Cue] {
    var said: [Cue] = []
    for _ in 0..<frames {
        if let cue = engine.update(result, now: start) { said.append(cue) }
        start += frameTime
    }
    return said
}
do {
    var engine = GuidanceEngine(); var t = 0.0
    check(feed(&engine, zones(nil, nil, nil), frames: 30, from: &t) == [.clear], "open path: says 'path clear' once")
    check(feed(&engine, zones(nil, 0.8, nil), frames: 2, from: &t) == [.stop], "obstacle at 0.8 m: stop within 2 frames")
    check(feed(&engine, zones(nil, 0.8, nil), frames: 44, from: &t) == [], "stop isn't repeated within 3 s")
    check(feed(&engine, zones(nil, 0.8, nil), frames: 2, from: &t) == [.stop], "stop repeats after 3 s")
    _ = feed(&engine, zones(nil, 1.2, nil), frames: 5, from: &t)
    check(engine.cue == .stop, "hysteresis: 1.2 m still counts as stop")
    _ = feed(&engine, zones(1.0, 1.5, nil), frames: 5, from: &t)
    check(engine.cue == .veerRight, "obstacle at 1.5 m, left blocked: go right")
    _ = feed(&engine, zones(nil, 1.5, 1.0), frames: 5, from: &t)
    check(engine.cue == .veerLeft, "right blocked: go left")
    _ = feed(&engine, zones(1.5, 1.5, 1.5), frames: 5, from: &t)
    check(engine.cue == .blocked, "everything within 2 m: blocked")
}
do {
    var engine = GuidanceEngine(); var t = 0.0
    _ = feed(&engine, zones(nil, 1.5, 1.0), frames: 5, from: &t)
    _ = feed(&engine, zones(2.5, 1.5, 2.8), frames: 5, from: &t)
    check(engine.cue == .veerLeft, "veer direction doesn't flip on a small difference")
}
do {
    var engine = GuidanceEngine(); var t = 0.0
    check(feed(&engine, nil, frames: 15, from: &t) == [], "can't see for 1 s: stays quiet")
    check(feed(&engine, nil, frames: 30, from: &t) == [.unreliable], "can't see for 3 s: warns once")
}
do {
    var engine = GuidanceEngine(); var t = 0.0
    _ = feed(&engine, zones(nil, 0.8, nil), frames: 3, from: &t)
    let said = feed(&engine, zones(nil, 0.8, nil), frames: 1, from: &t) + feed(&engine, nil, frames: 10, from: &t)
    check(engine.cue == .stop && said.isEmpty, "a few untrusted frames keep the last warning (zone memory)")
}

print("GuidancePipeline")
do {
    let pipeline = GuidancePipeline()
    var out: PipelineOutput?
    for i in 0..<10 {
        out = pipeline.process(makeFrame { _, _ in 0.8 }, floorY: floorY, trackingOK: true,
                               movingTooFast: false, timestamp: Double(i) * frameTime)
    }
    check(out?.cue == .blocked, "wall filling the view at 0.8 m: blocked")
    check(near(out?.nearestAhead, 0.8), "pipeline reports the distance ahead")

    let blurry = GuidancePipeline()
    for i in 0..<10 {
        out = blurry.process(makeFrame { _, _ in 0.8 }, floorY: floorY, trackingOK: true,
                             movingTooFast: true, timestamp: Double(i) * frameTime)
    }
    check(out?.cue == .unreliable, "frames during a violent swing are ignored")
}

print("Thin obstacles and gap-seeking")
do {
    // A 6 cm wide pole 1.5 m ahead, in front of a wall 4 m away.
    let poleHalfWidthPx = Int(0.03 / 1.5 * fx)
    let pole = ObstacleAnalyzer.analyze(makeFrame { u, v in
        abs(u - 128) <= poleHalfWidthPx ? 1.5 : 4.0
    }, heading: straightAhead, floorY: floorY)
    check(near(pole.zones[.center]?.distance, 1.5, 0.1), "thin pole in front of a far wall is found at 1.5 m")

    // Wall at 1.2 m on the left and center; open floor visible to the right.
    let opening = ObstacleAnalyzer.analyze(makeFrame { u, v in
        (Float(u) - cx) / fx * 1.2 < 0.15 ? 1.2 : floorDepth(v)
    }, heading: straightAhead, floorY: floorY)
    check((opening.gapOffset ?? 0) > 0.4, "gap-seeking points to the opening on the right")

    let clear = ObstacleAnalyzer.analyze(makeFrame { _, v in floorDepth(v) }, heading: straightAhead, floorY: floorY)
    check(abs(clear.gapOffset ?? 99) < 0.2, "with nothing in the way the best gap is straight ahead")
}

print("Guidance follows the gap")
do {
    var engine = GuidanceEngine(); var t = 0.0
    var result = zones(nil, 1.5, nil)
    result.gapOffset = -0.7
    _ = feed(&engine, result, frames: 6, from: &t)
    check(engine.cue == .veerLeft, "obstacle ahead with the opening on the left: go left")
    result.gapOffset = 0.7
    _ = feed(&engine, result, frames: 6, from: &t)
    check(engine.cue == .veerRight, "the opening moves to the right: go right")
}

print("Person detection")
do {
    let portrait = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 0, 1)))
    check(ImageOrientation.from(cameraTransform: matrix_identity_float4x4) == .up, "landscape camera: image is upright")
    check(ImageOrientation.from(cameraTransform: portrait) == .right, "portrait phone: image needs .right")
    let p = ImageOrientation.right.sensorPoint(fromVision: SIMD2(1, 0.5))
    check(near(p.x, 0.5) && near(p.y, 0), "portrait: right edge of the picture is sensor row 0")

    // A person-sized patch 2 m ahead in the middle of the image.
    let personFrame = makeFrame { u, v in (100...156).contains(u) && (40...150).contains(v) ? 2.0 : floorDepth(v) }
    let ahead = PersonLocator.nearest([SIMD2(0.5, 0.5)], in: personFrame, heading: straightAhead)
    check(near(ahead, 2.0), "a detected person is measured at 2 m with LiDAR")
    let offToSide = PersonLocator.nearest([SIMD2(0.5, 0.5)], in: personFrame, heading: SIMD2(1, 0))
    check(offToSide == nil, "a person who isn't ahead of you is ignored")

    var engine = GuidanceEngine(); var t = 0.0
    _ = feed(&engine, zones(nil, nil, nil), frames: 3, from: &t)
    check(engine.personAlert(2.0, now: t) == 2.0, "first sighting of a person is announced")
    check(engine.personAlert(2.0, now: t + 1) == nil, "the same person isn't announced again right away")
}

print("Spoken distances")
check(Cue.stop.phrase(distance: 0.84) == "Stop. Obstacle 0.8 meters ahead.", "stop says how far")
check(Cue.veerLeft.phrase(distance: 1.5) == Cue.veerLeft.phrase, "other cues keep their short phrase")


print("Cane in view")
do {
    // Phone 0.8 m up, tilted down 30°. The cane runs from just below the phone to the floor 1 m ahead.
    let tilted = mountedCamera(height: 0.8, pitchDegrees: 30)
    func worldRay(_ u: Int, _ v: Int) -> SIMD3<Float> {
        let r = tilted * SIMD4((Float(u) - cx) / fx, -(Float(v) - cy) / fy, -1, 0)
        return SIMD3(r.x, r.y, r.z)
    }
    func caneDepth(_ u: Int, _ v: Int) -> Float? {
        // March along the ray and see whether it hits the 3 cm thick cane.
        let ray = worldRay(u, v)
        for step in 1...150 {
            let d = Float(step) * 0.01
            let p = SIMD3<Float>(0, 0.8, 0) + ray * d
            let t = max(0, min(1, -p.z))               // 0 at the phone, 1 at the tip
            if simd_length(p - SIMD3(0, 0.7 - 0.7 * t, -t)) < 0.015 { return d }
        }
        return nil
    }
    let withCane = ObstacleAnalyzer.analyze(mountedFrame(tilted, extra: caneDepth), heading: straightAhead, floorY: nil)
    check(withCane.zones[.center] != nil && withCane.zones[.center]?.distance == nil, "the cane itself is not an obstacle")

    // An upright wall 0.7 m ahead.
    let wallClose = ObstacleAnalyzer.analyze(mountedFrame(tilted) { u, v in
        let ray = worldRay(u, v)
        return ray.z < 0 ? 0.7 / -ray.z : nil
    }, heading: straightAhead, floorY: nil)
    check(near(wallClose.zones[.center]?.distance, 0.7, 0.1), "a wall within cane reach is still a stop")
}

print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
