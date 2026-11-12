#!/usr/bin/env python3
"""Validate that the Wally package exposes only the shared public API."""

from pathlib import Path
import re
import tomllib

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "wally.toml"
ENTRYPOINT = ROOT / "src" / "init.lua"
API_MODULE = ROOT / "src" / "shared" / "CombatAPI.lua"
API_DOC = ROOT / "docs" / "API.md"


def main() -> None:
    manifest = tomllib.loads(MANIFEST.read_text(encoding="utf-8"))
    package = manifest.get("package", {})

    required = {
        "name": "jaojaocabecademelao/combatapi",
        "version": "0.3.0",
        "license": "MIT",
        "realm": "shared",
        "registry": "https://github.com/UpliftGames/wally-index",
        "private": True,
        "include": ["/src/init.lua", "/src/shared/**"],
    }
    for key, expected in required.items():
        actual = package.get(key)
        if actual != expected:
            raise SystemExit(f"Invalid [package].{key}: expected {expected!r}, got {actual!r}")

    if not ENTRYPOINT.is_file():
        raise SystemExit("Missing src/init.lua Wally package entrypoint")
    if "return require(script.shared.CombatAPI)" not in ENTRYPOINT.read_text(encoding="utf-8"):
        raise SystemExit("Wally entrypoint must return the shared public CombatAPI facade")
    if not API_MODULE.is_file():
        raise SystemExit("Missing src/shared/CombatAPI.lua public facade")

    semver = re.search(r'SemVer\s*=\s*"([^"]+)"', API_MODULE.read_text(encoding="utf-8"))
    if not semver or semver.group(1) != package["version"]:
        raise SystemExit("Wally package version must match CombatAPI.SemVer")
    if not API_DOC.is_file():
        raise SystemExit("Missing docs/API.md public API reference")
    api_doc = API_DOC.read_text(encoding="utf-8")
    if f"reports the package release version (`{package['version']}`)" not in api_doc:
        raise SystemExit("docs/API.md package release version must match CombatAPI.SemVer")

    if not (ROOT / "src" / "server").is_dir():
        raise SystemExit("Expected server test/source tree is missing")

    print(f"Wally package manifest valid: {package['name']}@{package['version']}")
    print("Package boundary: /src/init.lua + /src/shared/**; server tree excluded")


if __name__ == "__main__":
    main()
