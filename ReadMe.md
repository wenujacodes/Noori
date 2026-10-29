<h1 align="center">Noori for macOS</h1>

Noori turns the MacBook notch into a lightweight, focused surface for media, live activities, and system controls. It stays out of the way until needed, then expands with responsive, native SwiftUI animations.

## Highlights
- Media controls for Apple Music, Spotify, Cider, and more, with lyrics, a live audio visualizer, and animated album art.
- Live Activities for media playback, battery and charging, Focus, screen recording, privacy indicators, and Caps Lock.
- Device HUDs for Bluetooth headphones and AirPods, including battery levels.
- Custom volume, brightness, and keyboard backlight HUDs that replace the system ones.
- Battery status and notifications right in the notch.
- Customization for layouts, animations, hover behavior, and keyboard shortcuts.

## Other Features
- Gesture controls for opening/closing the notch and media navigation.
- Parallax hover interactions with smooth transitions.

<p align="center">
  <img src="https://i.postimg.cc/HkLGn6yH/846F86A4_A2F9_4CD6_BC84_1D720D377728_1_201_a.jpg" alt="Noori preview" width="920">
</p>

## Requirements
- macOS 14.0 or later (optimised for macOS 15+).
- MacBook with a notch (14/16‑inch MBP across Apple silicon generations).
- Xcode 16.3+ (Swift 6.1+) to build from source. On Xcode 26 or later, also install the Metal Toolchain (Xcode → Settings → Components).
- Permissions as needed: Accessibility (custom HUDs), Bluetooth (device HUDs), Automation (Spotify and Apple Music control), and Audio Capture (music visualizer).

## Installation
1) Download the latest DMG [here](https://github.com/wenujacodes/Noori/releases/latest).
2) Open the DMG and drag Noori into Applications.
3) Launch Noori and grant the requested permissions.

## License
Noori is released under the GPL v3 License. Refer to [LICENSE](LICENSE) for the full terms.

## Acknowledgments

Noori builds upon the work of several open-source projects and draws inspiration from innovative macOS applications:

- [**Atoll**](https://github.com/Ebullioscopic/Atoll) - the project Noori is forked from. Noori's codebase, features, and design come from Atoll by [Ebullioscopic](https://github.com/Ebullioscopic) and the Atoll contributors.

- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) - foundational codebase that provided the initial media player integration. Major architectural patterns and notch interaction models were adapted from this project.

- [**Alcove**](https://tryalcove.com) - primary inspiration for the Minimalistic Mode interface design and its compact layout strategy.

- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) - window rendering for the HUDs and floating media controls

- [**rtaudio**](https://github.com/ZephyrCodesStuff/rtaudio) - Live music visualizer using C++ was adapted from this project

- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) - thanks DynamicNotch for letting us use their battery huds

A heartfelt thanks to [TheBoredTeam](https://github.com/TheBoredTeam) for being supportive and being totally awesome, Noori (and Atoll before it) would not have been possible without Boring.Notch
