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
- Never run `git push`, `git commit --amend`, or destructive resets (`git reset --hard`, `git checkout -- .`) unless explicitly instructed by the user.
- Never stage or leave behind temporary patch files (`patch.txt`, `*.bak`, `*.orig`) or local data/media files (`*.csv`, `*.bin`, `*.png`).
- After every completed task, **only if `flutter analyze && dart test` exits 0**, inspect `git status -s`, stage only intended source/test/project files (`git add lib/ test/ pubspec.yaml ...`, never blind `git add -A` when untracked data/media files exist), and create a concise conventional commit (`feat:`, `fix:`, `refactor:`, `chore:`).
- If verification fails or no files changed, do NOT commit.

## Execution & Output Contract
- Use targeted `SEARCH/REPLACE` edits on existing files; avoid full-file rewrites.
- Never leave empty `() {}` stubs or `// TODO` placeholders; if an interface is ambiguous, stop and ask in 1 line.
- Run `flutter analyze && dart test` before committing and finishing.
- Skip narration; respond with a single line: `OK (<short-sha>): <modified/created files> — <commit message>`.

## Flutter & Chart State Discipline
- **Zero Collection Allocation in `build()`:** Never pass `.toList()` or newly constructed lists/maps into child widgets inside `build()`. Cache derived lists in `State` and update them only when the underlying data changes so `identical()` checks in `didUpdateWidget` remain valid.
- **Preserve Viewport on Parent Rebuilds:** `ChartPaneWidget.didUpdateWidget` must never overwrite `_viewport.startIndex` or `_viewport.endIndex` during hover, cursor-sync, or order-state updates. Only re-anchor the right edge on initial mount, explicit timeframe switches, or replay bar advances when already pinned to the right edge.
- **Arena-Free Chart Pointers:** Keep chart pan, pinch-zoom, and touch long-press inside the single `Listener` pointer map in `chart_pane_widget.dart` rather than stacking competing `GestureDetector` recognizers.
