import MapKit
import SwiftUI

/// Big Start/Stop and Ask buttons, a large status word, and a map with the walking route.
/// High contrast and VoiceOver labelled; everything important is also spoken.
struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 14) {
            Text(model.cue?.label ?? (model.isRunning ? "STARTING" : "CANE GUIDE"))
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(.yellow)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(model.cue?.phrase ?? "Cane Guide")

            if !model.lidarSupported {
                Text("This iPhone has no LiDAR sensor. Cane Guide needs an iPhone 12 Pro or newer Pro model.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
            }

            Button(action: { model.toggle() }) {
                Text(model.isRunning ? "Stop" : "Start")
                    .font(.system(size: 48, weight: .heavy))
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .background(model.isRunning ? Color.red : Color.green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .disabled(!model.lidarSupported)
            .accessibilityHint(model.isRunning ? "Stops obstacle guidance" : "Starts obstacle guidance")

            Button(action: { model.ask() }) {
                Label(model.isListening ? "Listening…" : "Ask for directions",
                      systemImage: model.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .background(model.isListening ? Color.orange : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .accessibilityHint("Say where you want to go, for example: take me to the library.")

            if !model.navigationStatus.isEmpty {
                Text(model.navigationStatus)
                    .font(.title3)
                    .multilineTextAlignment(.center)
            }

            Map(position: $model.mapPosition) {
                UserAnnotation()
                if let route = model.route {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 6)
                    if let end = route.polyline.endCoordinate {
                        Marker("Destination", systemImage: "flag.fill", coordinate: end)
                            .tint(.red)
                    }
                }
            }
            .mapControls { MapUserLocationButton() }
            .frame(minHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel(model.route == nil ? "Map of your location" : "Map showing your walking route")

            HStack {
                TextField("Or type a place", text: $model.destination)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .submitLabel(.go)
                    .onSubmit { model.navigate() }
                    .accessibilityLabel("Destination")
                Button("Go") { model.navigate() }
                    .font(.title3.bold())
                    .disabled(model.destination.isEmpty)
            }

            Toggle("Show distances", isOn: $model.showDistances)
                .font(.body)

            if model.showDistances {
                HStack {
                    ForEach(Zone.allCases, id: \.self) { zone in
                        VStack {
                            Text(name(zone)).font(.headline)
                            Text(distanceText(zone)).font(.title2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding()
        .foregroundStyle(.white)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func name(_ zone: Zone) -> String {
        switch zone {
        case .left: return "Left"
        case .center: return "Ahead"
        case .right: return "Right"
        }
    }

    private func distanceText(_ zone: Zone) -> String {
        switch model.zones[zone] {
        case .none: return "–"
        case .some(.none): return "clear"
        case .some(.some(let meters)): return String(format: "%.1f m", meters)
        }
    }
}

private extension MKPolyline {
    var endCoordinate: CLLocationCoordinate2D? {
        guard pointCount > 0 else { return nil }
        return points()[pointCount - 1].coordinate
    }
}
