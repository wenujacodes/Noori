# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**Noori** — a native macOS app that turns the MacBook notch into an iPhone-style island: media controls, Live Activities, lock screen widgets, system HUDs (volume/brightness/Bluetooth), system stats, timers, clipboard, color picker, shelf (file drop), terminal tab, AI screen assistant, LLM usage tracking, and an opt-in third-party extension API.

- Noori is a fork of **Atoll** 2.3.3 (`Ebullioscopic/Atoll`), which derives from **boring.notch**. GPL-3.0. Repo: `wenujacodes/Noori`. Owner: Wenuja Liyanamana.
- Language: Swift / SwiftUI + AppKit, with a small C++/Obj-C++ audio layer (`Noori/audio/`) and one Metal shader (`Noori/metal/visualizer.metal`).
- Size: ~320 Swift files, ~100k lines.
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

Requirements: macOS 14+, Xcode with **Swift 6.1+**, and on Xcode 26+ the downloadable **Metal Toolchain** (`xcodebuild -downloadComponent MetalToolchain`, installed by Xcode into its own system location — no path to choose). Without it the build fails at the first `.metal` file (SwiftTerm's shaders or `visualizer.metal`).

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
- Product is `Noori.app`. Debug bundle id `com.wenujacodes.Noori.dev` (icon `AppIconDev`); Release `com.wenujacodes.Noori`.
- **Entitlements gotcha:** `Noori/Noori.entitlements` declares `com.apple.security.mach-services` (`com.wenujacodes.Noori.xpc`). With ad-hoc signing amfid kills the app at launch; remove that key locally (`plutil -remove com.apple.security.mach-services Noori/Noori.entitlements`) to run an ad-hoc build, but don't commit that.
- Prebuilt `Frameworks/MediaRemoteAdapter.framework` (source: `mediaremote-adapter/`) provides Now Playing info; `Contents/Helpers/NowPlayingTestClient` is copied into the app and used by `MediaChecker.swift`.
- Bridging header: `Noori/Noori-Bridging-Header.h` (exposes `audio/AudioBridge.h`).
- Swift language mode is 5.0 (`SWIFT_VERSION = 5.0`) even though the toolchain must be 6.1+.

### Tests

- `python3 -m unittest tests.test_privacy_configuration` — static checks on entitlements and the privacy usage strings in `project.pbxproj` (exact strings/counts). Run after touching entitlements or `INFOPLIST_KEY_*UsageDescription` settings.
- `NooriUITests/` exists but isn't run automatically (the notch UI can't be driven headlessly).

## Project layout

All app code lives in `Noori/`. The Xcode project uses **synchronized folder groups**: new files in `Noori/` are picked up automatically — no `project.pbxproj` edits needed to add a file.

| Path | Purpose |
|---|---|
| `NooriApp.swift` | `@main NooriApp` (menu bar extra, Sparkle updater) and `AppDelegate` (window per screen, startup wiring, Defaults migrations). |
| `ContentView.swift` | Main notch view (~3k lines); most notch UI routes through here. |
| `NooriViewCoordinator.swift` | Shared coordinator: current tab/view, sneak-peek/HUD state. |
| `models/` | View models (`NooriViewModel`, `BatteryStatusViewModel`) and **`Constants.swift` = almost all `Defaults.Keys` settings (~350)**. |
| `managers/` | Singleton feature managers (`MusicManager`, `StatsManager`, `LockScreenManager`, `SystemHUDManager`, `TimerManager`, `ClipboardManager`, …). `LLMUsage/` = LLM usage tracking; `Extensions/` = extension host. |
| `components/` | SwiftUI views by feature (`Notch/`, `Music/`, `LockScreen/`, `Settings/`, `Shelf/`, `Stats/`, `Timer/`, `Live activities/`, `OSD/`, `Onboarding/`, …). |
| `MediaControllers/` | Per-player controllers behind `MediaControllerProtocol` (Apple Music, Spotify, YouTube Music, Amazon Music, Now Playing). |
| `services/Extensions/` | XPC + RPC servers for third-party extensions. |
| `helpers/`, `extensions/`, `utils/`, `private/` | AppleScript runner, permission stores, private display/brightness APIs (`CGSSpace`, DisplayServices, CoreBrightness), SMC/IOReport. |
| `audio/`, `metal/` | Real-time audio tap + FFT visualizer (C++ via Obj-C++ bridge) and Metal shader. |
| `Localizable.xcstrings` | The string catalog the app builds (in `Noori/`). The root-level `Localizable.xcstrings` is **not** in the build; it's kept for its extra languages. |
| `LottieAnimations/`, `BluetoothHUDAnimations/` | Animation assets (`.mov` files are Git LFS). |
| `NooriSamples/` | Screenshots (not part of the app). |

## Conventions

- Settings: add a key to `extension Defaults.Keys` in `models/Constants.swift`; read with `@Default(.key)` in views or `Defaults[.key]` in code. Renaming/retyping a key needs a migration (see `Defaults.Keys.migrate…()` in `applicationDidFinishLaunching`).
- Managers are `ObservableObject` singletons (`.shared`) using Combine; UI work on the main actor.
- Uses private/undocumented macOS APIs (SkyLight windows for lock screen, MediaRemote, DisplayServices, SMC/IOReport). Guard with availability checks; expect breakage across macOS versions.
- Spotify / Music / Notes control goes through AppleScript — keep those bundle ids in the `temporary-exception.apple-events` entitlement.
- A new permission needs an entitlement and an `INFOPLIST_KEY_…UsageDescription` in **both** Debug and Release configs (the privacy test counts them).
- New user-facing strings go in `Noori/Localizable.xcstrings`.
- Log changes under `## [Unreleased]` in `CHANGELOG.md`.

### Extensions (AtollExtensionKit)

The extension system depends on the external SPM package **`AtollExtensionKit`** (owned by Atoll's author). Its type names (`AtollLiveActivityDescriptor`, `AtollXPCServiceProtocol`, …) can't be renamed without forking the package — leave them. Extensions are **off by default** (`enableThirdPartyExtensions = false`) and each app must be approved by the user. Note: the published kit connects to Atoll's bundle id/XPC name, so third-party extensions will only reach Noori once a Noori fork of the kit exists.

## Updates / release

- Sparkle is still integrated. Feeds point to `https://raw.githubusercontent.com/wenujacodes/Noori/main/Updates/appcast*.xml` (don't exist yet). Atoll's `SUPublicEDKey` was removed; before shipping updates, generate your own EdDSA key with Sparkle's `generate_keys` and add `SUPublicEDKey` to `Noori/Info.plist`.
- No CI/release workflows yet (Atoll's were removed).
- `ModelPricingManager` fetches `pricing.json` from `wenujacodes/Noori` main; it falls back to the bundled copy.

## Knowledge graph (graphify)

A code knowledge graph is in `graphify-out/` (gitignored), built with local AST extraction only (`graphify extract . --code-only`). Hubs: `Defaults`, `ContentView`, `NooriViewModel`, `MusicManager`, `StatsManager`, `BluetoothAudioManager`, `LockScreen*` managers.

```bash
graphify query "how does the music player get now-playing info"
graphify explain "MusicManager"
graphify path "ContentView" "StatsManager"
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
