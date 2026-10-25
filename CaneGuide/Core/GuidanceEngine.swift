import Foundation

/// Decides what to tell the person, and when, from a stream of zone observations.
///
/// Zones are remembered briefly because a sweeping cane only sees part of the
/// corridor in each frame. Cues must hold for a couple of frames before they
/// count, and announcements are rate limited so the app doesn't chatter.
struct GuidanceEngine {
    private struct Memory {
        var observation: ZoneObservation
        var time: TimeInterval
    }

    private var memory: [Zone: Memory] = [:]
    private(set) var cue: Cue = .unreliable
    private var candidate: Cue = .unreliable
    private var candidateCount = 0
    private var lastAnnounced: Cue?
    private var lastAnnounceTime: TimeInterval = -.infinity
    private var unreliableSince: TimeInterval?
    private var gapHistory: [Float] = []
    private var lastPersonAlert: TimeInterval = -.infinity

    /// Missing key: zone not seen recently. nil value: seen and clear.
    var zoneDistances: [Zone: Float?] { memory.mapValues { $0.observation.distance } }
    var nearestAhead: Float? { memory[.center]?.observation.distance }

    /// Feed one frame (nil when the frame couldn't be trusted). Returns a cue to speak, if any.
    mutating func update(_ result: AnalysisResult?, now: TimeInterval) -> Cue? {
        if let result {
            for (zone, observation) in result.zones {
                memory[zone] = Memory(observation: observation, time: now)
            }
            if let gap = result.gapOffset {
                gapHistory.append(gap)
                if gapHistory.count > Tuning.gapHistory { gapHistory.removeFirst() }
            }
        }
        memory = memory.filter { now - $0.value.time <= Tuning.zoneMemory }

        let raw = rawCue()
        if raw == candidate {
            candidateCount += 1
        } else {
            candidate = raw
            candidateCount = 1
        }
        if candidateCount >= Tuning.cueConfirmFrames { cue = candidate }

        if cue == .unreliable {
            if unreliableSince == nil { unreliableSince = now }
        } else {
            unreliableSince = nil
        }
        return announcement(now: now)
    }

    /// Returns the distance to announce for a person ahead, at most every `personRepeatInterval`.
    /// Stays quiet during stop warnings, which matter more.
    mutating func personAlert(_ distance: Float?, now: TimeInterval) -> Float? {
        guard let distance, !cue.isStop, now - lastPersonAlert >= Tuning.personRepeatInterval else { return nil }
        lastPersonAlert = now
        return distance
    }

    private func rawCue() -> Cue {
        guard let center = memory[.center] else { return .unreliable }
        let ahead = center.observation.distance ?? .infinity
        let left = sideDistance(.left)
        let right = sideDistance(.right)

        let stopLimit = Tuning.stopDistance + (cue.isStop ? Tuning.hysteresis : 0)
        let veerLimit = Tuning.veerDistance + (cue.isObstacle ? Tuning.hysteresis : 0)
        let sidesBlocked = left < Tuning.veerDistance && right < Tuning.veerDistance

        if ahead < stopLimit { return sidesBlocked ? .blocked : .stop }
        if ahead < veerLimit {
            if sidesBlocked { return .blocked }
            // Head for the clearest opening, sticking with the current side until the gap clearly moves.
            if !gapHistory.isEmpty {
                let gap = gapHistory.reduce(0, +) / Float(gapHistory.count)
                if cue == .veerLeft && gap < Tuning.gapSwitch { return .veerLeft }
                if cue == .veerRight && gap > -Tuning.gapSwitch { return .veerRight }
                if abs(gap) >= Tuning.gapDeadband { return gap < 0 ? .veerLeft : .veerRight }
            }
            // No clear gap: stick with the current side unless the other is clearly freer.
            if cue == .veerLeft && right <= left + Tuning.veerSwitchMargin { return .veerLeft }
            if cue == .veerRight && left <= right + Tuning.veerSwitchMargin { return .veerRight }
            return left >= right ? .veerLeft : .veerRight
        }
        return .clear
    }

    /// A side never seen recently is treated as neither blocked nor clear.
    private func sideDistance(_ zone: Zone) -> Float {
        guard let entry = memory[zone] else { return Tuning.veerDistance }
        return entry.observation.distance ?? .infinity
    }

    private mutating func announcement(now: TimeInterval) -> Cue? {
        let sinceLast = now - lastAnnounceTime
        let shouldSay: Bool
        if cue != lastAnnounced {
            switch cue {
            case .stop, .blocked:
                shouldSay = true
            case .unreliable:
                shouldSay = now - (unreliableSince ?? now) >= Tuning.unreliableGrace
            case .clear, .veerLeft, .veerRight:
                shouldSay = sinceLast >= Tuning.minAnnounceInterval
            }
        } else {
            switch cue {
            case .stop, .blocked: shouldSay = sinceLast >= Tuning.repeatStopInterval
            case .unreliable: shouldSay = sinceLast >= Tuning.repeatUnreliableInterval
            case .clear, .veerLeft, .veerRight: shouldSay = false
            }
        }
        guard shouldSay else { return nil }
        lastAnnounced = cue
        lastAnnounceTime = now
        return cue
    }
}
