import 'dart:convert';
import 'dart:io';

import '../models/trading_session.dart';

/// JSON-file persistence for the sessions canvas.
///
/// The catalogue lives at `<storageDir>/sessions.json` and is written with an
/// atomic temp-file + rename so a crash mid-write never corrupts the file.
/// IO is lazy: the constructor performs no filesystem work, and a missing file
/// simply yields an empty list.
class SessionStore {
  static const String fileName = 'sessions.json';

  static const double cardWidth = 248.0;
  static const double cardHeight = 148.0;
  static const double horizontalGap = 36.0;
  static const double verticalGap = 64.0;
  static const double originX = 48.0;
  static const double originY = 48.0;

  final Directory storageDir;

  SessionStore(this.storageDir);

  File get _file =>
      File('${storageDir.path}${Platform.pathSeparator}$fileName');

  Future<List<TradingSession>> loadAll() async {
    final File f = _file;
    if (!await f.exists()) return <TradingSession>[];
    final String raw = await f.readAsString();
    if (raw.trim().isEmpty) return <TradingSession>[];
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) return <TradingSession>[];
    final dynamic list = decoded['sessions'];
    if (list is! List) return <TradingSession>[];
    final List<TradingSession> out = <TradingSession>[];
    for (final dynamic e in list) {
      if (e is Map) {
        out.add(TradingSession.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  Future<void> saveAll(List<TradingSession> sessions) async {
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    final File target = _file;
    final File tmp = File('${target.path}.tmp');
    final Map<String, dynamic> data = <String, dynamic>{
      'version': 1,
      'sessions': sessions.map((s) => s.toJson()).toList(),
    };
    await tmp.writeAsString(jsonEncode(data));
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    }
  }

  Future<void> upsert(TradingSession session) async {
    final List<TradingSession> all = await loadAll();
    final int idx = all.indexWhere((s) => s.id == session.id);
    if (idx == -1) {
      all.add(session);
    } else {
      all[idx] = session;
    }
    await saveAll(all);
  }

  /// Removes [sessionId] only if no other session forks from it.
  Future<void> deleteLeaf(String sessionId) async {
    final List<TradingSession> all = await loadAll();
    final bool hasChild = all.any((s) => s.parentId == sessionId);
    if (hasChild) {
      throw StateError(
        'Cannot delete session $sessionId: it still has child sessions.',
      );
    }
    final int before = all.length;
    all.removeWhere((s) => s.id == sessionId);
    if (all.length == before) return;
    await saveAll(all);
  }

  /// Deterministically arranges root trees side-by-side and nests forks
  /// vertically below their parents without overlaps.
  List<TradingSession> autoLayout(List<TradingSession> sessions) {
    if (sessions.isEmpty) return <TradingSession>[];

    final Map<String, TradingSession> byId = <String, TradingSession>{
      for (final TradingSession s in sessions) s.id: s,
    };
    final Map<String, List<TradingSession>> children =
        <String, List<TradingSession>>{};
    final List<TradingSession> roots = <TradingSession>[];
    for (final TradingSession s in sessions) {
      final String? pid = s.parentId;
      if (pid == null || !byId.containsKey(pid)) {
        roots.add(s);
      } else {
        children.putIfAbsent(pid, () => <TradingSession>[]).add(s);
      }
    }

    int byCreated(TradingSession a, TradingSession b) {
      final int c = a.createdAt.compareTo(b.createdAt);
      return c != 0 ? c : a.id.compareTo(b.id);
    }

    roots.sort(byCreated);
    for (final List<TradingSession> list in children.values) {
      list.sort(byCreated);
    }

    final Map<String, _Pos> positions = <String, _Pos>{};

    double layout(TradingSession s, double left, double top) {
      final List<TradingSession> kids =
          children[s.id] ?? const <TradingSession>[];
      if (kids.isEmpty) {
        positions[s.id] = _Pos(left, top);
        return cardWidth;
      }
      double childLeft = left;
      for (final TradingSession kid in kids) {
        final double w = layout(kid, childLeft, top + cardHeight + verticalGap);
        childLeft += w + horizontalGap;
      }
      final double span = childLeft - horizontalGap - left;
      final double width = span > cardWidth ? span : cardWidth;
      positions[s.id] = _Pos(left + span / 2 - cardWidth / 2, top);
      return width;
    }

    double cursorX = originX;
    for (final TradingSession root in roots) {
      final double w = layout(root, cursorX, originY);
      cursorX += w + horizontalGap * 2;
    }

    return sessions.map((TradingSession s) {
      final _Pos? p = positions[s.id];
      return p == null ? s : s.copyWith(canvasX: p.x, canvasY: p.y);
    }).toList();
  }
}

class _Pos {
  final double x;
  final double y;
  const _Pos(this.x, this.y);
}
