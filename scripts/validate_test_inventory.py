#!/usr/bin/env python3
"""Check that CombatDocumentationTest lists every automated test module once."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "src" / "server"
DOC_TEST = SERVER / "CombatDocumentationTest.lua"
MANUAL_TESTS = {"CombatMultiplayerSmokeTest.server.lua"}

if not DOC_TEST.is_file():
    raise SystemExit("Missing src/server/CombatDocumentationTest.lua")

source = DOC_TEST.read_text(encoding="utf-8")
match = re.search(r"local documentedTests\s*=\s*\{(.*?)\n\}", source, re.S)
if not match:
    raise SystemExit("Could not locate documentedTests inventory")

documented = re.findall(r'"([^"\n]+Test\.lua)"', match.group(1))
actual = sorted(path.name for path in SERVER.glob("*Test.lua"))
missing_manual = sorted(name for name in MANUAL_TESTS if not (SERVER / name).is_file())

missing = sorted(set(actual) - set(documented))
stale = sorted(set(documented) - set(actual))
duplicates = sorted(name for name in set(documented) if documented.count(name) > 1)

if missing or stale or duplicates or missing_manual or len(actual) != len(documented):
    if missing:
        print("Missing from documentation:", *missing, sep="\n  ")
    if stale:
        print("Documented but absent:", *stale, sep="\n  ")
    if duplicates:
        print("Duplicate inventory entries:", *duplicates, sep="\n  ")
    if missing_manual:
        print("Missing separately gated tests:", *missing_manual, sep="\n  ")
    raise SystemExit(1)

print(
    f"Test inventory valid: {len(actual)} automated ModuleScripts; "
    f"{len(MANUAL_TESTS)} separately gated server Script"
)
