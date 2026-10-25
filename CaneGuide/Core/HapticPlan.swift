import Foundation

struct HapticPulse: Equatable {
    var interval: TimeInterval
    var intensity: Float
}

/// Parking-sensor style vibration: taps get faster and stronger as the obstacle ahead gets closer.
enum HapticPlan {
    static func pulse(forDistance distance: Float?) -> HapticPulse? {
        guard let distance else { return nil }
        for band in Tuning.hapticBands where distance < band.distance {
            return HapticPulse(interval: band.interval, intensity: band.intensity)
        }
        return nil
    }
}
