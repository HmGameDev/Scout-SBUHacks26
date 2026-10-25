import CoreHaptics

/// Repeating taps whose speed and strength follow HapticPlan.
final class Haptics {
    private var engine: CHHapticEngine?
    private var timer: Timer?
    private var current: HapticPulse?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else { return }
        engine.resetHandler = { [weak engine] in try? engine?.start() }
        try? engine.start()
        self.engine = engine
    }

    /// Call from the main thread with the distance to the nearest obstacle ahead.
    func update(distance: Float?) {
        let pulse = HapticPlan.pulse(forDistance: distance)
        guard pulse != current else { return }
        current = pulse
        timer?.invalidate()
        timer = nil
        guard let pulse else { return }
        tap(pulse.intensity)
        timer = Timer.scheduledTimer(withTimeInterval: pulse.interval, repeats: true) { [weak self] _ in
            self?.tap(pulse.intensity)
        }
    }

    func stop() {
        update(distance: nil)
    }

    private func tap(_ intensity: Float) {
        guard let engine else { return }
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
        ], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern) else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
    }
}
