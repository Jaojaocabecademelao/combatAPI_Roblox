#!/usr/bin/env python3
"""Check that CombatDocumentationTest lists every server test script exactly once."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "src" / "server"
DOC_TEST = SERVER / "CombatDocumentationTest.server.lua"

if not DOC_TEST.is_file():
    raise SystemExit("Missing src/server/CombatDocumentationTest.server.lua")

source = DOC_TEST.read_text(encoding="utf-8")
match = re.search(r"local documentedTests\s*=\s*\{(.*?)\n\}", source, re.S)
if not match:
    raise SystemExit("Could not locate documentedTests inventory")

documented = re.findall(r'"([^"\n]+Test\.server\.lua)"', match.group(1))
actual = sorted(path.name for path in SERVER.glob("*Test.server.lua"))

missing = sorted(set(actual) - set(documented))
stale = sorted(set(documented) - set(actual))
duplicates = sorted(name for name in set(documented) if documented.count(name) > 1)

if missing or stale or duplicates or len(actual) != len(documented):
    if missing:
        print("Missing from documentation:", *missing, sep="\n  ")
    if stale:
        print("Documented but absent:", *stale, sep="\n  ")
    if duplicates:
        print("Duplicate inventory entries:", *duplicates, sep="\n  ")
    raise SystemExit(1)

print(f"Test inventory valid: {len(actual)} server test scripts")
