<h1 align="center">Noori for macOS</h1>

<p align="center">
  <a href="https://github.com/wenujacodes/Noori/releases/latest"><img src="https://img.shields.io/github/v/release/wenujacodes/Noori?style=for-the-badge&label=Download&color=0A84FF&logo=github" alt="Latest release"></a>
  <a href="https://github.com/wenujacodes/Noori/releases"><img src="https://img.shields.io/github/downloads/wenujacodes/Noori/total?style=for-the-badge&color=30D158&logo=icloud&logoColor=white" alt="Downloads"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/wenujacodes/Noori?style=for-the-badge&color=BF5AF2" alt="License: GPL-3.0"></a>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.6%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14.6+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-Universal-555555?style=for-the-badge&logo=apple&logoColor=white" alt="Universal: Apple Silicon and Intel">
  <img src="https://img.shields.io/badge/Swift-6.1%2B-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6.1+">
  <img src="https://img.shields.io/badge/Status-Active%20development-FF9F0A?style=for-the-badge" alt="Status: active development">
  <a href="https://github.com/wenujacodes/Noori/stargazers"><img src="https://img.shields.io/github/stars/wenujacodes/Noori?style=for-the-badge&color=FFD60A&logo=github" alt="GitHub stars"></a>
</p>

Noori turns the MacBook notch into a lightweight island for music, lyrics, live activities and system controls. It stays out of the way until you need it, then opens with smooth, native SwiftUI animations.

> [!NOTE]
> Noori is still in active development. Expect frequent updates, and occasional rough edges. Bug reports and ideas are welcome in [Issues](https://github.com/wenujacodes/Noori/issues).

## Features
- **Music:** now playing for Apple Music, Spotify and any app that shows up in macOS Now Playing, with album art, a visualizer in the cover's colors (Vibrant, or the classic Legacy look) and customizable controls. Optionally, the album art fills the open notch (blurred toward the bottom) or sits blurred behind the lyrics.
- **Synced lyrics:** the line being sung shows under the notch, filling in word by word when the timing is available, with the next line underneath. Or show a translation (on-device on macOS 15+) or pronunciation (romaji, pinyin…) instead. Turn lyrics on with the lyrics button in the notch. If a song's lyrics run early or late, right-click the notch › Lyrics Timing to nudge just that song, or shift every song in Settings › Lyrics.
- **Calls:** during a WhatsApp, FaceTime, Zoom, Teams, Discord, Slack or Telegram call, the notch shows a green call timer, like on iPhone. Click it to go back to the call.
- **Messages:** new iMessages and texts drop down from the notch with the sender's photo, and you can reply right there (optional; needs Full Disk Access).
- **Live activities:** charging, Focus, screen recording, camera and microphone use, and Caps Lock.
- **Devices:** Bluetooth headphones and AirPods with battery levels and low-battery reminders, plus Wi-Fi and AirDrop changes.
- **Volume and brightness:** custom HUDs in the notch replace the macOS ones (green for volume, yellow for brightness), including keyboard backlight.
- **Battery:** charging, low and full battery alerts.
- **Gestures and shortcuts:** swipe to open, close or skip tracks, and keyboard shortcuts.
- **Updates:** Noori updates itself (Settings › About › Check for Updates; right-click the notch for Settings).

## Requirements
- macOS 14.6 or later. Translating lyrics into other languages needs macOS 15 or later.
- Best on a MacBook with a notch; on other screens Noori shows a pill at the top.
- Runs on Apple Silicon and Intel Macs.
- Permissions when you use the matching feature: Accessibility (volume and brightness HUDs), Bluetooth (device HUDs), Automation (Spotify and Apple Music controls, and replying in Messages), and for message alerts Full Disk Access (to read new messages) and Contacts (names and photos).

## Install
1. Download `Noori-<version>.dmg` (or the `.zip`) from the [latest release](https://github.com/wenujacodes/Noori/releases/latest).
2. Open it and drag **Noori.app** to Applications.
3. Noori isn't notarized yet, so the first time, right-click **Noori.app**, choose **Open**, then **Open** again.
4. Grant the permissions it asks for.

## Privacy
- Lyrics are looked up on LRCLIB, NetEase Cloud Music and QQ Music using the song's title, artist, album and length. They're kept in memory only, never saved. You can turn sources off, or lyrics entirely, in Settings › Lyrics.
- Translation with Apple's on-device translation stays on your Mac.
- Message alerts read new messages from your Mac's Messages database, on your Mac only. Noori never stores or sends message contents; it only remembers which message it showed last.
- Call detection only checks which apps are using the microphone and speakers. No audio is recorded.

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
