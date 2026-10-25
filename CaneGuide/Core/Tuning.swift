import Foundation

/// Every number you might want to adjust after a test walk lives here.
enum Tuning {
    // Guidance thresholds (meters, measured forward along the walking direction)
    static let stopDistance: Float = 1.0
    static let veerDistance: Float = 2.0
    /// Extra distance needed to leave a warning, so cues don't flicker at the boundary.
    static let hysteresis: Float = 0.3
    /// How much freer the other side must be before switching veer direction.
    static let veerSwitchMargin: Float = 0.5

    // Corridor geometry (meters)
    static let maxRange: Float = 5.0
    /// Ignore anything closer than this; it is usually the cane itself.
    static let minForward: Float = 0.4
    /// How far ahead the cane reaches. Closer than this, the cane shaft is in view and the cane
    /// already finds low obstacles, so only points no lower than `withinReachBelowCamera`
    /// under the phone count as obstacles.
    static let caneReach: Float = 1.0
    static let withinReachBelowCamera: Float = 0.1
    static let centerHalfWidth: Float = 0.35
    static let corridorHalfWidth: Float = 1.0
    /// Points less than this above the floor count as floor, not obstacles.
    static let floorClearance: Float = 0.2
    /// Points this far above the camera are ignored (keeps overhanging branches, drops ceilings).
    static let headroom: Float = 1.0
    /// Until ARKit finds the floor plane, the floor is estimated as this low percentile of point heights.
    static let floorPercentile: Float = 0.03
    /// An estimated floor must be at least this far below the camera to be believed.
    static let minCameraHeight: Float = 0.3
    /// Used when the floor can't be seen or estimated.
    static let defaultCameraHeight: Float = 1.0

    // Depth sampling
    static let sampleStride = 2
    static let minSamplesPerZone = 15
    /// An obstacle needs this many depth points within `clusterDepth` of each other,
    /// so specks of noise don't count but a thin pole does.
    static let minObstaclePoints = 12
    static let clusterDepth: Float = 0.3
    static let minValidFraction: Float = 0.1
    /// Analyze every Nth ARKit frame (60 fps / 2 = 30 Hz).
    static let frameSkip = 2

    // Gap-seeking: the corridor is split into thin strips to find the clearest opening.
    static let gapStrips = 7
    static let minSamplesPerStrip = 8
    /// Gap directions are averaged over this many frames to stop left/right flicker.
    static let gapHistory = 5
    /// A gap closer to straight ahead than this (meters) doesn't decide left vs right.
    static let gapDeadband: Float = 0.15
    /// How far the gap must move to the other side before switching veer direction.
    static let gapSwitch: Float = 0.3

    // People (Apple Vision + LiDAR distance)
    static let personRange: Float = 5.0
    static let personSideMargin: Float = 0.5
    static let personCheckInterval: TimeInterval = 0.4
    static let personRepeatInterval: TimeInterval = 5.0

    // Motion
    /// Seconds over which the walking direction is averaged, so cane sweeps don't swing the zones.
    static let headingTimeConstant: Double = 1.0
    /// Camera pointing nearly straight up or down (|forward.y| above this) is unusable.
    static let maxCameraTilt: Float = 0.9
    /// Gyro rotation rate (rad/s) above which frames are too blurry to trust.
    static let maxRotationRate: Double = 6.0

    // Announcements (seconds)
    static let zoneMemory: TimeInterval = 1.0
    static let cueConfirmFrames = 2
    static let minAnnounceInterval: TimeInterval = 1.5
    static let repeatStopInterval: TimeInterval = 3.0
    static let unreliableGrace: TimeInterval = 2.0
    static let repeatUnreliableInterval: TimeInterval = 10.0

    // Haptics: (closer than meters, seconds between taps, intensity 0-1)
    static let hapticBands: [(distance: Float, interval: TimeInterval, intensity: Float)] = [
        (1.0, 0.15, 1.0),
        (2.0, 0.40, 0.7),
        (3.0, 0.80, 0.4),
    ]

    // Navigation (meters)
    static let announceTurnDistance: Double = 20
    static let reachedStepDistance: Double = 8
    static let arrivedDistance: Double = 15
}
