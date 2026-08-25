#!/usr/bin/env python3
"""Planning artifact guardrails after recipe-new-project / gsd-new-project."""
from __future__ import annotations

import json
import os
import re
import sys

MIN_BYTES = 50


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _file_ok(target: str, rel: str) -> tuple[bool, str]:
    path = os.path.join(target, rel)
    if not os.path.isfile(path):
        return False, f"missing {rel}"
    if os.path.getsize(path) < MIN_BYTES:
        return False, f"{rel} too small (likely hand-written stub)"
    return True, rel


def assess(target: str) -> dict:
    checks: dict[str, tuple[bool, str]] = {}
    for rel in (".planning/PROJECT.md", ".planning/ROADMAP.md", ".planning/STATE.md"):
        checks[rel] = _file_ok(target, rel)

    roadmap = _read(os.path.join(target, ".planning/ROADMAP.md"))
    if roadmap:
        if not re.search(r"(?m)^#{2,3} Phase \d+\b", roadmap):
            checks["roadmap_phases"] = (False, "ROADMAP.md has no ##/### Phase N headings")
        else:
            checks["roadmap_phases"] = (True, "phase headings present")
    else:
        checks["roadmap_phases"] = (False, "ROADMAP.md unreadable")

    state = _read(os.path.join(target, ".planning/STATE.md"))
    if state:
        if "## Tracker" not in state:
            checks["state_tracker"] = (False, "STATE.md missing ## Tracker section")
        else:
            checks["state_tracker"] = (True, "tracker section present")
    else:
        checks["state_tracker"] = (False, "STATE.md unreadable")

    failures = [name for name, (ok, _msg) in checks.items() if not ok]
    return {
        "ready": len(failures) == 0,
        "checks": {name: {"ok": ok, "detail": msg} for name, (ok, msg) in checks.items()},
        "failures": failures,
    }


def main(argv: list[str] | None = None) -> int:
    argv = list(argv if argv is not None else sys.argv[1:])
    json_out = False
    if "--json" in argv:
        json_out = True
        argv.remove("--json")
    target = "."
    if "--target" in argv:
        i = argv.index("--target")
        if i + 1 >= len(argv):
            print("--target requires a path", file=sys.stderr)
            return 2
        target = argv[i + 1]
    target = os.path.abspath(target)
    report = assess(target)
    if json_out:
        print(json.dumps(report, indent=2))
        return 0 if report["ready"] else 1
    if report["ready"]:
        return 0
    for name in report["failures"]:
        print(f"{name}: {report['checks'][name]['detail']}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
