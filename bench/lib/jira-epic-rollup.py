#!/usr/bin/env python3
"""Pure Jira Epic roll-up policy.

The caller owns Jira I/O. This helper receives status-category snapshots and
returns the one allowed status action, making the policy deterministic and
testable without Atlassian credentials.
"""
from __future__ import annotations

import argparse
import json
import sys


ACTIVE_EVENTS = {
    "plan_complete",
    "plan_revised",
    "execute_started",
    "execute_complete",
    "verify_complete",
    "review_complete",
}


def evaluate(event: str, epic_category: str, children: list[dict]) -> dict:
    epic_category = epic_category.lower().strip()
    normalized_children = [
        {
            **child,
            "category": str(child.get("category", "unknown")).lower().strip(),
        }
        for child in children
    ]

    if event == "reopened":
        if epic_category == "indeterminate":
            return {"action": "no-op", "reason": "epic already active"}
        return {
            "action": "transition",
            "target_status": "In Progress",
            "reason": "phase reopened",
        }

    if event == "settled":
        if not normalized_children:
            return {"action": "no-op", "reason": "no recorded phase tasks"}
        missing = [
            str(child.get("key", "<unknown>"))
            for child in normalized_children
            if child.get("category") not in {"new", "indeterminate", "done"}
        ]
        if missing:
            if epic_category == "new":
                return {
                    "action": "transition",
                    "target_status": "In Progress",
                    "reason": "child status unavailable; refusing to close epic",
                    "unknown_children": missing,
                }
            return {
                "action": "no-op",
                "reason": "child status unavailable; refusing to close epic",
                "unknown_children": missing,
            }
        if all(child["category"] == "done" for child in normalized_children):
            if epic_category == "done":
                return {"action": "no-op", "reason": "epic already done"}
            return {
                "action": "transition",
                "target_status": "Done",
                "reason": "all recorded phase tasks are done",
            }
        if epic_category == "new":
            return {
                "action": "transition",
                "target_status": "In Progress",
                "reason": "some recorded phase tasks remain incomplete",
            }
        return {
            "action": "no-op",
            "reason": "epic remains active until all phase tasks are done",
        }

    if event in ACTIVE_EVENTS:
        if epic_category == "new":
            return {
                "action": "transition",
                "target_status": "In Progress",
                "reason": "phase work is active",
            }
        return {"action": "no-op", "reason": "epic is already active or complete"}

    return {"action": "no-op", "reason": f"event {event!r} has no epic roll-up"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--event", required=True)
    parser.add_argument("--epic-category", required=True)
    parser.add_argument("--children-json", required=True)
    args = parser.parse_args(argv)

    try:
        children = json.loads(args.children_json)
    except json.JSONDecodeError as exc:
        print(f"jira-epic-rollup: invalid --children-json: {exc}", file=sys.stderr)
        return 2
    if not isinstance(children, list):
        print("jira-epic-rollup: --children-json must be a JSON array", file=sys.stderr)
        return 2

    print(json.dumps(evaluate(args.event, args.epic_category, children)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
