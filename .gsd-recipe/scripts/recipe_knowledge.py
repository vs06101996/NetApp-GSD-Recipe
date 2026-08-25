#!/usr/bin/env python3
"""Shared knowledge-readiness checks for recipe-next, recipe-status, and verify CLI."""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone


MIN_CODEBASE_DOCS = 2
MIN_DOC_BYTES = 48
MIN_GRAPH_BYTES = 16


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def codebase_map_ok(target: str) -> tuple[bool, str]:
    root = os.path.join(target, ".planning", "codebase")
    if not os.path.isdir(root):
        return False, "missing .planning/codebase/"
    docs = [
        name
        for name in os.listdir(root)
        if name.endswith(".md") and os.path.isfile(os.path.join(root, name))
    ]
    if len(docs) < MIN_CODEBASE_DOCS:
        return False, f"need at least {MIN_CODEBASE_DOCS} .planning/codebase/*.md files (found {len(docs)})"
    small = [
        name
        for name in docs
        if os.path.getsize(os.path.join(root, name)) < MIN_DOC_BYTES
    ]
    if small:
        return False, f"codebase docs too small (likely hand-written stubs): {', '.join(small)}"
    return True, f"{len(docs)} codebase docs"


def _graph_file_ok(path: str) -> bool:
    try:
        size = os.path.getsize(path)
    except OSError:
        return False
    if size < MIN_GRAPH_BYTES:
        return False
    if path.endswith(".json"):
        try:
            with open(path, encoding="utf-8") as f:
                json.load(f)
        except (OSError, json.JSONDecodeError):
            return False
    return True


def graph_output_ok(target: str) -> tuple[bool, str]:
    for rel in (".planning/graphs", "graphify-out"):
        root = os.path.join(target, rel)
        if not os.path.isdir(root):
            continue
        for dirpath, _, filenames in os.walk(root):
            for name in filenames:
                path = os.path.join(dirpath, name)
                if _graph_file_ok(path):
                    return True, f"graph artifact {os.path.relpath(path, target)}"
    return False, "no non-empty graph output under .planning/graphs/ or graphify-out/"


def marker_ok(target: str) -> tuple[bool, str]:
    raw = _read(os.path.join(target, ".gsd-recipe", "KNOWLEDGE-BOOTSTRAPPED"))
    if not raw.strip():
        return False, "missing .gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return False, "KNOWLEDGE-BOOTSTRAPPED is not valid JSON"
    if data.get("status") != "ready":
        return False, 'KNOWLEDGE-BOOTSTRAPPED status is not "ready"'
    return True, "marker ready"


def assess(target: str) -> dict:
    checks = {
        "marker": marker_ok(target),
        "codebase_map": codebase_map_ok(target),
        "graph_output": graph_output_ok(target),
    }
    failures = [name for name, (ok, _msg) in checks.items() if not ok]
    return {
        "ready": len(failures) == 0,
        "checks": {name: {"ok": ok, "detail": msg} for name, (ok, msg) in checks.items()},
        "failures": failures,
    }


def knowledge_ready(target: str) -> bool:
    return assess(target)["ready"]


def write_marker(target: str) -> None:
    report = assess(target)
    if not report["ready"]:
        lines = ["knowledge not ready — marker not written:"]
        for name in report["failures"]:
            lines.append(f"  - {name}: {report['checks'][name]['detail']}")
        raise SystemExit("\n".join(lines))
    path = os.path.join(target, ".gsd-recipe", "KNOWLEDGE-BOOTSTRAPPED")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    payload = {
        "status": "ready",
        "completed_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f)
        f.write("\n")


def main(argv: list[str] | None = None) -> int:
    argv = argv if argv is not None else sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help"):
        print(
            "Usage: recipe_knowledge.py check|write-marker|json [--target DIR]",
            file=sys.stderr,
        )
        return 2
    cmd = argv[0]
    target = "."
    rest = argv[1:]
    if "--target" in rest:
        i = rest.index("--target")
        if i + 1 >= len(rest):
            print("--target requires a path", file=sys.stderr)
            return 2
        target = rest[i + 1]
    target = os.path.abspath(target)

    if cmd == "check":
        report = assess(target)
        if not report["ready"]:
            for name in report["failures"]:
                print(f"{name}: {report['checks'][name]['detail']}", file=sys.stderr)
            return 1
        return 0
    if cmd == "write-marker":
        try:
            write_marker(target)
        except SystemExit as exc:
            print(str(exc), file=sys.stderr)
            return 1
        return 0
    if cmd == "json":
        print(json.dumps(assess(target), indent=2))
        return 0
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
