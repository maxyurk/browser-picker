#!/usr/bin/env python3
"""Configure and verify signed Sparkle releases. Private keys only enter via stdin."""
import argparse
import base64
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PUBLIC_KEY = ROOT / "Resources/UpdatePublicKey.txt"
TOOLS = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
REPOSITORY = "https://github.com/maxyurk/browser-picker"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def public_key(path=PUBLIC_KEY, required=True):
    key = Path(path).read_text().strip()
    if not key and not required:
        return None
    try:
        if len(base64.b64decode(key, validate=True)) != 32:
            raise ValueError()
    except (ValueError, base64.binascii.Error):
        raise ValueError("Configure the public update-signing key in Resources/UpdatePublicKey.txt.") from None
    return key


def configure(app, key_file=PUBLIC_KEY):
    path = Path(app) / "Contents/Info.plist"
    info = plistlib.loads(path.read_bytes())
    key = public_key(key_file, required=False)
    if key:
        info["SUPublicEDKey"] = key
    else:
        info.pop("SUPublicEDKey", None)
    path.write_bytes(plistlib.dumps(info))


def validate_feed(path, archive, info, tag):
    if not re.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)", tag):
        raise ValueError("Expected a stable release tag.")
    root = ET.parse(path).getroot()
    items = root.findall("channel/item")
    if len(items) != 1:
        raise ValueError("The update feed must contain exactly this release.")
    item = items[0]
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("The update archive is missing.")
    if item.findtext(SPARKLE + "version") != info["CFBundleVersion"]:
        raise ValueError("The update build number does not match the app.")
    if item.findtext(SPARKLE + "shortVersionString") != tag[1:] or info["CFBundleShortVersionString"] != tag[1:]:
        raise ValueError("The update version does not match the release.")
    if item.findtext(SPARKLE + "minimumSystemVersion") != info["LSMinimumSystemVersion"]:
        raise ValueError("The update macOS requirement does not match the app.")
    if enclosure.get("url") != f"{REPOSITORY}/releases/download/{tag}/Browser-Picker.zip":
        raise ValueError("The update must use this release's immutable GitHub archive URL.")
    if enclosure.get("length") != str(Path(archive).stat().st_size):
        raise ValueError("The update archive size does not match the feed.")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    try:
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError()
    except (ValueError, base64.binascii.Error):
        raise ValueError("The update archive needs a valid Ed25519 signature.") from None
    return signature


def generate(app, output):
    output = Path(output)
    info = plistlib.loads((Path(app) / "Contents/Info.plist").read_bytes())
    build = json.loads((output / "BuildInfo.json").read_text())
    key = public_key()
    if info.get("SUPublicEDKey") != key or not info.get("SURequireSignedFeed") or not info.get("SUVerifyUpdateBeforeExtraction"):
        raise ValueError("Release app is missing its update verification configuration.")
    private_key = os.environ.get("SPARKLE_ED25519_PRIVATE_KEY", "").strip()
    if not private_key:
        raise ValueError("Configure the SPARKLE_ED25519_PRIVATE_KEY GitHub Actions secret before publishing.")
    archive = output / "Browser-Picker.zip"
    with tempfile.TemporaryDirectory(prefix="browser-picker-appcast-") as temporary:
        folder = Path(temporary)
        shutil.copyfile(archive, folder / archive.name)
        (folder / "Browser-Picker.md").write_text("Verified updates from GitHub. Routing stays on your Mac.\n")
        subprocess.run([
            str(TOOLS / "generate_appcast"), "--ed-key-file", "-", "--maximum-deltas", "0",
            "--download-url-prefix", f"{REPOSITORY}/releases/download/{build['tag']}/",
            "--embed-release-notes", "-o", str(folder / "appcast.xml"), str(folder),
        ], input=private_key + "\n", text=True, check=True)
        feed = folder / "appcast.xml"
        signature = validate_feed(feed, archive, info, build["tag"])
        # Validate against the app's PUBLIC key, not just the signing tool's key.
        subprocess.run(["swift", str(ROOT / "scripts/verify-update.swift"), key, str(archive), signature], check=True)
        subprocess.run([str(TOOLS / "sign_update"), "--verify", "--ed-key-file", "-", str(feed)],
                       input=private_key + "\n", text=True, check=True)
        shutil.copyfile(feed, output / "appcast.xml")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["configure", "validate-key", "generate"])
    parser.add_argument("app", nargs="?")
    parser.add_argument("output", nargs="?")
    args = parser.parse_args()
    try:
        if args.command == "configure":
            configure(args.app)
        elif args.command == "validate-key":
            public_key()
        else:
            generate(args.app, args.output)
    except (ValueError, OSError, subprocess.CalledProcessError, ET.ParseError) as error:
        parser.exit(1, f"Update release validation failed: {error}\n")


if __name__ == "__main__":
    main()
