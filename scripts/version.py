#!/usr/bin/env python3
"""Resolve stable SemVer tags and stamp app metadata without a version file."""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PATTERN = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z")


def parse_tag(value):
    match = PATTERN.fullmatch(value)
    if not match:
        raise ValueError("Use a stable SemVer tag such as v1.2.3 (no leading zeros or prerelease suffix).")
    return tuple(int(part) for part in match.groups())


def tag_for(parts):
    return "v" + ".".join(map(str, parts))


def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def valid_tags(root, merged=False):
    args = ["tag", "--list", "v*"]
    if merged:
        args.extend(["--merged", "HEAD"])
    return sorted((tag for tag in (git(root, *args) or "").splitlines() if PATTERN.fullmatch(tag)), key=parse_tag)


def resolve(root=ROOT, *, tag=None, bump=None, version=None, verify_tag=False):
    root = Path(root).resolve()
    top = git(root, "rev-parse", "--show-toplevel")
    is_repo = top is not None and Path(top).resolve() == root
    commit = git(root, "rev-parse", "HEAD") if is_repo else None
    build = str(max(1, int(git(root, "rev-list", "--count", "HEAD") or "0"))) if commit else "1"
    create_tag = False
    if bump:
        if not commit:
            raise ValueError("Creating a release requires a Git checkout with a commit.")
        tags = valid_tags(root)
        latest = parse_tag(tags[-1]) if tags else (0, 0, 0)
        if version:
            tag = version if version.startswith("v") else "v" + version
            parts = parse_tag(tag)
        else:
            major, minor, patch = latest
            parts = {"patch": (major, minor, patch + 1), "minor": (major, minor + 1, 0), "major": (major + 1, 0, 0)}[bump]
            tag = tag_for(parts)
        existing = git(root, "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}")
        if existing:
            if existing != commit:
                raise ValueError(f"{tag} already points to another commit; choose a newer version.")
        elif parts <= latest:
            raise ValueError("A new release version must be greater than the latest SemVer tag.")
        else:
            create_tag = True
    else:
        tag = tag or os.environ.get("BROWSER_PICKER_RELEASE_TAG")
        if not tag and commit:
            tags = valid_tags(root, merged=True)
            tag = tags[-1] if tags else None
        parts = parse_tag(tag) if tag else (0, 0, 0)
        if verify_tag:
            if not tag or not commit or git(root, "rev-parse", "--verify", f"refs/tags/{tag}^{{commit}}") != commit:
                raise ValueError("The release tag must point to the checked-out commit.")
    return {"version": ".".join(map(str, parts)), "tag": tag, "build": build, "commit": commit, "create_tag": create_tag}


def stamp(path, metadata, metadata_path=None):
    path = Path(path)
    info = plistlib.loads(path.read_bytes())
    info["CFBundleShortVersionString"] = metadata["version"]
    info["CFBundleVersion"] = metadata["build"]
    path.write_bytes(plistlib.dumps(info, sort_keys=False))
    if metadata_path:
        payload = {**metadata, "architecture": platform.machine()}
        Path(metadata_path).write_text(json.dumps(payload, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag")
    parser.add_argument("--next", choices=["patch", "minor", "major"], dest="bump")
    parser.add_argument("--version", help="Optional explicit version when creating a release.")
    parser.add_argument("--verify-tag", action="store_true")
    parser.add_argument("--write-plist")
    parser.add_argument("--metadata")
    parser.add_argument("--github-output", action="store_true")
    args = parser.parse_args()
    if args.version and not args.bump:
        parser.error("--version requires --next")
    if args.tag and args.bump:
        parser.error("Choose --tag or --next, not both")
    try:
        metadata = resolve(tag=args.tag, bump=args.bump, version=args.version, verify_tag=args.verify_tag)
        if args.write_plist:
            stamp(args.write_plist, metadata, args.metadata)
        if args.github_output:
            with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
                for key, value in metadata.items():
                    value = str(value).lower() if isinstance(value, bool) else value or ""
                    output.write(f"{key}={value}\n")
        print(json.dumps(metadata))
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f"Version error: {error}\n")


if __name__ == "__main__":
    main()
