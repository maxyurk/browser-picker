#!/usr/bin/env python3
"""Exercise real Sparkle installations on disposable apps using public RFC test data.

Never reads/writes a production signing key or the user's app/settings/defaults.
"""
import base64
import hashlib
import http.server
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import threading
import time
import uuid
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ARTIFACT = ROOT / ".build/artifacts/sparkle/Sparkle"
FRAMEWORKS = ARTIFACT / "Sparkle.xcframework/macos-arm64_x86_64"
# RFC 8032 section 7.1, publicly documented test vector, NOT a production secret.
TEST_SEED = base64.b64encode(bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")).decode()
TEST_PUBLIC = "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="


def run(*arguments, **kwargs):
    return subprocess.run(list(map(str, arguments)), check=True, **kwargs)


def bundle_digest(app):
    digest = hashlib.sha256()
    for path in sorted(app.rglob("*")):
        digest.update(str(path.relative_to(app)).encode() + b"\0")
        if path.is_symlink():
            digest.update(b"link:" + os.readlink(path).encode())
        elif path.is_file():
            digest.update(str(path.stat().st_mode & 0o777).encode())
            digest.update(path.read_bytes())
        else:
            digest.update(b"directory")
    return digest.hexdigest()


def main():
    executable = ROOT / "build/UpdaterHarness"
    run("swiftc", "-O", "-swift-version", "6", "-parse-as-library", "-F", FRAMEWORKS,
        "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
        ROOT / "Sources/BrowserPicker/AppUpdater.swift", ROOT / "Sources/BrowserPicker/QuietUpdateDriver.swift",
        ROOT / "scripts/UpdaterHarness.swift", "-o", executable)
    with tempfile.TemporaryDirectory(prefix="browser-picker-update-e2e-") as temporary:
        folder = Path(temporary)
        requests = []
        class Handler(http.server.SimpleHTTPRequestHandler):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, directory=str(folder), **kwargs)
            def log_message(self, *args):
                pass
            def do_GET(self):
                requests.append(self.path)
                if "/rate-limit/" in self.path:
                    self.send_response(429); self.send_header("Retry-After", "3600"); self.end_headers()
                elif "/unavailable/" in self.path:
                    self.send_response(503); self.end_headers()
                else:
                    super().do_GET()
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        origin = f"http://127.0.0.1:{server.server_port}"
        try:
            for case in ["no-update", "rate-limit", "unavailable", "malformed", "tampered-feed", "tampered-archive", "install", "auto-install"]:
                case_dir = folder / case
                case_dir.mkdir()
                result_path = case_dir / "result.json"
                identity = "test.browser-picker.update." + uuid.uuid4().hex
                app = case_dir / "installed/Browser Picker.app"
                contents = app / "Contents"
                (contents / "MacOS").mkdir(parents=True)
                (contents / "Frameworks").mkdir()
                shutil.copyfile(executable, contents / "MacOS/BrowserPicker")
                os.chmod(contents / "MacOS/BrowserPicker", 0o755)
                run("ditto", FRAMEWORKS / "Sparkle.framework", contents / "Frameworks/Sparkle.framework")
                info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
                info.update(CFBundleIdentifier=identity, CFBundleVersion="1", CFBundleShortVersionString="1.0.0",
                            SUPublicEDKey=TEST_PUBLIC, SUFeedURL=f"{origin}/{case}/appcast.xml",
                            SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
                            NSAppTransportSecurity={"NSAllowsLocalNetworking": True}, UpdateTestResult=str(result_path))
                info.pop("CFBundleURLTypes", None); info.pop("CFBundleDocumentTypes", None)
                if case in ["rate-limit", "unavailable"]:
                    info.update(SUEnableAutomaticChecks=True, UpdateTestMode="background")
                if case == "auto-install":
                    info.update(SUEnableAutomaticChecks=True, SUAutomaticallyUpdate=True, UpdateTestMode="auto-install")
                (contents / "Info.plist").write_bytes(plistlib.dumps(info))
                run("codesign", "--force", "--sign", "-", app, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                original = bundle_digest(app)
                candidate = case_dir / "candidate/Browser Picker.app"
                run("ditto", app, candidate)
                new_info = dict(info)
                if case != "no-update":
                    new_info.update(CFBundleVersion="2", CFBundleShortVersionString="1.0.1")
                (candidate / "Contents/Info.plist").write_bytes(plistlib.dumps(new_info))
                run("codesign", "--force", "--sign", "-", candidate, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                archive = case_dir / "Browser-Picker.zip"
                run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", candidate, archive)
                if case == "install":
                    import sys
                    sys.path.insert(0, str(ROOT / "scripts"))
                    import update_feed
                    release = case_dir / "release-validation"
                    release.mkdir()
                    shutil.copyfile(archive, release / archive.name)
                    (release / "BuildInfo.json").write_text('{"tag":"v1.0.1"}')
                    with patch.object(update_feed, "public_key", return_value=TEST_PUBLIC), patch.dict(os.environ, {"SPARKLE_ED25519_PRIVATE_KEY": TEST_SEED}):
                        update_feed.generate(candidate, release)
                    # Verify that the production public-key verifier fails closed.
                    signature = update_feed.validate_feed(release / "appcast.xml", release / archive.name, new_info, "v1.0.1")
                    bad_archive = release / "tampered.zip"
                    bad_archive.write_bytes(b"tampered")
                    invalid = subprocess.run(["swift", str(ROOT / "scripts/verify-update.swift"), TEST_PUBLIC, str(bad_archive), signature], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    assert invalid.returncode != 0, "production archive verifier accepted tampered content"
                    print("PASS release signing and public-key verification", flush=True)
                run(ARTIFACT / "bin/generate_appcast", "--ed-key-file", "-", "--maximum-deltas", "0",
                    "--download-url-prefix", f"{origin}/{case}/", "-o", case_dir / "appcast.xml", case_dir,
                    input=TEST_SEED + "\n", text=True, stdout=subprocess.DEVNULL)
                if case == "malformed":
                    (case_dir / "appcast.xml").write_text("<broken>")
                elif case == "tampered-feed":
                    path = case_dir / "appcast.xml"
                    path.write_text(path.read_text().replace("</channel>", "<description>tampered</description></channel>"))
                elif case == "tampered-archive":
                    with archive.open("ab") as handle:
                        handle.write(b"tampered")
                log = (case_dir / "run.log").open("w")
                process = subprocess.Popen([str(contents / "MacOS/BrowserPicker")], stdout=log, stderr=log)
                deadline = time.monotonic() + 45
                while not result_path.exists() and time.monotonic() < deadline:
                    time.sleep(0.1)
                if not result_path.exists():
                    process.terminate()
                    raise AssertionError(f"{case}: no result; see {(case_dir/'run.log').read_text()[-3000:]}")
                result = json.loads(result_path.read_text())
                expected = "ready-on-quit" if case == "auto-install" else "installed" if case == "install" else "no-update" if case == "no-update" else "error"
                assert result["outcome"] == expected, (case, result, (case_dir / "run.log").read_text()[-3000:])
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.terminate(); process.wait(timeout=5)
                if case not in ["install", "auto-install"]:
                    assert bundle_digest(app) == original, f"{case}: existing app was modified"
                else:
                    deadline = time.monotonic() + 15
                    while time.monotonic() < deadline:
                        try:
                            if plistlib.loads((contents / "Info.plist").read_bytes())["CFBundleVersion"] == "2":
                                break
                        except FileNotFoundError:
                            pass
                        time.sleep(0.1)
                    assert plistlib.loads((contents / "Info.plist").read_bytes())["CFBundleVersion"] == "2"
                    run("codesign", "--verify", "--deep", "--strict", app)
                if case in ["no-update", "rate-limit", "unavailable"]:
                    result_path.unlink()
                    info.update(UpdateTestMode="throttle", SUEnableAutomaticChecks=True)
                    (contents / "Info.plist").write_bytes(plistlib.dumps(info))
                    run("codesign", "--force", "--sign", "-", app, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    before = len(requests)
                    second = subprocess.Popen([str(contents / "MacOS/BrowserPicker")], stdout=log, stderr=log)
                    second.wait(timeout=10)
                    assert json.loads(result_path.read_text())["outcome"] == "throttled"
                    assert len(requests) == before, "relaunch caused an extra update request"
                subprocess.run(["defaults", "delete", identity], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                log.close()
                print(f"PASS {case}", flush=True)
        finally:
            server.shutdown(); server.server_close()


if __name__ == "__main__":
    main()
