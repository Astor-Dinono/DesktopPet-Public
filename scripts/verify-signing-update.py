#!/usr/bin/env python3
"""Compare two completed local builds. This does not grant or inspect TCC access."""
import pathlib
import plistlib
import re
import subprocess
import sys


def signature(path):
    app = pathlib.Path(path).resolve()
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    result = subprocess.run(["codesign", "--display", "--verbose=4", "-r-", str(app)],
                            check=True, capture_output=True, text=True)
    output = result.stdout + result.stderr
    requirement = re.search(r"^designated => (.+)$", output, re.MULTILINE)
    cdhash = re.search(r"^CDHash=(.+)$", output, re.MULTILINE)
    if not requirement or not cdhash:
        raise ValueError("Missing explicit signature identity or content hash")
    with (app / "Contents/Info.plist").open("rb") as stream:
        version = plistlib.load(stream)["CFBundleVersion"]
    return app, requirement.group(1), cdhash.group(1), version


def main():
    if len(sys.argv) != 3:
        raise ValueError("Usage: python3 scripts/verify-signing-update.py old.app new.app")
    old, new = map(signature, sys.argv[1:])
    if old[1] != new[1] or "certificate leaf = " not in new[1] or "cdhash" in new[1]:
        raise ValueError("Builds do not share a certificate-bound identity")
    if old[2] == new[2] or old[3] == new[3]:
        raise ValueError("Expected distinct content hashes and build numbers")
    for app in (old[0], new[0]):
        subprocess.run(["codesign", "--verify", "-R", "=" + new[1], str(app)], check=True)
    print(f"Builds {old[3]} and {new[3]}: different CDHashes; identical certificate-bound identity.")
    print("Both pass the same requirement. Input Monitoring must still be verified in the running app.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(f"Signing validation failed: {error}", file=sys.stderr)
        sys.exit(1)
