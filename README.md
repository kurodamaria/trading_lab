# TradingLab

A local-first, hypothesis-driven price-action replay workstation built with Flutter and custom `CustomPainter` rendering. TradingLab treats every trading hypothesis as an independent, reproducible unit test: a `Root` session establishes a baseline, and `Fork` sessions inherit its candidate entries to test a single change at a time.

There is no cloud sync, telemetry upload, brokerage integration, or external market feed. Everything runs locally and all state is stored on disk.

## Philosophy

- **One change per fork.** A session has a `SessionChangeType` of `root`, `entryFilter`, `exitRule`, or `oosValidation`. Forked sessions replay the parent's `CandidateEntry` list so hypotheses are compared apples-to-apples.
- **Anti-look-ahead by construction.** The `ReplayEngine` advances one 1-minute bar at a time and refuses to step back across an open position, active pending order, or closed-trade boundary.
- **Scale-invariant ideas, not pixel patterns.** Annotations are anchored in `(time, price)` space (`CrossTimeframePath`), so they project correctly across every timeframe pane.
- **Local-first.** Sessions, datasets, and preferences are plain files under the OS application-support directory. Corrupt files are quarantined and rebuilt where possible rather than crashing the app.

## Key Features

- **Multi-pane recursive tiling** (`SplitNode` / `PaneNode`) with per-pane timeframes, synchronized crosshairs/hover ranges, and cross-timeframe path annotations (`CrossTimeframePath`).
- **Anti-look-ahead 1-minute replay** (`ReplayEngine`) with cadence stepping at `1m`, `5m`, `15m`, and `1h`; market entries; pending limit/stop orders; draggable entry and stop-loss levels; paired pending-order stop-loss lines and risk brackets; and complete `OrderEvent` / `SlHistoryEntry` audit trails. Canceled and unfilled orders are retained as `CanceledOrder` records.
- **Customizable per-pane indicators** (`IndicatorConfig`): arbitrary-period `EMA` overlays and synchronized `RSI` oscillator sub-panes, added/edited through a `+ Ind` dialog and an interactive top-left legend (visibility, settings, remove). RSI uses Wilder smoothing.
- **Session tree canvas** (`SessionsPage`): pan/zoom an Obsidian-style canvas of draggable session cards with Bezier lineage connectors, fork/auto-layout, smart framing, and selection vs. active-practice indicators.
- **Dataset manager** (`DatasetsPage`): import CSV files, inspect bars, and manage stored datasets.
- **Telemetry and export** (`StatsPage`): KPIs, an interactive equity curve with drawdown shading and crosshair readout, trade ledger, unfilled-order table, fill-rate metric, and one-click CSV export.
- **Preferences** (`SettingsPage`): display timezone (including live preview), plus custom font family and font scale applied app-wide and to custom-painted chart text.

## Architecture & Local Storage

`lib/domain/` is pure Dart — it must never import `package:flutter/...` or `dart:ui`, keeping replay, aggregation, persistence, and models testable without a UI.

```text
lib/
├── core/theme/                 # ChartTheme (nytNewsprint palette, typography, fontScale)
├── domain/
│   ├── data/                   # BinaryCandleStore, SessionStore, DatasetMetadata
│   ├── engine/                 # BarAggregator, ReplayEngine, TelemetryCalculator
│   └── models/                 # Candle, Timeframe, Order/Position/Trade, Drawing,
│                               # DisplayTimezone, TradingSession, IndicatorConfig
└── features/workstation/
    ├── chart/                  # ChartPaneWidget, ChartViewport, painters, indicator dialogs
    ├── data/                   # DatasetsPage
    ├── sessions/               # SessionsPage, session dialogs
    ├── settings/               # SettingsPage
    ├── stats/                  # StatsPage
    └── tiling/                 # TilingNode tree + TilingTreeView splitters
```

### On-disk layout

All paths are relative to `getApplicationSupportDirectory()`.

```text
<support>/
├── datasets/
│   ├── <sha256>.bin            # content-addressed candle store
│   └── catalog.json            # dataset metadata catalog
├── sessions/
│   ├── sessions.json           # all TradingSession snapshots
│   └── active_session.txt      # id of the last active session
└── ui_settings.json            # customFontFamily + fontScale
```

- **`BinaryCandleStore`** stores 1-minute candles in `<sha256>.bin` as a 32-byte header followed by 48-byte little-endian records:
  - Header: `"TLAB"` magic, `uint32` version, `uint64` bar count, `int64` first timestamp, `int64` last timestamp.
  - Record: `int64` time (ms) + five `float64` values (`open`, `high`, `low`, `close`, `volume`).
  - Range reads seek directly to `header + startIndex * 48`, giving O(1) offset access. Imported files are SHA-256 hashed so identical CSVs deduplicate. `catalog.json` is written atomically (temp file + rename) and rebuilt from valid `.bin` headers if it becomes corrupt.
- **`SessionStore`** writes `sessions.json` atomically with temp-file + rename and serializes mutating operations through an internal write chain. Corrupt JSON is quarantined as `sessions.json.corrupt.<timestamp>`.
- **`ui_settings.json`** stores `{ "customFontFamily": string|null, "fontScale": number }`; invalid values fall back to the default font and `1.0`.

## Keyboard & Mouse Controls

Keyboard shortcuts are implemented in `lib/main.dart` and the chart/pane interaction logic in `lib/features/workstation/chart/chart_pane_widget.dart`.

| Input | Action |
| --- | --- |
| `→` / `←` | Step replay forward/back one cadence bar |
| `N` | Jump to the next candidate entry (forked sessions) |
| `L` | Toggle pending-buy placement |
| `Shift` + `L` | Toggle pending-sell placement |
| `P` | Toggle cross-timeframe path drawing |
| `Esc` | Cancel pending placement / finish the active path |
| `Delete` / `Backspace` | Remove the selected path or control point |
| `.` / Numpad `.` / `F` | Zoom to focus on the Sessions canvas (selected node, else all nodes) |

Mouse / touch:

- Wheel zooms at the cursor; pinch zooms on touch; drag pans. Both horizontal overscroll and zoom clamp keep at least three bars visible at either edge.
- Double-tap the chart to auto-fit price; double-tap the time axis to reset the view.
- Drag the price axis to scale vertically; drag the time axis to zoom horizontally.
- Drag stop-loss lines, pending entry lines, and paired pending SL lines directly on the chart.
- Right-click a pending order line or click its `│ ✕` badge to cancel it.
- Indicator legend rows reveal eye/settings/remove controls on hover; hovering the legend shields the chart crosshair. Legend values track the hovered chart bar, falling back to the latest bar.
- On the Sessions canvas: drag cards to reposition, double-click a card header/body to zoom to it, scroll/pinch to zoom, and drag empty space to pan.

## Development & Verification

Requires a Flutter SDK with Dart `^3.13.5`.

```bash
flutter pub get

# Desktop targets
flutter run -d linux
flutter run -d windows

# Static analysis
flutter analyze

# Tests (the project's tests use flutter_test)
flutter test

# Pure-Dart test runner (only for suites without flutter_test imports;
# the current tests import flutter_test, so use `flutter test`)
dart test
```

Dependencies are intentionally small: `crypto` for SHA-256 dataset identity, `file_picker` for CSV import, `path_provider` for the support directory, and `cupertino_icons`.
