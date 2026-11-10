# Changelog

All notable changes to Noori will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Album art background: the open notch can fill with the current song's album art behind the player, melting into a heavy blur toward the bottom so the controls and lyrics stay readable, and black at the top so it still blends with the camera. A second option puts a blurred cover behind the lyrics under the closed notch. It fades in and out with the notch and crossfades when the song changes. Turn it on in Settings › Music › Player.
- Call live activity: during a WhatsApp, FaceTime, Zoom, Microsoft Teams, Discord, Slack or Telegram call, the closed notch shows a green phone with the call's time on the left and a small waveform on the right, like on iPhone. Click it to bring the call back to the front. It takes the place of the music pill while the call lasts. Noori notices the call when the app has the microphone and sound running for a few seconds (so voice notes don't trigger it); no audio is recorded and no new permission is needed. Turn it off in Settings › Live Activities › Calls.
- New messages in the notch: when an iMessage or text arrives, the notch drops down with the sender's photo (or initials), name and message, and a reply field. Press Return to send the reply, Esc to dismiss; it hides by itself after about 6 seconds unless you're pointing at it or typing. Click the message to open Messages. Turn it on in Settings › Live Activities › Messages. It needs Full Disk Access (to read new messages), Contacts (for names and photos, optional) and permission to control Messages (asked on the first reply). Nothing from your messages is saved; Noori only remembers which message it saw last.

### Changed
- The music sneak peek uses the Default style for new installs (Inline is still in Settings › Music).
- The Settings search field shows an accent-colored outline while you type in it, and clicking anywhere on it starts typing.
- Volume, brightness and other HUDs always use the inline style in the notch; the "HUD style" setting and the old standard style are gone.
- New installs show the next lyric line under the current one by default (Settings › Lyrics › second line can change it).
- The title and controls blur in faster when the notch opens (sharp after about 0.16 s instead of 0.29 s).
- Lyrics are off by default for new installs. Turn them on with the lyrics button in the notch or in Settings › Lyrics.
- The default player controls are shuffle, previous, play/pause, next and lyrics. New installs used to get the media output button on the right, from a setting migration inherited from Atoll.
- The menu bar icon is off by default for new installs (Settings, Restart and Quit are in the notch's right-click menu; turn the icon on in Settings › General).
- Music player: the three main controls stay together in the center, and the two side buttons sit apart toward the edges, mirrored for balance.
- Volume bars are always green and brightness bars yellow in every volume/brightness HUD.

### Fixed
- Switching Spaces (into a fullscreen app especially) no longer makes the notch pop in at once; it fades in.
- The notch's shadow no longer stutters when it opens and closes: it's drawn from the plain notch outline and fades in and out, instead of shadowing everything inside the notch on every frame.
- With the album art background on, the notch's opening bounce showed a dark rim around the art; the bounce is skipped then.
- Spotify ads no longer fill the notch with the Spotify logo as album art; the art backgrounds hide while an ad plays.
- With blurred album art behind the closed-notch lyrics, the strip under the camera showed as a black bar over the art; the whole top band is now black and the art starts below it.
- Opening and closing the notch with an album art background is smooth again: the cover is now blurred once per song in the background (like Lyrimuse does) instead of on every frame of the animation.
- When a song's lyrics end (or start), the closed notch now shrinks (or grows) smoothly with the lyric row instead of snapping back.
- The album art flip on a track change is kept inside the cover's own frame; mid-flip it could make the closed notch show as a square-cornered black rectangle for a moment.
- The progress slider no longer vanishes before the rest of the player when the notch opens or closes: it used the same strong blur as the text, which smeared the thin bar away almost at once.
- Turning on Caps Lock while the notch was open put the closed notch's Caps Lock indicator over the album art (and could freeze the notch). It now only shows in the closed notch.
- The open notch's rounded bottom corners could be cut off when it was taller than its window (for example when the lyric row appeared without the window growing). The window now always makes room for the notch it shows, checking the window's real height (turning lyrics on for the first time could still cut off the second lyric line).
- The lyric row in the open notch only shows when the player has the lyrics button, so it can always be turned off where it appears; it used to show even after removing the button from the controls.

## [1.0.1] - 2026-11-09

### Changed
- Noori's repository is public, and updates and downloads now come from its own GitHub releases (github.com/wenujacodes/Noori/releases) instead of the separate Noori-releases repository.
- Removed about 2,800 lines of code nothing used anymore (the custom update window, TipKit tips, old Atoll helpers, views, settings keys and functions). Noori works the same; it's just smaller and quicker to build.
- Settings pages say what they control: Media is now **Music** and Controls is now **Volume & Brightness**. Live Activities labels use the same sentence case as the rest ("Detect screen recording", "Show Focus name"…) and its notes explain what each one does instead of which macOS API it uses.
- Settings › Appearance now has all the notch's size and shape settings: Notch height moved there from General, next to Notch width, and the two pickers for the style on screens without a notch (one in General, one in Appearance) are now one, "Style on screens without a notch", always shown in Appearance.
- Settings clean-up: the artist color setting in Media had the wrong label ("Enable colored spectograms"); it's now "Color the artist name with the album art". The loose "Hide Noori Options" picker is now "Hide Noori in full screen" in its own Full screen section. "Visualizer candles" is "Visualizer bars", "Progressbar style" is "Progress bar style", and the Devices notes point to the right page instead of one that doesn't exist.
- Smaller download: releases are stripped of debugging symbols (the universal app is about 19 MB instead of 48 MB, the zip about 7.5 MB instead of 11 MB). Nothing changes in how Noori works.

### Fixed
- Updated Sparkle (the updater) from 2.7.0 to 2.10.1, which fixes two security issues in how updates are installed.
- With Spotify as the music source, the notch catches up by itself after an ad: Spotify doesn't always announce when an ad hands over to the next song, so Noori now also checks shortly after each change, every 2 seconds during an ad, and when the current track should end.
- The open notch with lyrics is tall enough again: the lyric line was cut off at the bottom and the notch lost its rounded bottom corners, because the space reserved for the line didn't count the 11 pt the controls already take beyond their estimate.
- The open notch no longer slides up under the camera when lyrics load right after launch: the notch content is pinned to the top of its window, so if it's briefly taller than the window it runs past the bottom instead.
- Releases run on Intel Macs again: 1.0.0 was built for Apple Silicon only. Releases are now universal (Apple Silicon and Intel in one download).
- Long lyric lines no longer get cut off in the closed notch: when a song's lyrics load, the notch widens to fit its longest line (once per song, between 260 and 620 pt), and the window widens with it.
- With Second line › Next line, the line that moves up into the top row of the closed notch no longer disappears after each line change.
- Scrolling in Settings is smoother: rows no longer each draw an invisible search-highlight outline with a shadow, and the Media and Lyrics pages no longer redraw on every playback update while music plays.
- The layout preview in Settings › Music no longer shows the shuffle and repeat icons in red when they're on in the player.
- With Second line › Next line, the top row no longer looks empty in a pause: the upcoming line shows there, dimmed with a music note, and lights up in place when it's sung while the line after it slides in below.

## [1.0.0] - 2026-11-09

### Added
- First Noori release, forked from Atoll 2.3.3 and renamed to Noori.
- Lyrics in the open notch too: when lyrics are showing and the notch opens, the line being sung shows under the player controls and the notch grows to fit it (it stays while paused, so the notch doesn't change size).
- Lyrics under the notch: while a song plays, the closed notch gets a bit wider and shows the line being sung underneath, filling in word by word when the timing is available. Lyrics come from LRCLIB, NetEase Cloud Music and QQ Music (searched at the same time; word-by-word timing wins) and are kept in memory only, never saved on the Mac. Turn it on or off with the lyrics button in the player. Based on [Lyrimuse](https://github.com/Yudaotor/lyrimuse).
- Settings › Lyrics: choose the lyrics sources; a second line with the translation (NetEase's Chinese translations, or Apple's on-device translation into any language on macOS 15+, with a button to download the languages), the pronunciation (romaji, pinyin, Latin letters for Korean, Cyrillic and other scripts, worked out on the Mac) or the next line; Chinese characters as written, simplified or traditional; a timing offset; word fill, alignment, color (white or album art), text size and weight; and whether lyrics hide when paused. "Search again" fetches the current song's lyrics again.
- Menu bar icon (a bolt for now): click it to open or close the notch; right-click (or Control-click) for Settings…, Check for Updates…, Restart Noori and Quit Noori. It can be hidden with "Show menu bar icon" in Settings › General.
- AirDrop HUD: the notch shows "AirDrop · Off/Contacts Only/Everyone" when the AirDrop setting changes (red for Off, green otherwise), with a "Show AirDrop changes" toggle in Settings › Devices. AirDrop has no connected device to show, and macOS posts no notification for the setting, so Noori checks it every 2 seconds.
- Wi-Fi HUD: the notch shows "Wi-Fi · On/Off" and "Wi-Fi · Connected/Disconnected" when they change (green for on/connected, red for off/disconnected), with a "Show Wi-Fi changes" toggle in Settings › Devices. The network name isn't shown, since macOS only gives it to apps with Location permission.
- Bluetooth battery reminders: the device HUD shows again when a connected device drops to 75%, 50%, 25%, 10% and 5% (once per level until it's charged back above it), and a device that disconnects at 5% or less shows "Battery dead" in red. Battery levels are re-read every 30 seconds while a device is connected.
- Turning Bluetooth on or off shows "Bluetooth · On/Off" in the notch (part of "Show Bluetooth device connections").
- Disconnecting a Bluetooth audio device shows "<device> · Disconnected" in the notch instead of the Mac's volume level.
- Clicking Noori's app icon while it's running (Finder, Launchpad, Spotlight) opens the notch; clicking it again while the notch is open opens Settings.
- Sparkle updates are set up: Noori has its own update signing key, an update feed (`Updates/appcast.xml`) and a release script (`scripts/release.sh <version>`) that picks the next build number itself, then builds, zips, signs and adds the version to the feed.
- Lock icon on the lock screen: when the Mac is locked, the notch widens slightly and shows a lock on its left side. Hovering it gives a small bounce and a haptic tap (it doesn't open). On unlock the lock opens and the pill shrinks back into the notch; if a song is playing, the music pill then grows out smoothly.
- The volume HUD bar turns red while the sound is muted and stays at the current volume level, instead of being replaced by the word "muted".
- Search in Settings is back: a search field at the top of the sidebar with suggestions; picking one opens its tab, scrolls to the setting and highlights it. The search list only covers settings that exist in Noori.
- Copyright line (© 2026 Wenuja Liyanamana) in the About window.

### Changed
- While lyrics show under the closed notch, changing the volume, brightness or keyboard backlight shows a bar (icon, level, percentage) under the lyrics instead of the wide inline HUD; the lyrics stay up.
- During a pause in the lyrics (and just before the first line), the notch shows the upcoming line, dimmed, with the music note instead of the note alone.
- The extra player buttons (shuffle, repeat, lyrics, media output, AirPlay) animate when clicked: they squeeze and spring back with a bounce, and their color fades between on and off.
- The album art in the open notch stays full size and full brightness when the song is paused.
- Word-by-word lyrics animate like Apple Music: each word lights up with a soft edge, rises slightly as it's sung, and long held words glow; when a line is done it slides up and out as the next one slides up from below, both staying sharp.
- The Bluetooth icon in the HUD is a little smaller (14 pt tall, was 16).
- Wi-Fi, AirDrop and Bluetooth HUD words (On/Off, Connected/Disconnected, Contacts Only/Everyone, and the Wi-Fi/AirDrop title) roll to the new value like the brightness percentage when they change while the HUD is showing.
- The Bluetooth device name in the HUD uses the same font as the other HUD titles (Wi-Fi, AirDrop, Volume) instead of a larger one.
- The Bluetooth and Wi-Fi HUD icons no longer get a slash when off or disconnected; the colored On/Off/Disconnected text shows the state.
- Bluetooth HUD: the Bluetooth on/off HUD uses the Bluetooth rune (with a slash when off) and shows "On" in green / "Off" in red; "Disconnected" is red; the battery ring and bar go smoothly from green (75%+) through yellow (50%) and orange (25%) to red (10% and below).
- A long Bluetooth device name in the connection HUD scrolls through twice before the HUD closes.
- The Bluetooth connection HUD shows the battery percentage as a number next to the ring by default.
- The Bluetooth device-connected HUD stays up for 5 seconds (was 2.5).
- The Bluetooth connection HUD shows the device name by default ("Show device name" is on for new installs).
- The Settings window opens and closes instantly, with no fade (macOS's own window animation is off too).
- Settings section titles and labels use one style (sentence case, e.g. "Notch height", "Music visualizer", "Skip button behavior"); "Noori Progress Bars" is now "Progress bars" and "Battery Indicator Styling" is "Battery indicator style".
- In the open notch the two time labels use the slider color (white, the album color, or the accent color), and the extra player buttons (shuffle, repeat, media output, AirPlay, lyrics) are grey so previous, play/pause and next stand out.
- The notch no longer bounces when it closes; it just shrinks smoothly onto the closed notch.
- Opening the notch is a little faster again (open spring 0.32 s, was 0.36 s), with the content fade-in and bounce shortened to match.
- The album cover flip on a song change is slower and smoother (0.75 s with a smooth curve, was 0.45 s ease-in-out).
- The song name and artist in the small notch (sneak peek and the song line on screens without a notch) use the same 11 pt medium font as the open notch's artist name.
- The album cover flip on a song change now blurs as it turns (strongest halfway through, sharp again when it lands).
- The explicit "E" badge is now a bright white square with a black E (it was a faint grey square).
- The artist name in the open notch is a little bigger (11 pt medium instead of 10 pt regular) so it's easier to read.
- The song sneak peek (on song change or hover) still hides after 3 seconds, but when the title or artist is too long and scrolls, it stays until the name has scrolled through once.
- Long song titles and artist names start scrolling after half a second instead of three, and the artist name now stops at the same edge as the title instead of running under the visualizer.
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
- The closed notch no longer shows an empty lyrics strip during a song's intro or after its last line (the ending): the lyric row shows from just before the first line until the last one is sung.
- With Second line › Next line, the two lines no longer move as one block: when a line is done it slides up and out on its own, and the next line moves up and grows into its place.
- The open player could sit too high, with the album art and controls under the camera notch, right after launch: lyrics loaded while the notch was closed didn't make the window taller, so the taller open player didn't fit. The window now grows for lyrics while the notch is closed too.
- Opening and closing the notch is smooth again while lyrics show: the lyric line no longer measures its text every frame, only draws the glow on held notes, and draws word-by-word lines as one layer.
- The player controls stay centered when only one end slot has a button (for example the lyrics button on the right and nothing on the left); the empty slot used to stretch and push the controls to one side.
- Turning lyrics on or off with the lyrics button in the open notch now grows or shrinks the notch smoothly, with the lyric line sliding in, instead of jumping.
- Moving the song slider (or skipping ±10 seconds) now moves the lyrics right away. Some players, like Spotify through Now Playing, don't report a seek, so the lyrics kept going from the old spot until the song was paused and played again.
- Lyrics and the song progress bar could run up to a second early, by a different amount after each update: macOS's Now Playing times were read rounded down to the whole second. Noori now reads them to the microsecond.
- The Bluetooth device HUD could show up as an empty wide notch with only the headphones icon (the device name didn't draw). The name is now always drawn, and the HUD isn't shown when it would have neither a name nor a battery level.
- Turning on a Focus other than Do Not Disturb (e.g. Reduce Interruptions) no longer shows the Do Not Disturb pill when Noori can't tell which Focus it is (no Full Disk Access): it shows a neutral "Focus". With Full Disk Access, each Focus shows its own name and icon.
- The volume HUD no longer flashes for a moment when the audio output switches, e.g. when Bluetooth earphones disconnect.
- Connecting Bluetooth earphones that report their battery late (e.g. Soundcore) showed the volume HUD instead of the connection HUD; the volume HUD is now held back while the connection HUD waits for the battery level.
- When nothing is playing (no music in the closed notch), the open player's album art and visualizer now blur in and out with the notch instead of popping; they still glide from the closed notch when a song is showing there.
- Possible cause of the whole Mac freezing while Noori runs: Noori kept macOS's OSD helper (OSDUIHelper) paused with SIGSTOP to hide the native volume/brightness popup, and anything waiting on that helper could hang until Noori quit. Noori no longer pauses it (it already swallows the media keys itself) and resumes it if an older run left it paused.
- Scrolling song titles and artist names no longer jump sideways when a scroll loop ends (the text was measured 10 pt too wide).
- Battery HUDs (charging, low battery, full battery) had a flat bottom with square corners: the window was sized exactly to the HUD, so its rounded bottom (and the hover growth) got cut off. The window now stays at least its normal size.
- Long song titles now start scrolling on their own: restarts no longer leave several scroll loops running that kept snapping the text back to the start.
- Song titles slightly too long for the open notch now scroll instead of running under the visualizer: the title's width is measured in the font it's drawn with.
- The "Closed notch / pill width" slider in Appearance now moves in 10 px steps, so its tick marks match the other sliders instead of forming a dense row.
- The brightness HUD sometimes didn't show and the macOS brightness popup appeared instead. The media key listener now runs on its own thread, so it can't be delayed by work on the main thread (like the brightness change itself) and timed out by macOS.
- The notch no longer shifts to the right after a music sneak peek (hiding half the album art under the camera until you hovered). SwiftUI was stretching the window from its left edge to fit the wider sneak peek; Noori now sizes and re-centers the window itself.
- Small memory leaks when reading the keyboard backlight level and audio device names.
- All compiler warnings (Swift 6 concurrency and raw-pointer warnings); the project now builds with none.
- Brightness and volume keys no longer show nothing when Accessibility permission is missing: Noori keeps the macOS popups visible until it can handle the keys, and starts handling them as soon as permission is granted, without a restart.
- GitHub logo on the About page now follows the text color instead of always being white.

### Removed
- Noori no longer asks for Full Disk Access (the Focus settings callout and the Permissions menu items are gone). Without it, a Focus other than one Noori can identify shows as a neutral "Focus" pill. If Full Disk Access is granted manually, Focus names and icons are still read.
- The Apple Music permission text, which was only used for the removed animated artwork.
- Live canvas (Apple Music animated album art) and its "Show live canvas in Noori" setting. The album cover is always the still artwork.
- The "HUD Tests" buttons (test charging / low / full battery HUD) in the Battery settings.
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
- "Corner radius scaling" setting; the open notch now always uses the larger, scaled corners.
- The onboarding window (welcome screen, media player picker and finish screen), including its "Focus detection mode" popup. First-run defaults are still applied on first launch, and Focus detection uses the Standard mode.
