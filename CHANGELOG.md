# Changelog

All notable changes to Noori will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Search in Settings is back: a search field at the top of the sidebar with suggestions; picking one opens its tab, scrolls to the setting and highlights it. The search list only covers settings that exist in Noori.
- Copyright line (© 2026 Wenuja Liyanamana) in the About window.

### Changed
- Opening the notch is a little faster (about 15%), including the blur-in of the title and controls. Closing is unchanged.
- Long artist names now scroll like the song title instead of being cut off, in the open notch and in the closed-notch sneak peek.
- The visualizer now has 5 candles by default (was 4); it can still be changed in Settings.
- The visualizer now has 5 candles by default (was 4); it can still be changed in Settings.
- The visualizer now has 5 candles by default (was 4); it can still be changed in Settings.
- The default minimum hover duration to open the notch is now 0.2s (was 0.3s); it can still be changed in Settings.
- After launch, the notch shows the current song's cover right away instead of a heart placeholder (or the player's app icon) first, and without a flip.
- The album art and visualizer stay sharp when the notch opens and closes; the title and controls blur and fade.
- The album art and visualizer glide smoothly from the closed notch into the open player instead of jumping, and the album art no longer flashes black while the notch opens.
- The notch shape bounces once as it finishes opening, and as it closes it stops a few points short of the closed size, then settles onto it in one move, so the real notch is never uncovered. The content inside doesn't bounce.
- Fixed a Swift concurrency warning in the YouTube Music controller.
- The volume, brightness and keyboard backlight HUDs no longer appear when Noori starts; they only show when the level changes.
- Notch, HUD and live activity animations now share a small set of motions (`NooriMotion`), so they move consistently. Opening the notch uses the same spring everywhere instead of three slightly different ones.
- The song progress bar in the open notch now updates 4 times a second instead of every display frame, cutting CPU use while music plays with the notch open from about 27% to about 8%.
- The hidden-notch hover check (for "hide until hover" on screens without a notch) now only runs while the notch is hidden, instead of waking the CPU 20 times a second all the time.
- Lower idle CPU and battery use: Noori no longer launches a `pgrep` process about 7 times a second to keep the macOS volume/brightness popup hidden; it waits for that service to restart instead. Bluetooth connections use IOBluetooth notifications instead of checking every 3 seconds, the AirPods listening-mode log reader only runs while AirPods are connected, and Focus detection watches its file instead of reading it every 2 seconds.
- The Controls page in Settings is now one scrolling page instead of two separately scrolling halves.
- Caps Lock indicator color now defaults to Green (White and Accent are still available).
- Moved the media appearance options (spectrograms, color tinting, slider color) from the Appearance tab to the Media tab.
- The simpler close animation is now always used; its toggle was removed from Appearance settings.
- Renamed the Focus detection options in the Focus menu to "Standard (needs Full Disk Access)" and "Faster, via system logs (needs Developer Tools permission)", replacing the confusing "Use DevTools" wording.
- Keyboard shortcuts are now off by default (they can be turned on in Settings).
- Color extraction now defaults to Legacy (Vibrant is still available in Settings).
- README and the Apple Music permission text no longer mention removed features (lyrics, real-time audio, lock screen wallpaper, Metal Toolchain).
- Sneak peek is now on by default, with the Inline style (both can be changed in Settings).
- Launch at Login is now turned on for new installs (it can be turned off in Settings).
- The default media player for new installs is now Now Playing on every macOS version (it was Apple Music on macOS 15.4 and later).
- Updated swiftui-introspect from 1.3.0 to 26.2.0 (fixes the deprecated package manifest warning in Xcode).

### Fixed
- Long song titles now start scrolling on their own: restarts no longer leave several scroll loops running that kept snapping the text back to the start.
- Song titles slightly too long for the open notch now scroll instead of running under the visualizer: the title's width is measured in the font it's drawn with.
- The "Closed notch / pill width" slider in Appearance no longer shows a dense row of tick marks; it still moves in 5 px steps.
- The brightness HUD sometimes didn't show and the macOS brightness popup appeared instead. The media key listener now runs on its own thread, so it can't be delayed by work on the main thread (like the brightness change itself) and timed out by macOS.
- The notch no longer shifts to the right after a music sneak peek (hiding half the album art under the camera until you hovered). SwiftUI was stretching the window from its left edge to fit the wider sneak peek; Noori now sizes and re-centers the window itself.
- Small memory leaks when reading the keyboard backlight level and audio device names.
- All compiler warnings (Swift 6 concurrency and raw-pointer warnings); the project now builds with none.
- Brightness and volume keys no longer show nothing when Accessibility permission is missing: Noori keeps the macOS popups visible until it can handle the keys, and starts handling them as soon as permission is granted, without a restart.
- GitHub logo on the About page now follows the text color instead of always being white.

### Removed
- The "Show power status icons" battery option; the charging/plug icon on the battery always shows.
- The "Color-coded volume display" option: the volume HUD bar is always white now (it was green/yellow/red by level).
- Unused entries from the string catalog.
- Spotify Canvas: the Spotify sign-in / `sp_dc` cookie setting and fetching Spotify's looping track videos. Live canvas still works for Apple Music animated artwork. Spotify artist names still come from Spotify's public track page.
- The album art parallax (3D tilt on hover) effect and its intensity setting.
- The "Vibrant" color extraction mode and the Color extraction setting; the visualizer and tinting always use the original (Legacy) album art color.
- 3D (animated video) icons in the Bluetooth device HUD and the "HUD icon style" setting; the HUD always uses the device symbol. The 8 AirPods/Beats animation videos were deleted.
- Unused `sparkle` and `spotlight` images.
- Divider lines above the credit line on the About page.
- Blurred glow behind the album art, along with its "Enable blur effect behind album art" setting.
- "Beta" badges in Settings.
- App icon picker in Appearance settings (custom app icons).
- "Hello" animation that opened the notch on first launch.
- Welcome sound that played on first launch.
- "Extend hover area" setting, which had almost no effect.
- All of Atoll's app icons (release, Dev, Alpha, Beta and Nightly) and its unused logo images. The app icon slot is empty for now, so macOS shows its default app icon.
- Unused `MinimalisticMusicView` and translations for removed features.
- Unused Metal shader (`visualizer.metal`), the empty bridging header and the unused Accelerate framework link. Building no longer needs the Metal Toolchain.
- Real-time waveform: live audio capture, the C++ audio processing behind it, the scrubbable waveform on the progress bar, the "Enable real-time waveform" and "Scrubbable real-time waveform" settings, and the audio capture permission. The music visualizer always shows the animated bars.
- Lyrics feature (fetching from LRCLIB, the lyrics line in the player, and the "Enable lyrics" setting). The lyrics button stays in the music controls as a placeholder for a future version and does nothing for now.
- "Corner radius scaling" setting; the open notch now always uses the larger, scaled corners.
- The onboarding window (welcome screen, media player picker and finish screen), including its "Focus detection mode" popup. First-run defaults are still applied on first launch, and Focus detection uses the Standard mode.

## [1.0.0]

### Changed
- First Noori release, forked from Atoll 2.3.3 and renamed to Noori.
