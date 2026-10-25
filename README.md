# Cane Guide

An iPhone app that mounts on a white cane, uses the LiDAR depth sensor to find obstacles ahead, and guides the user by voice and vibration. It can also give walking directions with Apple Maps.

**It supplements the cane. It does not replace it.** It cannot detect stairs going down, drop-offs, or glass reliably.

## What you need

- An iPhone with LiDAR: iPhone 12 Pro or newer **Pro** model.
- A Mac running a recent macOS with **Xcode 16 or newer** (free from the Mac App Store).
- A USB cable for the phone.
- A free Apple ID. No paid developer account and no App Store.

## Put it on the phone (about 10 minutes)

1. Open `CaneGuide.xcodeproj` in Xcode.
2. Click the blue **CaneGuide** project at the top left, then **Signing & Capabilities**.
   - **Team:** choose your Apple ID. If none is listed, use *Add an Account…*
   - **Bundle Identifier:** change `com.example.caneguide` to something unique, such as `com.yourname.caneguide`.
3. Plug in the iPhone and unlock it. Tap **Trust** if it asks.
4. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode** and restart when asked.
5. In Xcode, pick the iPhone in the device menu at the top and press **Run** (▶).
6. The first time, the iPhone blocks the app. Go to **Settings → General → VPN & Device Management**, tap your Apple ID, and tap **Trust**. Then press Run again.
7. Allow camera, location and motion access when the app asks.

An app installed with a free Apple ID stops opening after 7 days. Press Run again to reinstall it.

## Using it

- Mount the phone on the cane at about chest height with the **back camera facing forward** and the screen facing you. A bike phone holder and zip ties work.
- Tap **Start**. You'll hear "Cane Guide on."
- Spoken cues: "Path clear", "Obstacle ahead. Go left/right", "Stop. Obstacle 0.8 meters ahead", "Stop. Path blocked", and "Person ahead, 2.0 meters."
- Vibration gets faster and stronger as an obstacle gets closer (under 3 m).
- For directions: tap **Ask for directions** and say something like "take me to the library." It stops listening when you pause, finds a walking route, draws it on the map, and reads out each turn. You can also type a place and tap **Go**.
- Turn on **Show distances** to see the left, ahead and right readings while tuning.

## Gemini for spoken requests (optional)

Get a free key at https://aistudio.google.com/apikey and paste it into `geminiAPIKey` in `CaneGuide/App/Config.swift`. Gemini turns what you said into a place to search for, then Apple Maps finds the walking route. Without a key, or if Gemini fails, the app sends what it heard straight to Apple Maps search. Speech recognition itself is Apple's and runs on the phone. Only the transcript of your request goes to Google, not audio or location.

## Optional ElevenLabs voice for directions

Paste an API key into `CaneGuide/App/Config.swift`. Obstacle warnings always use the built-in voice because it's instant and works offline. If ElevenLabs fails, directions fall back to the built-in voice.

## Tuning after a test walk

All distances and timings live in `CaneGuide/Core/Tuning.swift`. Common changes:

- Too many false "stop"s from the floor: raise `floorClearance` or `defaultCameraHeight`.
- The cane itself triggers warnings: raise `minForward`.
- Warnings come too late: raise `stopDistance` and `veerDistance`.
- Too chatty: raise `minAnnounceInterval`.

## How it works

```
LiDAR depth (15 Hz) ─┐
ARKit camera pose  ──┼─> ObstacleAnalyzer ─> GuidanceEngine ─> voice + vibration
Gyroscope ───────────┘   (left/ahead/right     (stop / go left /
                          nearest distance)     go right / clear)
Your voice ─> Apple speech ─> Gemini ─> place name
GPS + Apple Maps ───> RoutePlanner ───> map on screen + voice (ElevenLabs or built-in)
```

- Each depth pixel is projected into gravity-aligned 3D space. Points near the floor are ignored, and the rest are sorted into left, ahead and right zones of a 2 m wide corridor.
- Zones follow the averaged walking direction, so sweeping the cane scans across them instead of rotating them.
- Within a zone, the nearest *cluster* of depth points wins, so a thin pole in front of a far wall is still caught while stray noisy pixels are ignored.
- Gap-seeking (inspired by [Shepherd](https://github.com/tonywangs/shepherd)): the corridor is split into 7 thin strips, and "go left/right" points toward the clearest opening wide enough to walk through, averaged over a few frames.
- Apple Vision looks for people a few times a second; LiDAR measures how far away they are.
- Raw LiDAR depth at 30 Hz. ARKit's smoothed depth blends frames together, which smears obstacles while the cane sweeps.
- A cue has to hold for two frames before it counts. Warnings have hysteresis and rate limits so the app doesn't chatter.
- Obstacle warnings always interrupt directions.

## Folders

| Folder | What's in it |
|---|---|
| `CaneGuide/Core` | Pure logic: obstacle detection, guidance rules, haptic timing, tuning. No iPhone frameworks, so it can be tested on any Mac. |
| `CaneGuide/Sensing` | LiDAR depth (ARKit) and gyroscope (CoreMotion). |
| `CaneGuide/Output` | Voice and vibration. |
| `CaneGuide/Navigation` | Apple Maps walking routes and the ElevenLabs voice. |
| `CaneGuide/App` | App entry point, screen, and wiring. |
| `Checks` | Logic tests for `Core`. |

## Logic tests (no Xcode needed)

```
./run-checks.sh
```

This compiles `CaneGuide/Core` with the Mac's Swift compiler and runs 52 checks on simulated depth frames and guidance sequences.

## Safety for testing

Test only with a sighted spotter walking beside the user. Start indoors, in a hallway with known obstacles, before trying outside.
