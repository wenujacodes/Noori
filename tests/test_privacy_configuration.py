import plistlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTITLEMENTS = ROOT / "Noori" / "Noori.entitlements"
PROJECT = ROOT / "Noori.xcodeproj" / "project.pbxproj"


class PrivacyConfigurationTests(unittest.TestCase):
    def test_media_players_are_authorized_for_apple_events(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertNotIn("AUTOMATION_APPLE_EVENTS = NO;", project)
        allowed = entitlements["com.apple.security.temporary-exception.apple-events"]
        self.assertIn("com.spotify.client", allowed)
        self.assertIn("com.apple.Music", allowed)
        self.assertIn("com.apple.MobileSMS", allowed)

    def test_automation_usage_text_names_media_players(self):
        project = PROJECT.read_text()

        self.assertEqual(
            2,
            project.count(
                'INFOPLIST_KEY_NSAppleEventsUsageDescription = "Noori uses AppleScripts to control Spotify and Apple Music, and to send your quick replies in Messages.";'
            ),
        )

    def test_contacts_access_is_declared_for_message_alerts(self):
        project = PROJECT.read_text()
        entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())

        self.assertTrue(entitlements["com.apple.security.personal-information.addressbook"])
        self.assertEqual(
            2,
            project.count(
                'INFOPLIST_KEY_NSContactsUsageDescription = "Noori shows the names and photos of your contacts when a new message appears in the notch.";'
            ),
        )


if __name__ == "__main__":
    unittest.main()
