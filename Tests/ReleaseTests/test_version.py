import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("release_version", Path(__file__).resolve().parents[2] / "scripts/version.py")
versioning = importlib.util.module_from_spec(spec)
spec.loader.exec_module(versioning)


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.invalid")
        self.commit()
        environment = patch.dict(os.environ)
        environment.start()
        self.addCleanup(environment.stop)
        os.environ.pop("BROWSER_PICKER_RELEASE_TAG", None)

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.DEVNULL, text=True).strip()

    def commit(self):
        path = self.root / "source.txt"
        path.write_text((path.read_text() if path.exists() else "") + "change\n")
        self.git("add", "source.txt")
        self.git("commit", "-m", "Test commit")

    def test_stable_semver_validation(self):
        self.assertEqual(versioning.parse_tag("v10.20.30"), (10, 20, 30))
        self.assertEqual(versioning.parse_tag("v0.0.0"), (0, 0, 0))
        for value in ["1.2.3", "v01.2.3", "v1.02.3", "v1.2.03", "v1.2", "v1.2.3-beta", "v1.2.3+build", "v1.2.3\nname=other", "v１.2.3", "$(echo test)"]:
            with self.subTest(value=value), self.assertRaises(ValueError): versioning.parse_tag(value)

    def test_no_tags_is_a_development_build(self):
        result = versioning.resolve(self.root)
        self.assertEqual(result["version"], "0.0.0")
        self.assertIsNone(result["tag"])
        self.assertEqual(result["build"], "1")
        self.assertEqual(result["commit"], self.git("rev-parse", "HEAD"))

    def test_versions_sort_numerically(self):
        for tag in ["v2.0.0", "v10.0.0", "v1.0.0", "other-tag", "v99.0.0-beta"]: self.git("tag", tag)
        self.assertEqual(versioning.resolve(self.root)["version"], "10.0.0")

    def test_development_build_keeps_reachable_version_and_counts_commits(self):
        self.git("tag", "v1.0.1"); self.commit()
        result = versioning.resolve(self.root)
        self.assertEqual(result["version"], "1.0.1")
        self.assertEqual(result["build"], "2")

    def test_unreachable_tag_does_not_version_a_local_build(self):
        self.git("tag", "v1.0.0")
        previous = self.git("rev-parse", "HEAD")
        self.commit(); self.git("tag", "v9.0.0"); self.git("checkout", previous)
        self.assertEqual(versioning.resolve(self.root)["version"], "1.0.0")

    def test_bump_levels(self):
        self.git("tag", "v2.3.4")
        for bump, expected in [("patch", "v2.3.5"), ("minor", "v2.4.0"), ("major", "v3.0.0")]:
            with self.subTest(bump=bump):
                result = versioning.resolve(self.root, bump=bump)
                self.assertEqual(result["tag"], expected)
                self.assertTrue(result["create_tag"])

    def test_first_release_can_choose_explicit_version(self):
        self.assertEqual(versioning.resolve(self.root, bump="patch", version="1.0.1")["tag"], "v1.0.1")
        self.assertEqual(versioning.resolve(self.root, bump="patch", version="v1.0.1")["version"], "1.0.1")

    def test_bump_does_not_mutate_tags(self):
        versioning.resolve(self.root, bump="patch")
        self.assertEqual(self.git("tag", "--list"), "")

    def test_no_downgrade_or_moving_existing_tag(self):
        self.git("tag", "v2.0.0"); self.commit()
        for requested in ["1.0.0", "2.0.0"]:
            with self.subTest(requested=requested), self.assertRaises(ValueError):
                versioning.resolve(self.root, bump="patch", version=requested)

    def test_retry_same_release_commit_is_idempotent(self):
        self.git("tag", "-a", "v1.0.1", "-m", "Release")
        result = versioning.resolve(self.root, bump="patch", version="1.0.1")
        self.assertFalse(result["create_tag"])
        self.assertEqual(result["tag"], "v1.0.1")

    def test_verify_tag_requires_exact_checkout(self):
        self.git("tag", "-a", "v1.0.1", "-m", "Release")
        self.assertEqual(versioning.resolve(self.root, tag="v1.0.1", verify_tag=True)["version"], "1.0.1")
        self.commit()
        with self.assertRaises(ValueError): versioning.resolve(self.root, tag="v1.0.1", verify_tag=True)
        with self.assertRaises(ValueError): versioning.resolve(self.root, tag="v9.0.0", verify_tag=True)

    def test_archive_and_nested_directory_do_not_inherit_parent_tags(self):
        self.git("tag", "v9.0.0")
        child = self.root / "archive"; child.mkdir()
        result = versioning.resolve(child)
        self.assertEqual(result["version"], "0.0.0")
        self.assertIsNone(result["commit"])
        with self.assertRaises(ValueError): versioning.resolve(child, bump="patch")

    def test_explicit_build_tag_is_validated(self):
        with patch.dict(os.environ, {"BROWSER_PICKER_RELEASE_TAG": "v1.0.1"}):
            self.assertEqual(versioning.resolve(self.root)["version"], "1.0.1")
        with patch.dict(os.environ, {"BROWSER_PICKER_RELEASE_TAG": "v01.0.1"}):
            with self.assertRaises(ValueError): versioning.resolve(self.root)

    def test_stamp_preserves_bundle_identity_and_records_source(self):
        plist = self.root / "Info.plist"
        plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "example.picker", "LSMinimumSystemVersion": "14.0"}))
        metadata = versioning.resolve(self.root, tag="v1.0.1")
        output = self.root / "BuildInfo.json"
        versioning.stamp(plist, metadata, output)
        info = plistlib.loads(plist.read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "1.0.1")
        self.assertEqual(info["CFBundleVersion"], "1")
        self.assertEqual(info["CFBundleIdentifier"], "example.picker")
        self.assertEqual(json.loads(output.read_text())["commit"], metadata["commit"])


if __name__ == "__main__": unittest.main()
