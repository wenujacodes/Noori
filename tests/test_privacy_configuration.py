import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTITLEMENTS = ROOT / "Noori" / "Noori.entitlements"
PROJECT = ROOT / "Noori.xcodeproj" / "project.pbxproj"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_camera_capture_is_explicitly_entitled(self):
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements.get("com.apple.security.device.camera"))

    def test_media_players_are_authorized_for_apple_events(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        allowed = entitlements["com.apple.security.temporary-exception.apple-events"]
        self.assertIn("com.spotify.client", allowed)
        self.assertIn("com.apple.Music", allowed)

    def test_automation_usage_text_names_media_players(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count(
                'INFOPLIST_KEY_NSAppleEventsUsageDescription = "Noori uses AppleScripts to control Spotify and Apple Music.";'
            ),
        )

    def test_full_access_reminder_api_has_matching_usage_text(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count("INFOPLIST_KEY_NSRemindersFullAccessUsageDescription ="),
        )


if __name__ == "__main__":
    unittest.main()
