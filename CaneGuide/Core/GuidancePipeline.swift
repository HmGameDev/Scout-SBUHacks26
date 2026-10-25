import Foundation
import simd

struct PipelineOutput {
    var cue: Cue
    /// Cue to speak now, if any.
    var announce: Cue?
    var zones: [Zone: Float?]
    var nearestAhead: Float?
    /// Distance to a person ahead, when it's time to announce one.
    var personAhead: Float?
}

/// Depth frame in, guidance out. Runs on the depth processing queue only.
final class GuidancePipeline {
    private var smoother = HeadingSmoother()
    private var engine = GuidanceEngine()
    private var lastTimestamp: TimeInterval?

    /// `people`: normalized sensor points of people Vision found, or nil if it didn't look this frame.
    func process(_ frame: DepthFrame, floorY: Float?, trackingOK: Bool, movingTooFast: Bool,
                 people: [SIMD2<Float>]? = nil, timestamp: TimeInterval) -> PipelineOutput {
        let dt = lastTimestamp.map { timestamp - $0 } ?? 0
        lastTimestamp = timestamp

        let back = frame.cameraTransform.columns.2
        let cameraForward = -SIMD3(back.x, back.y, back.z)
        let angleOK = abs(cameraForward.y) < Tuning.maxCameraTilt
        let heading = smoother.update(cameraForward: cameraForward, dt: dt)

        var result: AnalysisResult?
        if trackingOK, angleOK, !movingTooFast, let heading {
            let analysis = ObstacleAnalyzer.analyze(frame, heading: heading, floorY: floorY)
            if analysis.validFraction >= Tuning.minValidFraction { result = analysis }
        }

        let announce = engine.update(result, now: timestamp)

        var personAhead: Float?
        if let people, !people.isEmpty, result != nil, let heading {
            personAhead = engine.personAlert(PersonLocator.nearest(people, in: frame, heading: heading),
                                             now: timestamp)
        }
        return PipelineOutput(cue: engine.cue, announce: announce, zones: engine.zoneDistances,
                              nearestAhead: engine.nearestAhead, personAhead: personAhead)
    }
}
