import 'package:flutter/material.dart';

import '../../../domain/models/indicator.dart';
import '../../../domain/models/timeframe.dart';

/// Recursive binary tree describing how chart panes are tiled.
sealed class TilingNode {
  final String id;

  const TilingNode({required this.id});

  /// Replaces the [PaneNode] with [targetPaneId] by a [SplitNode] whose
  /// `first` is the original pane and whose `second` is a fresh pane using
  /// [newTimeframe]. Returns an unchanged tree if the pane is not found.
  TilingNode splitPane(String targetPaneId, Axis direction, Timeframe newTimeframe) {
    final TilingNode self = this;
    if (self is PaneNode) {
      if (self.id != targetPaneId) return self;
      return SplitNode(
        id: _newNodeId(),
        direction: direction,
        ratio: 0.5,
        first: self,
        second: PaneNode(
          id: _newNodeId(),
          timeframe: newTimeframe,
          indicators: self.indicators,
          showVolume: self.showVolume,
        ),
      );
    }
    return self;
  }

  /// Removes the [PaneNode] with [targetPaneId] and collapses its parent
  /// split to the surviving sibling. Returns `this` when the root is the
  /// only pane (or the target cannot be found).
  TilingNode closePane(String targetPaneId) {
    final TilingNode self = this;
    if (self is PaneNode) return self;
    return self;
  }

  /// Applies [updater] to the [PaneNode] with [targetPaneId].
  TilingNode updatePane(String targetPaneId, PaneNode Function(PaneNode) updater) {
    final TilingNode self = this;
    if (self is PaneNode) {
      return self.id == targetPaneId ? updater(self) : self;
    }
    return self;
  }

  /// Updates the split ratio of the [SplitNode] with [splitId].
  TilingNode updateSplitRatio(String splitId, double newRatio) => this;
}

class SplitNode extends TilingNode {
  /// [Axis.horizontal] = Split Right, [Axis.vertical] = Split Down.
  final Axis direction;
  final double ratio;
  final TilingNode first;
  final TilingNode second;

  SplitNode({
    required super.id,
    required this.direction,
    this.ratio = 0.5,
    required this.first,
    required this.second,
  })  : assert(ratio >= 0.15 && ratio <= 0.85);

  @override
  TilingNode splitPane(String targetPaneId, Axis direction, Timeframe newTimeframe) {
    return SplitNode(
      id: id,
      direction: this.direction,
      ratio: ratio,
      first: first.splitPane(targetPaneId, direction, newTimeframe),
      second: second.splitPane(targetPaneId, direction, newTimeframe),
    );
  }

  @override
  TilingNode closePane(String targetPaneId) {
    if (first is PaneNode && first.id == targetPaneId) {
      return second;
    }
    if (second is PaneNode && second.id == targetPaneId) {
      return first;
    }
    return SplitNode(
      id: id,
      direction: direction,
      ratio: ratio,
      first: first.closePane(targetPaneId),
      second: second.closePane(targetPaneId),
    );
  }

  @override
  TilingNode updatePane(String targetPaneId, PaneNode Function(PaneNode) updater) {
    return SplitNode(
      id: id,
      direction: direction,
      ratio: ratio,
      first: first.updatePane(targetPaneId, updater),
      second: second.updatePane(targetPaneId, updater),
    );
  }

  @override
  TilingNode updateSplitRatio(String splitId, double newRatio) {
    final double clamped = newRatio.clamp(0.15, 0.85).toDouble();
    if (id == splitId) {
      return SplitNode(
        id: id,
        direction: direction,
        ratio: clamped,
        first: first,
        second: second,
      );
    }
    return SplitNode(
      id: id,
      direction: direction,
      ratio: ratio,
      first: first.updateSplitRatio(splitId, clamped),
      second: second.updateSplitRatio(splitId, clamped),
    );
  }
}

class PaneNode extends TilingNode {
  final Timeframe timeframe;
  final List<IndicatorConfig> indicators;
  final bool showVolume;

  const PaneNode({
    required super.id,
    this.timeframe = Timeframe.m15,
    this.indicators = IndicatorConfig.defaults,
    this.showVolume = false,
  });

  PaneNode copyWith({
    Timeframe? timeframe,
    List<IndicatorConfig>? indicators,
    bool? showVolume,
  }) {
    return PaneNode(
      id: id,
      timeframe: timeframe ?? this.timeframe,
      indicators: indicators ?? this.indicators,
      showVolume: showVolume ?? this.showVolume,
    );
  }
}

int _nodeCounter = 0;
String _newNodeId() => 'node-${_nodeCounter++}';

/// True when the tree contains at least one [SplitNode] (i.e. the pane is
/// not the only one on screen and can be closed).
bool treeHasSplit(TilingNode node) {
  final TilingNode n = node;
  if (n is SplitNode) return true;
  return false;
}
