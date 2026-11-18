# AGENTS.md

## Commands
- Verify UI/all: `flutter analyze`
- Verify domain: `dart test`

## Architectural Boundaries
- `lib/domain/` and `test/domain/` MUST remain 100% pure Dart (no `package:flutter/...` or `dart:ui` imports).
- Text/icons painted over `theme.badgeBackground` MUST use `theme.badgeText`.
- Use `.withValues(alpha: ...)` instead of deprecated `.withOpacity(...)`.

## Execution & Output Contract
- Use targeted `SEARCH/REPLACE` edits on existing files; avoid full-file rewrites.
- Never leave empty `() {}` stubs or `// TODO` placeholders; if an interface is ambiguous, stop and ask in 1 line.
- Run `flutter analyze` (and `dart test` when `lib/domain/` or `test/` changes) before finishing.
- Skip narration; respond with a single line: `OK: <modified/created files>`.
