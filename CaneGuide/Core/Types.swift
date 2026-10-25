import Foundation
import simd

/// The walking corridor ahead is split into three side-by-side zones.
enum Zone: Int, CaseIterable {
    case left, center, right
}

struct ZoneObservation: Equatable {
    /// Forward distance in meters to the nearest obstacle in this zone.
    /// nil means the zone was in view and nothing was within range.
    var distance: Float?
    var sampleCount: Int
}

/// One LiDAR depth frame plus the camera pose it was captured from.
/// Kept free of ARKit types so the logic can be tested on a Mac.
struct DepthFrame {
    /// Meters, row-major, width * height, in the sensor's native (landscape) orientation.
    var depth: [Float]
    /// ARConfidenceLevel raw values (0 low, 1 medium, 2 high), same layout as depth.
    var confidence: [UInt8]?
    var width: Int
    var height: Int
    /// Camera intrinsics scaled to the depth map resolution.
    var intrinsics: simd_float3x3
    /// Camera-to-world transform. World is gravity aligned: +Y is up.
    var cameraTransform: simd_float4x4
}

struct AnalysisResult {
    /// Only zones that had enough samples to say anything.
    var zones: [Zone: ZoneObservation]
    /// Fraction of sampled pixels that had usable depth.
    var validFraction: Float
    /// Lateral offset in meters (negative is left) of the clearest opening, if any was in view.
    var gapOffset: Float? = nil
}

enum Cue: Equatable {
    case clear, veerLeft, veerRight, stop, blocked, unreliable

    var isStop: Bool { self == .stop || self == .blocked }
    var isObstacle: Bool { isStop || self == .veerLeft || self == .veerRight }

    /// What gets spoken.
    var phrase: String {
        switch self {
        case .clear: return "Path clear."
        case .veerLeft: return "Obstacle ahead. Go left."
        case .veerRight: return "Obstacle ahead. Go right."
        case .stop: return "Stop. Obstacle ahead."
        case .blocked: return "Stop. Path blocked."
        case .unreliable: return "Can't see the path. Check the phone angle."
        }
    }

    /// Stop warnings say how far away the obstacle is.
    func phrase(distance: Float?) -> String {
        guard self == .stop, let distance else { return phrase }
        return "Stop. Obstacle \(Cue.spoken(distance)) ahead."
    }

    static func spoken(_ meters: Float) -> String {
        String(format: "%.1f meters", meters)
    }

    /// What the big status label shows.
    var label: String {
        switch self {
        case .clear: return "CLEAR"
        case .veerLeft: return "GO LEFT"
        case .veerRight: return "GO RIGHT"
        case .stop: return "STOP"
        case .blocked: return "BLOCKED"
        case .unreliable: return "CAN'T SEE"
        }
    }
}
