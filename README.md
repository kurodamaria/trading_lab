# trading_lab

A low-latency, multi-timeframe bar-by-bar price action replay and execution workstation built in Flutter with custom `CustomPainter` rendering and a minimalist Newsprint editorial aesthetic.

## Features

- **Recursive Tiling Window Manager:** Split panes horizontally or vertically into arbitrary multi-timeframe layouts with 1:1 pointer-synced dividers, independent timeframes, EMA overlays (`20`, `50`, `200`), and volume histograms.
- **Cross-Timeframe Synchronization:** Hovering any candle illuminates its exact `DateTimeRange` interval across all open panes (mapping lower-timeframe bars into parent higher-timeframe candles and vice versa) alongside synchronized crosshairs.
- **Cross-Timeframe Path Drawing:** Zero-latency vector trend/path annotations anchored in `(time, price)` space that project accurately across every timeframe pane with selectable, draggable control points.
- **Bar-by-Bar Replay & Order Execution:** Step forward/backward bar-by-bar, place market or pending limit/stop orders, drag stop-loss (`SL`) levels directly on the chart with dynamic profit/loss color coding, and close positions or cancel orders via inline `│ ✕` badges.
- **Session Telemetry (`Stats`):** Dedicated analytics view featuring session KPIs (win rate, cumulative return, total R, Sharpe ratio, max drawdown, blunder count), an equity curve canvas, trade ledger, and one-click CSV export.

## Project Structure

```text
lib/
├── core/theme/          # ChartTheme (NYT Newsprint palette & typography tokens)
├── domain/
│   ├── engine/          # BarAggregator, ReplayEngine, TelemetryCalculator
│   └── models/          # Candle, Timeframe, Order/Position/Trade, CrossTimeframePath
└── features/workstation/
    ├── chart/           # ChartPaneWidget, ChartViewport, Main/Price/Time CustomPainters
    ├── stats/           # StatsPage (KPI grid, equity curve, trade ledger)
    └── tiling/          # TilingNode binary tree & TilingTreeView splitter layout

```

## Getting Started

```bash
# Run the desktop application (Linux / Windows / macOS)
flutter run -d linux   # or -d windows / -d macos

# Static analysis and unit tests
flutter analyze && dart test

```

```

Write it to `README.md` and commit with:

```bash
cat << 'EOF' > README.md
# trading_lab

A low-latency, multi-timeframe bar-by-bar price action replay and execution workstation built in Flutter with custom `CustomPainter` rendering and a minimalist Newsprint editorial aesthetic.

## Features

- **Recursive Tiling Window Manager:** Split panes horizontally or vertically into arbitrary multi-timeframe layouts with 1:1 pointer-synced dividers, independent timeframes, EMA overlays (`20`, `50`, `200`), and volume histograms.
- **Cross-Timeframe Synchronization:** Hovering any candle illuminates its exact `DateTimeRange` interval across all open panes (mapping lower-timeframe bars into parent higher-timeframe candles and vice versa) alongside synchronized crosshairs.
- **Cross-Timeframe Path Drawing:** Zero-latency vector trend/path annotations anchored in `(time, price)` space that project accurately across every timeframe pane with selectable, draggable control points.
- **Bar-by-Bar Replay & Order Execution:** Step forward/backward bar-by-bar, place market or pending limit/stop orders, drag stop-loss (`SL`) levels directly on the chart with dynamic profit/loss color coding, and close positions or cancel orders via inline `│ ✕` badges.
- **Session Telemetry (`Stats`):** Dedicated analytics view featuring session KPIs (win rate, cumulative return, total R, Sharpe ratio, max drawdown, blunder count), an equity curve canvas, trade ledger, and one-click CSV export.

## Project Structure

```text
lib/
├── core/theme/          # ChartTheme (NYT Newsprint palette & typography tokens)
├── domain/
│   ├── engine/          # BarAggregator, ReplayEngine, TelemetryCalculator
│   └── models/          # Candle, Timeframe, Order/Position/Trade, CrossTimeframePath
└── features/workstation/
    ├── chart/           # ChartPaneWidget, ChartViewport, Main/Price/Time CustomPainters
    ├── stats/           # StatsPage (KPI grid, equity curve, trade ledger)
    └── tiling/          # TilingNode binary tree & TilingTreeView splitter layout

```

## Getting Started

```bash
# Run the desktop application (Linux / Windows / macOS)
flutter run -d linux   # or -d windows / -d macos

# Static analysis and unit tests
flutter analyze && dart test

```
