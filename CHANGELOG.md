# Changelog

All notable changes to Noori will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Copyright line (© 2026 Wenuja Liyanamana) in the About window.

### Changed
- Caps Lock indicator color now defaults to Green (White and Accent are still available).
- Moved the media appearance options (spectrograms, color tinting, slider color) from the Appearance tab to the Media tab.
- The simpler close animation is now always used; its toggle was removed from Appearance settings.
- Renamed the Focus detection options in the Focus menu to "Standard (needs Full Disk Access)" and "Faster, via system logs (needs Developer Tools permission)", replacing the confusing "Use DevTools" wording.
- The default media player for new installs is now Now Playing on every macOS version (it was Apple Music on macOS 15.4 and later).
- Updated swiftui-introspect from 1.3.0 to 26.2.0 (fixes the deprecated package manifest warning in Xcode).

### Fixed
- GitHub logo on the About page now follows the text color instead of always being white.

### Removed
- Divider lines above the credit line on the About page.
- Blurred glow behind the album art, along with its "Enable blur effect behind album art" setting.
- "Beta" badges in Settings.
- App icon picker in Appearance settings (custom app icons).
- "Hello" animation that opened the notch on first launch.
- Welcome sound that played on first launch.
- The onboarding window (welcome screen, media player picker and finish screen), including its "Focus detection mode" popup. First-run defaults are still applied on first launch, and Focus detection uses the Standard mode.

## [1.0.0]

### Changed
- First Noori release, forked from Atoll 2.3.3 and renamed to Noori.
