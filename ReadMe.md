<h1 align="center">Noori for macOS</h1>

Noori turns the MacBook notch into a lightweight island for music, lyrics, live activities and system controls. It stays out of the way until you need it, then opens with smooth, native SwiftUI animations.

## Features
- **Music:** now playing for Apple Music, Spotify and any app that shows up in macOS Now Playing, with album art, a visualizer and customizable controls.
- **Synced lyrics:** the line being sung shows under the notch, filling in word by word when the timing is available. Optional translation (on-device on macOS 15+), pronunciation (romaji, pinyin…) or the next line underneath.
- **Live activities:** charging, Focus, screen recording, camera and microphone use, and Caps Lock.
- **Devices:** Bluetooth headphones and AirPods with battery levels and low-battery reminders, plus Wi-Fi and AirDrop changes.
- **Volume and brightness:** custom HUDs in the notch replace the macOS ones, including keyboard backlight.
- **Battery:** charging, low and full battery alerts.
- **Gestures and shortcuts:** swipe to open, close or skip tracks, and keyboard shortcuts.
- **Updates:** Noori updates itself (right-click the menu bar icon › Check for Updates…).

## Requirements
- macOS 14.6 or later. Translating lyrics into other languages needs macOS 15 or later.
- Best on a MacBook with a notch; on other screens Noori shows a pill at the top.
- Runs on Apple Silicon and Intel Macs.
- Permissions when you use the matching feature: Accessibility (volume and brightness HUDs), Bluetooth (device HUDs) and Automation (Spotify and Apple Music controls).

## Install
1. Download `Noori-<version>.zip` from the [latest release](https://github.com/wenujacodes/Noori/releases/latest).
2. Unzip it and move **Noori.app** to Applications.
3. Noori isn't notarized yet, so the first time, right-click **Noori.app**, choose **Open**, then **Open** again.
4. Grant the permissions it asks for.

## Privacy
- Lyrics are looked up on LRCLIB, NetEase Cloud Music and QQ Music using the song's title, artist, album and length. They're kept in memory only, never saved. You can turn sources off, or lyrics entirely, in Settings › Lyrics.
- Translation with Apple's on-device translation stays on your Mac.

## Build from source
Requires Xcode with Swift 6.1+.

```bash
git clone https://github.com/wenujacodes/Noori.git
cd Noori
open Noori.xcodeproj   # scheme "Noori", run on My Mac
```

Pick your own team under Signing & Capabilities (a free Personal Team works).

## License
Noori is released under the GPL v3 License. Refer to [LICENSE](LICENSE) for the full terms and [NOTICE](NOTICE) for attribution.

## Acknowledgments

Noori builds upon the work of several open-source projects:

- [**Atoll**](https://github.com/Ebullioscopic/Atoll) - the project Noori is forked from. Noori's codebase, features, and design come from Atoll by [Ebullioscopic](https://github.com/Ebullioscopic) and the Atoll contributors.

- [**Boring.Notch**](https://github.com/TheBoredTeam/boring.notch) - foundational codebase that provided the initial media player integration. Major architectural patterns and notch interaction models were adapted from this project.

- [**Lyrimuse**](https://github.com/Yudaotor/lyrimuse) by [Yudaotor](https://github.com/Yudaotor) - Noori's notch lyrics are based on Lyrimuse: its LRC and word-by-word lyric parsers, and the way it looks up lyrics on LRCLIB, NetEase Cloud Music and QQ Music.

- [**Alcove**](https://tryalcove.com) - inspiration for the compact notch layout.

- [**SkyLightWindow**](https://github.com/Lakr233/SkyLightWindow) - window rendering for the HUDs.

- [**DynamicNotch**](https://github.com/jackson-storm/DynamicNotch) - thanks DynamicNotch for letting us use their battery HUDs.

- [**Sparkle**](https://sparkle-project.org) - updates.

A heartfelt thanks to [TheBoredTeam](https://github.com/TheBoredTeam) for being supportive and being totally awesome, Noori (and Atoll before it) would not have been possible without Boring.Notch
