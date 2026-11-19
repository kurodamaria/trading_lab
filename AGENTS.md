# AGENTS.md

## Commands
- Verify UI/all: `flutter analyze`
- Verify domain: `dart test`

## Architectural Boundaries
- `lib/domain/` and `test/domain/` MUST remain 100% pure Dart (no `package:flutter/...` or `dart:ui` imports).
- Text/icons painted over `theme.badgeBackground` MUST use `theme.badgeText`.
- Use `.withValues(alpha: ...)` instead of deprecated `.withOpacity(...)`.

## Visual & Theme Scope
- Use `ChartTheme.nytNewsprint` exclusively. Do NOT reintroduce Dark or Liquid Glass themes, `BackdropFilter` chrome, or hardcoded colors outside `ChartTheme` (except EMA overlays).

## Input & Rendering Discipline
- Never use delta-accumulation (`ratio + delta`) inside high-frequency pointer handlers; map `globalPosition` via `RenderBox` or use deterministic state.
- Do not add fade animations to chart candles.

## Git Hygiene (Strict)
- Never run `git commit` or `git push` unless explicitly instructed by the user in the current turn.
- Never stage or leave behind temporary patch files (`patch.txt`, `*.bak`, `*.orig`).
- At the end of every completed task, run `flutter analyze && dart test`, run `git status -s`, and print a suggested one-line conventional commit command (`git add -A && git commit -m "..."`) for the user to run after visual hot-reload verification.

## Execution & Output Contract
- Use targeted `SEARCH/REPLACE` edits on existing files; avoid full-file rewrites.
- Never leave empty `() {}` stubs or `// TODO` placeholders; if an interface is ambiguous, stop and ask in 1 line.
- Run `flutter analyze` (and `dart test` when `lib/domain/` or `test/` changes) before finishing.
- Skip narration; respond with a single line: `OK: <modified/created files>`.

## Flutter & Chart State Discipline
- **Zero Collection Allocation in `build()`:** Never pass `.toList()` or newly constructed lists/maps into child widgets inside `build()`. Cache derived lists in `State` and update them only when the underlying data changes so `identical()` checks in `didUpdateWidget` remain valid.
- **Preserve Viewport on Parent Rebuilds:** `ChartPaneWidget.didUpdateWidget` must never overwrite `_viewport.startIndex` or `_viewport.endIndex` during hover, cursor-sync, or order-state updates. Only re-anchor the right edge on initial mount, explicit timeframe switches, or replay bar advances when already pinned to the right edge.
- **Arena-Free Chart Pointers:** Keep chart pan, pinch-zoom, and touch long-press inside the single `Listener` pointer map in `chart_pane_widget.dart` rather than stacking competing `GestureDetector` recognizers.
