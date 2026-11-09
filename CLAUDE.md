# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**Noori** — a lightweight native macOS app that turns the MacBook notch into an iPhone-style island. Core features only: **media** (now playing, controls, visualizer, synced lyrics under the closed notch), **live activities** (music, charging, Focus, screen recording, privacy indicators, caps lock), **devices** (Bluetooth/AirPods HUD), **controls** (custom volume/brightness/keyboard-backlight HUDs), **battery**, and **keyboard shortcuts**.

Removed on purpose to keep the app light (see commits after `f96db6e`): Terminal, Downloads, Color Picker, Clipboard, Notes, Screen Assistant, LLM Usage, Webcam Mirror, Stats, Lock Screen widgets, Calendar/Reminders, Timer, Shelf, and Atoll's extension system. The full pre-removal code is on the `extensions-source` branch for reference. Don't re-add these without the owner asking.

- Noori is a fork of **Atoll** 2.3.3 (`Ebullioscopic/Atoll`), which derives from **boring.notch**. GPL-3.0. Repo: `wenujacodes/Noori`. Owner: Wenuja Liyanamana.
- Language: Swift / SwiftUI + AppKit (no C++, Obj-C++ or Metal code).
- Size: ~160 Swift files, ~42k lines.
- Version: `VERSION` file and `MARKETING_VERSION` in the project (currently 1.0.0).

### Rules for this repo

- **Do not edit `ReadMe.md`** unless the owner explicitly asks.
- **Ask before deleting or removing any major part** (folders, features, packages, assets). Renames/refactors that keep behavior are fine.
- **License attribution must stay.** File headers keep the "Based on Atoll … Atoll Contributors" and boring.notch lines; keep `LICENSE` and `NOTICE`. New files use the header:
  ```
  /*
   * Noori
   * Copyright (C) 2026 Wenuja Liyanamana
   *
   * This program is free software: you can redistribute it and/or modify
   * it under the terms of the GNU General Public License as published by
   * the Free Software Foundation, either version 3 of the License, or
   * (at your option) any later version.
   */
  ```
- Never reintroduce Atoll's signing team (`9Y64TRM77N`), Sparkle key, or bundle IDs.

## Building

Requirements: macOS 14+, Xcode with **Swift 6.1+**. The Metal Toolchain is no longer needed (the app and its packages have no `.metal` files).

Open in Xcode: `open Noori.xcodeproj`, scheme **Noori**, run on My Mac. `DEVELOPMENT_TEAM` is empty: pick your own team (a free Personal Team works) under Signing & Capabilities to run a signed build.

Command-line build (no signing identity needed):

```bash
xcodebuild build \
  -project Noori.xcodeproj \
  -scheme Noori \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```

- No root Swift package; dependencies are SPM packages referenced from `Noori.xcodeproj` (resolve with `xcodebuild -resolvePackageDependencies -project Noori.xcodeproj -scheme Noori`).
- Product is `Noori.app`. Debug bundle id `com.wenujacodes.Noori.dev`; Release `com.wenujacodes.Noori`. Both use the `AppIcon` set, which is currently empty (macOS shows its default app icon until a Noori icon is added).
- Prebuilt `Frameworks/MediaRemoteAdapter.framework` (source: `mediaremote-adapter/`) provides Now Playing info; `Contents/Helpers/NowPlayingTestClient` is copied into the app and used by `MediaChecker.swift`.
- No bridging header (removed with the C++ audio bridge).
- Swift language mode is 5.0 (`SWIFT_VERSION = 5.0`) even though the toolchain must be 6.1+.

### Tests

- `python3 -m unittest tests.test_privacy_configuration` — static checks on the Apple Events entitlement/usage string in `project.pbxproj` (exact strings/counts). Run after touching entitlements or `INFOPLIST_KEY_*UsageDescription` settings.
- Remaining permissions: Apple Events (Spotify, Music), Bluetooth, Accessibility (HUD key interception). Camera, calendar, reminders, location, screen capture, audio capture and folder permissions were removed with their features.
- `NooriUITests/` exists but isn't run automatically (the notch UI can't be driven headlessly).

## Project layout

All app code lives in `Noori/`. The Xcode project uses **synchronized folder groups**: new files in `Noori/` are picked up automatically — no `project.pbxproj` edits needed to add a file.

| Path | Purpose |
|---|---|
| `NooriApp.swift` | `@main NooriApp` (menu bar extra, Sparkle updater) and `AppDelegate` (window per screen, startup wiring, Defaults migrations). |
| `ContentView.swift` | Main notch view (~3k lines); most notch UI routes through here. |
| `NooriViewCoordinator.swift` | Shared coordinator: current tab/view, sneak-peek/HUD state. |
| `models/` | View models (`NooriViewModel`, `BatteryStatusViewModel`) and **`Constants.swift` = almost all `Defaults.Keys` settings (~350)**. |
| `managers/` | Singleton managers: `MusicManager`, `SystemHUDManager`/`SystemDisplayManager` (HUDs), `BluetoothAudioManager`, `BatteryActivityManager`, `DoNotDisturbManager`, `PrivacyIndicatorManager`, `ScreenRecordingManager`, `LockScreenManager` (only tracks locked/unlocked state). |
| `components/` | SwiftUI views by feature (`Notch/`, `Music/`, `Live activities/`, `OSD/`, `Focus/`, `Privacy/`, `Recording/`, `Settings/`, …). There is no onboarding window; first-run setup is `applyDefaultSetup()` in `NooriApp.swift`. The notch has a single Home view and only the compact (former "minimalistic") layout; there is no wide layout or tab bar. Settings, Restart and Quit are in the notch's right-click menu and in the menu bar icon's right-click menu (`managers/MenuBarController.swift`; left-click opens the notch; "Show menu bar icon" setting). |
| `MediaControllers/` | Per-player controllers behind `MediaControllerProtocol` (Apple Music, Spotify, YouTube Music, Amazon Music, Now Playing). |
| `helpers/`, `extensions/`, `utils/`, `private/` | AppleScript runner, permission stores, private display/brightness APIs (`CGSSpace`, DisplayServices, CoreBrightness), SMC/IOReport. |
| `lyrics/` | Notch lyrics, based on Lyrimuse (`Yudaotor/lyrimuse`, GPL-3.0; credited in `NOTICE` and the README): `LyricsManager` follows the current song, asks the enabled sources (LRCLIB, NetEase, QQ) at once (`LyricsSources`), picks word timing first, keeps results in memory only (never on disk, by the owner's choice) and applies the display settings (Chinese script, pronunciation via `LyricsPronunciation`, translation). `LyricsParsing` has the LRC/YRC parsers. Translation: NetEase's Chinese `tlyric`, else Apple's Translation framework (macOS 15+, weak-linked) run by the invisible `LyricsTranslationHost` in `ContentView`; it never starts a language download from the notch (Settings › Lyrics has the button). Settings types in `LyricsSettings.swift`, keys `lyrics…` in `Constants.swift`, page in `components/Settings/LyricsSettingsView.swift`. Shown by `components/Notch/NotchLyricLine.swift` under the closed notch (`showLyrics`; the player's lyrics button toggles it). Only the notch lyrics were taken from Lyrimuse: none of its name, icons, onboarding, telemetry, launch at login, floating/menu bar lyrics, Last.fm or Discord. |
| `audio/`, `components/Music/` | Music visualizer: `AudioVisualizerView` shows the animated bars from `MusicVisualizer.swift` (no real-time audio capture). |
| `Localizable.xcstrings` | The string catalog the app builds (in `Noori/`). The root-level `Localizable.xcstrings` is **not** in the build; it's kept for its extra languages. |
| `components/Settings/` | The Settings window: `SettingsView.swift` has the sidebar, tabs, search and highlight; each page is its own file in `Pages/` (`GeneralSettings`, `AppearanceSettings`, `MediaSettings`, `LiveActivitiesSettings`, `DevicesSettings`, `ControlsSettings`, `BatterySettings`, `ShortcutsSettings`, `AboutSettings`, shared bits in `SettingsComponents`); Lyrics is `LyricsSettingsView.swift`. A new page needs a `SettingsTab` case and an entry in the sidebar's `ordered` list. |
| `NooriSamples/` | Screenshots (not part of the app; they show the old Atoll UI). |

## Conventions

- Settings: add a key to `extension Defaults.Keys` in `models/Constants.swift`; read with `@Default(.key)` in views or `Defaults[.key]` in code. Renaming/retyping a key needs a migration (see `Defaults.Keys.migrate…()` in `applicationDidFinishLaunching`).
- Animations: use the shared motions in `animations/NooriMotion.swift` (`notchOpen`/`notchClose`, `notchContent`, `hover`, `appear`, `change`, `gesture`) instead of one-off timings. Decorative loops (pulses, glows) and button press effects keep their own.
- Managers are `ObservableObject` singletons (`.shared`) using Combine; UI work on the main actor.
- Uses private/undocumented macOS APIs (SkyLight windows for lock screen, MediaRemote, DisplayServices, SMC/IOReport). Guard with availability checks; expect breakage across macOS versions.
- Spotify / Music / Notes control goes through AppleScript — keep those bundle ids in the `temporary-exception.apple-events` entitlement.
- A new permission needs an entitlement and an `INFOPLIST_KEY_…UsageDescription` in **both** Debug and Release configs (the privacy test counts them).
- New user-facing strings go in `Noori/Localizable.xcstrings`.
- Log changes under `## [Unreleased]` in `CHANGELOG.md`.

## Updates / release

- Sparkle is integrated with a single stable feed. Noori's repo is **private**, so updates are served from the **public** repo `wenujacodes/Noori-releases` (local checkout `../Noori-releases`): `SUFeedURL` in `Noori/Info.plist` points to its `appcast.xml` on `main` (raw.githubusercontent.com) and the release zips are its GitHub releases. `Updates/appcast.xml` in this repo is the master copy. `SUPublicEDKey` is Noori's own EdDSA key; the private key is in the owner's login Keychain under the account **Noori** (`generate_keys --account Noori`). Never sign with another key.
- Releasing: move the `## [Unreleased]` notes in `CHANGELOG.md` under `## [<version>] - <date>`, then `scripts/release.sh <version> --publish`: sets the version and the next build number (newest build in the appcast + 1; `BUILD=<n>` overrides), builds a universal, stripped Release (Apple Silicon + Intel; it refuses to ship if either is missing; the symbols go to `dist/Noori-<version>.app.dSYM` for reading crash reports), zips to `dist/`, signs it and adds it to `Updates/appcast.xml`, creates the release `v<version>` in `Noori-releases` with that version's changelog notes, then pushes the appcast there. Then commit and push the version bump, `Updates/appcast.xml` and the changelog here.
- There's no Developer ID certificate yet, so builds are ad-hoc signed (or `SIGN_IDENTITY=...`) and not notarized: users get the "unidentified developer" prompt on first install.
- No CI/release workflows yet (Atoll's were removed).

## Knowledge graph (graphify)

A code knowledge graph is in `graphify-out/` (gitignored), built with local AST extraction only (`graphify extract . --code-only`). Hubs: `Defaults`, `ContentView`, `NooriViewModel`, `MusicManager`, `BluetoothAudioManager`, `SettingsView`.

```bash
graphify query "how does the music player get now-playing info"
graphify explain "MusicManager"
graphify path "ContentView" "MusicManager"
graphify affected "NooriViewModel"   # what breaks if this changes
graphify update .                    # refresh after code changes (no API cost)
```

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- When graphify-out/graph.json exists, run `graphify query "<question>"` before your first grep, search or source-file read for a codebase question, and put this rule in every subagent prompt that explores code. Read raw files only for lines the graph or an earlier read already located. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- A committed graphify-out/graph.json is rewritten whole on every build, so a large diff to it in a pull request is expected. Do not flag it as churn or suggest skipping the graph rebuild or its hooks.
