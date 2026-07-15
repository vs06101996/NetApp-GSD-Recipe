# PRD: Widget Exporter

## Problem

Operators have no easy way to export widgets to CSV today. They resort to
manual copy-paste, which is slow and error-prone.

## Goals

What does success look like? List concrete, checkable outcomes.

- Export any widget list to CSV in one click.
- Preserve column ordering from the on-screen table.

## Non-Goals

- Does not cover XLSX export (deferred to a later PRD).

## Requirements

1. Add an "Export CSV" button to the widget list toolbar.
2. Exported CSV must match the visible column set exactly.

## Out of Scope

- Bulk scheduled exports.

## Open Questions (optional)

- Should exports include soft-deleted widgets?
