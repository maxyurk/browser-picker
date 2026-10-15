import base64
import importlib.util
import os
import plistlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("update_feed", ROOT / "scripts/update_feed.py")
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


class UpdateFeedTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.key = base64.b64encode(b"k" * 32).decode()
        self.key_file = self.root / "public.txt"
        self.key_file.write_text(self.key)
        self.app = self.root / "Browser Picker.app"
        (self.app / "Contents").mkdir(parents=True)
        self.info = {
            "CFBundleVersion": "25", "CFBundleShortVersionString": "1.2.3",
            "LSMinimumSystemVersion": "14.0", "SUPublicEDKey": self.key,
            "SURequireSignedFeed": True, "SUVerifyUpdateBeforeExtraction": True,
        }
        self.plist = self.app / "Contents/Info.plist"
        self.plist.write_bytes(plistlib.dumps(self.info))
        self.archive = self.root / "Browser-Picker.zip"
        self.archive.write_bytes(b"archive fixture")
        self.xml = self.root / "appcast.xml"
        self.tree = ET.Element("rss")
        self.channel = ET.SubElement(self.tree, "channel")
        self.item = ET.SubElement(self.channel, "item")
        for key, value in [("version", "25"), ("shortVersionString", "1.2.3"), ("minimumSystemVersion", "14.0")]:
            ET.SubElement(self.item, feed.SPARKLE + key).text = value
        self.enclosure = ET.SubElement(self.item, "enclosure", {
            "url": feed.REPOSITORY + "/releases/download/v1.2.3/Browser-Picker.zip",
            "length": str(self.archive.stat().st_size),
            feed.SPARKLE + "edSignature": base64.b64encode(b"s" * 64).decode(),
        })

    def validate(self, tag="v1.2.3"):
        self.xml.write_bytes(ET.tostring(self.tree))
        return feed.validate_feed(self.xml, self.archive, self.info, tag)

    def test_public_key_validates_exact_length_and_encoding(self):
        self.assertEqual(feed.public_key(self.key_file), self.key)
        for bad in ["", "invalid", base64.b64encode(b"x" * 31).decode(), base64.b64encode(b"x" * 33).decode()]:
            self.key_file.write_text(bad)
            with self.assertRaises(ValueError):
                feed.public_key(self.key_file)

    def test_unconfigured_development_build_has_no_trust_key(self):
        self.key_file.write_text("")
        feed.configure(self.app, self.key_file)
        self.assertNotIn("SUPublicEDKey", plistlib.loads(self.plist.read_bytes()))

    def test_configure_embeds_public_key_without_changing_bundle_fields(self):
        feed.configure(self.app, self.key_file)
        self.assertEqual(plistlib.loads(self.plist.read_bytes()), self.info)

    def test_matching_feed_metadata(self):
        self.assertEqual(self.validate(), self.enclosure.get(feed.SPARKLE + "edSignature"))

    def test_reject_unsafe_or_unstable_tags(self):
        for tag in ["1.2.3", "v01.2.3", "v1.2.3-beta", "v1.2.3/../../other", "v1.2.3?other"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.validate(tag)

    def test_reject_mixed_release_versions(self):
        self.item.find(feed.SPARKLE + "version").text = "24"
        with self.assertRaises(ValueError):
            self.validate()
        self.item.find(feed.SPARKLE + "version").text = "25"
        self.item.find(feed.SPARKLE + "shortVersionString").text = "1.2.2"
        with self.assertRaises(ValueError):
            self.validate()

    def test_reject_wrong_minimum_macos(self):
        self.item.find(feed.SPARKLE + "minimumSystemVersion").text = "12.0"
        with self.assertRaises(ValueError):
            self.validate()

    def test_reject_foreign_mutable_or_wrong_release_downloads(self):
        for url in ["https://example.com/Browser-Picker.zip", feed.REPOSITORY + "/releases/latest/download/Browser-Picker.zip", feed.REPOSITORY + "/releases/download/v1.2.2/Browser-Picker.zip", feed.REPOSITORY + "/releases/download/v1.2.3/Browser-Picker.zip?extra=1"]:
            with self.subTest(url=url), self.assertRaises(ValueError):
                self.enclosure.set("url", url)
                self.validate()

    def test_reject_missing_or_duplicate_update_items(self):
        self.channel.remove(self.item)
        with self.assertRaises(ValueError):
            self.validate()
        self.channel.append(self.item); self.channel.append(self.item)
        with self.assertRaises(ValueError):
            self.validate()

    def test_reject_missing_archive(self):
        self.item.remove(self.enclosure)
        with self.assertRaises(ValueError):
            self.validate()

    def test_reject_truncated_download_metadata(self):
        self.enclosure.set("length", str(self.archive.stat().st_size - 1))
        with self.assertRaises(ValueError):
            self.validate()

    def test_reject_missing_and_malformed_signatures(self):
        for signature in ["", "unsigned", base64.b64encode(b"s" * 63).decode(), base64.b64encode(b"s" * 65).decode()]:
            self.enclosure.set(feed.SPARKLE + "edSignature", signature)
            with self.subTest(signature=signature), self.assertRaises(ValueError):
                self.validate()

    def test_missing_private_key_stops_before_running_signing_tools(self):
        (self.root / "BuildInfo.json").write_text('{"tag":"v1.2.3"}')
        with patch.object(feed, "public_key", return_value=self.key), patch.dict(os.environ, {}, clear=True), patch.object(feed.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "GitHub Actions secret"):
                feed.generate(self.app, self.root)
            run.assert_not_called()
        self.assertFalse(self.xml.exists())


if __name__ == "__main__":
    unittest.main()
