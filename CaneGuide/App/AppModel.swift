import AudioToolbox
import MapKit
import SwiftUI
import UIKit

/// Wires the sensors, guidance logic, voice, haptics and navigation together.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isListening = false
    @Published private(set) var cue: Cue?
    @Published private(set) var zones: [Zone: Float?] = [:]
    @Published private(set) var navigationStatus = ""
    @Published private(set) var route: MKRoute?
    @Published var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @Published var destination = ""
    @Published var showDistances = false

    let lidarSupported = DepthSensor.isSupported

    private let sensor = DepthSensor()
    private let motion = MotionMonitor()
    private let haptics = Haptics()
    private let planner = RoutePlanner()
    private let listener = SpeechListener()
    private let assistant = GeminiAssistant(apiKey: Config.geminiAPIKey, model: Config.geminiModel)
    private let announcer = Announcer(cloudVoice: ElevenLabsVoice(apiKey: Config.elevenLabsAPIKey,
                                                                  voiceID: Config.elevenLabsVoiceID))

    init() {
        planner.onInstruction = { [weak self] text in self?.announcer.direct(text) }
        planner.onStatus = { [weak self] text in self?.navigationStatus = text }
        planner.onRoute = { [weak self] route in
            self?.route = route
            self?.mapPosition = route == nil ? .userLocation(fallback: .automatic) : .automatic
        }
        sensor.onError = { [weak self] message in
            Task { @MainActor in self?.announcer.warn("Camera error. \(message)", interrupt: true) }
        }
        planner.requestPermission()
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard lidarSupported, !isRunning else { return }
        // A fresh pipeline per run; it lives on the depth queue from here on.
        let pipeline = GuidancePipeline()
        let motion = motion
        sensor.onFrame = { [weak self] frame in
            let output = pipeline.process(frame.depth, floorY: frame.floorY, trackingOK: frame.trackingOK,
                                          movingTooFast: motion.isMovingTooFast, people: frame.people,
                                          timestamp: frame.timestamp)
            Task { @MainActor in self?.apply(output) }
        }
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        motion.start()
        sensor.start()
        announcer.warn("Cane Guide on. Keep using your cane. It cannot detect stairs going down.", interrupt: true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        sensor.stop()
        motion.stop()
        haptics.stop()
        planner.stopNavigation()
        UIApplication.shared.isIdleTimerDisabled = false
        cue = nil
        zones = [:]
        navigationStatus = ""
        announcer.warn("Cane Guide off.", interrupt: true)
    }

    /// Tap once to speak a request ("take me to the library"); it stops listening when you pause.
    func ask() {
        if listener.isListening {
            listener.finish()
            return
        }
        SpeechListener.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.announcer.warn("Turn on microphone and speech recognition for Cane Guide in Settings.", interrupt: true)
                return
            }
            self.announcer.hush()
            AudioServicesPlaySystemSound(1113) // "begin recording" tone
            self.isListening = true
            self.navigationStatus = "Listening…"
            self.listener.listen { [weak self] heard in
                guard let self else { return }
                self.isListening = false
                AudioServicesPlaySystemSound(1114) // "end recording" tone
                guard let heard else {
                    self.navigationStatus = ""
                    self.announcer.direct("I didn't hear anything.")
                    return
                }
                self.navigationStatus = "“\(heard)”"
                Task { await self.handle(heard) }
            }
        }
    }

    func navigate() {
        let query = destination
        Task { await planner.navigate(to: query) }
    }

    private func handle(_ heard: String) async {
        var query = heard
        if let assistant {
            do {
                let answer = try await assistant.interpret(heard)
                announcer.direct(answer.reply)
                query = answer.destination
            } catch {
                // Gemini unavailable: treat what was heard as the place to search for.
            }
        }
        guard !query.isEmpty else {
            navigationStatus = ""
            return
        }
        destination = query
        await planner.navigate(to: query)
    }

    private func apply(_ output: PipelineOutput) {
        guard isRunning else { return }
        cue = output.cue
        zones = output.zones
        haptics.update(distance: output.cue == .unreliable ? nil : output.nearestAhead)
        if let said = output.announce {
            announcer.warn(said.phrase(distance: output.nearestAhead), interrupt: said.isObstacle)
        }
        if let person = output.personAhead {
            announcer.warn("Person ahead, \(Cue.spoken(person)).", interrupt: false)
        }
    }
}
