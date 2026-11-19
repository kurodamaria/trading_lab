import 'package:flutter/material.dart';

import '../../../core/theme/chart_theme.dart';
import '../../../domain/models/candle.dart';
import '../../../domain/models/drawing.dart';
import '../../../domain/models/order.dart';
import '../../../domain/models/timeframe.dart';
import '../chart/chart_pane_widget.dart';
import 'tiling_node.dart';

/// Recursively renders a [TilingNode] tree: [PaneNode]s become chart panes,
/// [SplitNode]s become resizable layouts with 4px dividers.
class TilingTreeView extends StatelessWidget {
  final TilingNode node;
  final TilingNode? rootNode;
  final List<Candle> base1mCandles;
  final ChartTheme theme;
  final bool isDrawingPath;
  final List<CrossTimeframePath> paths;
  final CrossTimeframePath? activePath;
  final DateTimeRange? syncedCursorRange;
  final bool canClose;
  final ValueChanged<TilingNode> onTreeChanged;
  final ValueChanged<DateTimeRange?> onHoverRangeChanged;
  final void Function(ChartAnchor anchor) onAddPathPoint;
  final VoidCallback onFinishPath;
  final OpenPosition? openPosition;
  final List<PendingOrder> pendingOrders;
  final List<CompletedTrade> closedTrades;
  final OrderSide? pendingPlacementSide;
  final void Function(OrderSide side, double price)? onPlacePendingOrder;
  final ValueChanged<double>? onUpdateSl;
  final void Function(String orderId, double newPrice)? onUpdatePendingPrice;
  final ValueChanged<String>? onCancelPendingOrder;
  final String? selectedPathId;
  final int? selectedPointIndex;
  final void Function(String? pathId, int? pointIndex)? onSelectPath;
  final void Function(String pathId, int pointIndex, ChartAnchor newAnchor)?
      onUpdatePathPoint;
  final VoidCallback? onFocusRequested;
  final VoidCallback? onClosePosition;
  final VoidCallback? onRemoveSl;

  const TilingTreeView({
    super.key,
    required this.node,
    required this.base1mCandles,
    this.rootNode,
    required this.theme,
    required this.isDrawingPath,
    required this.paths,
    required this.activePath,
    required this.syncedCursorRange,
    required this.canClose,
    required this.onTreeChanged,
    required this.onHoverRangeChanged,
    required this.onAddPathPoint,
    required this.onFinishPath,
    this.openPosition,
    this.pendingOrders = const [],
    this.closedTrades = const [],
    this.pendingPlacementSide,
    this.onPlacePendingOrder,
    this.onUpdateSl,
    this.onUpdatePendingPrice,
    this.onCancelPendingOrder,
    this.selectedPathId,
    this.selectedPointIndex,
    this.onSelectPath,
    this.onUpdatePathPoint,
    this.onFocusRequested,
    this.onClosePosition,
    this.onRemoveSl,
  });

  @override
  Widget build(BuildContext context) {
    final TilingNode root = rootNode ?? node;
    final TilingNode n = node;
    if (n is PaneNode) {
      return ChartPaneWidget(
        node: n,
        base1mCandles: base1mCandles,
        theme: theme,
        isDrawingPath: isDrawingPath,
        paths: paths,
        activePath: activePath,
        syncedCursorRange: syncedCursorRange,
        canClose: canClose,
        onUpdatePane: (p) => onTreeChanged(root.updatePane(p.id, (_) => p)),
        onSplit: (axis) => onTreeChanged(
          root.splitPane(n.id, axis, _suggestTimeframe(n.timeframe)),
        ),
        onClose: () => onTreeChanged(root.closePane(n.id)),
        onHoverRangeChanged: onHoverRangeChanged,
        onAddPathPoint: onAddPathPoint,
        onFinishPath: onFinishPath,
        openPosition: openPosition,
        pendingOrders: pendingOrders,
        closedTrades: closedTrades,
        pendingPlacementSide: pendingPlacementSide,
        onPlacePendingOrder: onPlacePendingOrder,
        onUpdateSl: onUpdateSl,
        onUpdatePendingPrice: onUpdatePendingPrice,
        onCancelPendingOrder: onCancelPendingOrder,
        selectedPathId: selectedPathId,
        selectedPointIndex: selectedPointIndex,
        onSelectPath: onSelectPath,
        onUpdatePathPoint: onUpdatePathPoint,
        onFocusRequested: onFocusRequested,
        onClosePosition: onClosePosition,
        onRemoveSl: onRemoveSl,
      );
    }
    if (n is SplitNode) {
      final bool horizontal = n.direction == Axis.horizontal;
      return LayoutBuilder(
        builder: (context, constraints) {
          final double total = horizontal
              ? constraints.maxWidth
              : constraints.maxHeight;
          final double usable = total - 16.0;
          final double firstSize =
              (usable * n.ratio).clamp(0.0, usable).toDouble();

          Widget subtree(TilingNode child) => TilingTreeView(
                node: child,
                rootNode: root,
                base1mCandles: base1mCandles,
                theme: theme,
                isDrawingPath: isDrawingPath,
                paths: paths,
                activePath: activePath,
                syncedCursorRange: syncedCursorRange,
                canClose: canClose,
                onTreeChanged: onTreeChanged,
                onHoverRangeChanged: onHoverRangeChanged,
                onAddPathPoint: onAddPathPoint,
                onFinishPath: onFinishPath,
                openPosition: openPosition,
                pendingOrders: pendingOrders,
                closedTrades: closedTrades,
                pendingPlacementSide: pendingPlacementSide,
                onPlacePendingOrder: onPlacePendingOrder,
                onUpdateSl: onUpdateSl,
                onUpdatePendingPrice: onUpdatePendingPrice,
                onCancelPendingOrder: onCancelPendingOrder,
                selectedPathId: selectedPathId,
                selectedPointIndex: selectedPointIndex,
                onSelectPath: onSelectPath,
                onUpdatePathPoint: onUpdatePathPoint,
                onFocusRequested: onFocusRequested,
                onClosePosition: onClosePosition,
                onRemoveSl: onRemoveSl,
              );

          final Widget divider = _Divider(
            horizontal: horizontal,
            theme: theme,
            onDragDelta: (d) {
              if (usable <= 0) return;
              final RenderBox? box = context.findRenderObject() as RenderBox?;
              if (box == null) return;
              final Offset local = box.globalToLocal(d.globalPosition);
              final double pointerPos = horizontal ? local.dx : local.dy;
              final double newRatio =
                  ((pointerPos - 8.0) / usable).clamp(0.05, 0.95);
              onTreeChanged(root.updateSplitRatio(n.id, newRatio));
            },
          );

          final List<Widget> children = horizontal
              ? [
                  SizedBox(width: firstSize, child: subtree(n.first)),
                  divider,
                  Expanded(child: subtree(n.second)),
                ]
              : [
                  SizedBox(height: firstSize, child: subtree(n.first)),
                  divider,
                  Expanded(child: subtree(n.second)),
                ];

          return horizontal
              ? Row(children: children)
              : Column(children: children);
        },
      );
    }
    return const SizedBox.shrink();
  }
}

class _Divider extends StatefulWidget {
  final bool horizontal;
  final ChartTheme theme;
  final ValueChanged<DragUpdateDetails> onDragDelta;

  const _Divider({
    required this.horizontal,
    required this.theme,
    required this.onDragDelta,
  });

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final ChartTheme theme = widget.theme;
    final bool horizontal = widget.horizontal;
    final bool active = _isHovered || _isDragging;

    final double width = horizontal ? 16.0 : double.infinity;
    final double height = horizontal ? double.infinity : 16.0;

    final Widget hairline = Container(
      width: horizontal ? (active ? 2.0 : 1.0) : double.infinity,
      height: horizontal ? double.infinity : (active ? 2.0 : 1.0),
      color: active
          ? theme.activePillBackground
          : theme.border.withValues(alpha: 0.65),
    );

    final Widget grip = Container(
      width: horizontal ? 2.0 : 24.0,
      height: horizontal ? 24.0 : 2.0,
      decoration: BoxDecoration(
        color: active
            ? theme.activePillBackground
            : theme.textSecondary.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(1.0),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: horizontal ? (_) => _setDragging(true) : null,
      onHorizontalDragUpdate: horizontal ? widget.onDragDelta : null,
      onHorizontalDragEnd: horizontal ? (_) => _setDragging(false) : null,
      onHorizontalDragCancel: horizontal ? () => _setDragging(false) : null,
      onVerticalDragStart: horizontal ? null : (_) => _setDragging(true),
      onVerticalDragUpdate: horizontal ? null : widget.onDragDelta,
      onVerticalDragEnd: horizontal ? null : (_) => _setDragging(false),
      onVerticalDragCancel: horizontal ? null : () => _setDragging(false),
      child: MouseRegion(
        cursor: horizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: SizedBox(
          width: width,
          height: height,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: active
                ? theme.activePillBackground.withValues(alpha: 0.18)
                : Colors.transparent,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(alignment: Alignment.center, child: hairline),
                Align(alignment: Alignment.center, child: grip),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _setDragging(bool value) {
    if (_isDragging == value) return;
    setState(() => _isDragging = value);
  }
}

Timeframe _suggestTimeframe(Timeframe tf) {
  final int fourX = tf.minutes * 4;
  for (final t in Timeframe.values) {
    if (t.minutes >= fourX) return t;
  }
  return Timeframe.d1;
}
