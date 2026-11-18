import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/candle.dart';
import 'dataset_metadata.dart';

/// Thrown when deleting a dataset that is still referenced by sessions and
/// `force` was not set.
class DatasetInUseException implements Exception {
  final String sha256;
  final List<String> sessionIds;

  const DatasetInUseException(this.sha256, this.sessionIds);

  @override
  String toString() =>
      'Dataset $sha256 is in use by ${sessionIds.length} session(s)';
}

class DatasetImportResult {  final DatasetMetadata metadata;
  final bool deduplicated;

  const DatasetImportResult({
    required this.metadata,
    required this.deduplicated,
  });
}

/// Content-addressed, fixed-width binary store for 1-minute candles.
///
/// Layout: 32-byte header + `48 bytes/bar`, little-endian.
///   bytes  0..3  : ASCII "TLAB"
///   bytes  4..7  : Uint32 version = 1
///   bytes  8..15 : Uint64 barCount
///   bytes 16..23 : Int64  firstTimeMs
///   bytes 24..31 : Int64  lastTimeMs
///   record i     : Int64 timeMs, Float64 open/high/low/close/volume
class BinaryCandleStore {
  static const int headerBytes = 32;
  static const int recordBytes = 48;
  static const int version = 1;

  final Directory storageDir;

  BinaryCandleStore(this.storageDir) {
    if (!storageDir.existsSync()) {
      storageDir.createSync(recursive: true);
    }
  }

  File _binFile(String sha256) =>
      File('${storageDir.path}${Platform.pathSeparator}$sha256.bin');

  File get _catalogFile =>
      File('${storageDir.path}${Platform.pathSeparator}catalog.json');

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------
  Future<DatasetImportResult> importCsvFile(
    String csvPath, {
    String? displayName,
  }) {
    return Isolate.run(
      () => _importCsvSync(csvPath, displayName ?? _basename(csvPath)),
    );
  }

  static String _basename(String path) {
    final int i = math.max(
      path.lastIndexOf('/'),
      path.lastIndexOf('\\'),
    );
    return i >= 0 ? path.substring(i + 1) : path;
  }

  DatasetImportResult _importCsvSync(String csvPath, String displayName) {
    final Directory dir = Directory(storageDir.path);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final String tmpPath =
        '${dir.path}${Platform.pathSeparator}$displayName.${DateTime.now().microsecondsSinceEpoch}.tmp';
    final File tmp = File(tmpPath);
    final RandomAccessFile raf = tmp.openSync(mode: FileMode.write);

    final _DigestSink digestSink = _DigestSink();
    final ByteConversionSink hasher = sha256.startChunkedConversion(digestSink);

    int barCount = 0;
    int firstMs = 0;
    int lastMs = 0;
    final List<int> out = <int>[];
    final ByteData rec = ByteData(recordBytes);

    final List<int> pending = <int>[];
    bool headerChecked = false;
    List<int> delimiter = const <int>[0x2C]; // ','

    void flushIfNeeded() {
      if (out.length >= 1 << 16) {
        raf.writeFromSync(out);
        out.clear();
      }
    }

    void writeRecord(int timeMs, List<double> ohlcv) {
      rec.setInt64(0, timeMs, Endian.little);
      rec.setFloat64(8, ohlcv[0], Endian.little);
      rec.setFloat64(16, ohlcv[1], Endian.little);
      rec.setFloat64(24, ohlcv[2], Endian.little);
      rec.setFloat64(32, ohlcv[3], Endian.little);
      rec.setFloat64(40, ohlcv[4], Endian.little);
      out.addAll(rec.buffer.asUint8List());
      barCount++;
      if (barCount == 1) firstMs = timeMs;
      lastMs = timeMs;
      flushIfNeeded();
    }

    void handleLine(String line) {
      if (line.isEmpty) return;
      final List<String> cells = line.split(
        String.fromCharCodes(delimiter),
      );
      if (cells.length < 5) return;

      final int? timeMs = _parseTime(cells[0].trim());
      if (timeMs == null) {
        // Likely a header row.
        return;
      }
      final double? open = _parseDouble(cells[1]);
      final double? high = _parseDouble(cells[2]);
      final double? low = _parseDouble(cells[3]);
      final double? close = _parseDouble(cells[4]);
      if (open == null || high == null || low == null || close == null) return;
      final double volume =
          cells.length > 5 ? (_parseDouble(cells[5]) ?? 0.0) : 0.0;
      writeRecord(timeMs, <double>[open, high, low, close, volume]);
    }

    raf.setPositionSync(headerBytes);

    for (final List<int> chunk in _readAllSync(csvPath)) {
      hasher.add(chunk);
      pending.addAll(chunk);
      int start = 0;
      for (int i = 0; i < pending.length; i++) {
        if (pending[i] == 0x0A) {
          final List<int> lineBytes = pending.sublist(start, i);
          start = i + 1;
          if (!headerChecked) {
            headerChecked = true;
            delimiter = _detectDelimiter(lineBytes);
            if (lineBytes.isNotEmpty &&
                lineBytes.last == 0x0D) {
              lineBytes.removeLast();
            }
          }
          final String line =
              utf8.decode(lineBytes, allowMalformed: true).replaceAll('\r', '');
          handleLine(line);
        }
      }
      if (start > 0) pending.removeRange(0, start);
    }
    if (pending.isNotEmpty) {
      handleLine(utf8.decode(pending, allowMalformed: true).replaceAll('\r', ''));
    }

    if (out.isNotEmpty) {
      raf.writeFromSync(out);
      out.clear();
    }

    // Write header.
    final ByteData header = ByteData(headerBytes);
    header.setUint8(0, 0x54); // T
    header.setUint8(1, 0x4C); // L
    header.setUint8(2, 0x41); // A
    header.setUint8(3, 0x42); // B
    header.setUint32(4, version, Endian.little);
    header.setUint64(8, barCount, Endian.little);
    header.setInt64(16, firstMs, Endian.little);
    header.setInt64(24, lastMs, Endian.little);
    raf.setPositionSync(0);
    raf.writeFromSync(header.buffer.asUint8List());
    raf.flushSync();
    raf.closeSync();

    hasher.close();
    final String sha = digestSink.digest.toString();

    final File finalFile = _binFile(sha);
    final DatasetMetadata? existing = _findInCatalog(sha);

    if (finalFile.existsSync() || existing != null) {
      if (tmp.existsSync()) tmp.deleteSync();
      if (existing == null) {
        final DatasetMetadata meta = _buildMetadata(
          sha: sha,
          name: displayName,
          barCount: barCount,
          firstMs: firstMs,
          lastMs: lastMs,
          binSizeBytes: finalFile.existsSync() ? finalFile.lengthSync() : 0,
        );
        _upsertCatalog(meta);
        return DatasetImportResult(metadata: meta, deduplicated: true);
      }
      return DatasetImportResult(metadata: existing, deduplicated: true);
    }

    tmp.renameSync(finalFile.path);
    final DatasetMetadata meta = _buildMetadata(
      sha: sha,
      name: displayName,
      barCount: barCount,
      firstMs: firstMs,
      lastMs: lastMs,
      binSizeBytes: finalFile.lengthSync(),
    );
    _upsertCatalog(meta);
    return DatasetImportResult(metadata: meta, deduplicated: false);
  }

  // Synchronous chunked read helper (import path runs inside an Isolate).
  Iterable<List<int>> _readAllSync(String path) sync* {
    final List<int> bytes = File(path).readAsBytesSync();
    const int chunk = 1 << 16;
    for (int i = 0; i < bytes.length; i += chunk) {
      yield bytes.sublist(i, math.min(i + chunk, bytes.length));
    }
  }

  static List<int> _detectDelimiter(List<int> lineBytes) {
    int commas = 0;
    int semis = 0;
    int tabs = 0;
    for (final int b in lineBytes) {
      if (b == 0x2C) commas++;
      if (b == 0x3B) semis++;
      if (b == 0x09) tabs++;
    }
    if (semis > commas && semis >= tabs) return const <int>[0x3B];
    if (tabs > commas && tabs > semis) return const <int>[0x09];
    return const <int>[0x2C];
  }

  static int? _parseTime(String raw) {
    if (raw.isEmpty) return null;
    // Pure integer: Unix seconds (<=10 digits) or milliseconds.
    final bool allDigits = RegExp(r'^\d+$').hasMatch(raw);
    if (allDigits) {
      final int v = int.parse(raw);
      if (raw.length >= 13) return v;
      return v * 1000;
    }

    final DateTime? isoRaw = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (isoRaw != null) return isoRaw.millisecondsSinceEpoch;
    if (raw.contains('.')) {
      final String dotNormalized =
          raw.replaceAll('.', '-').replaceFirst(' ', 'T');
      final DateTime? dotParsed = DateTime.tryParse(dotNormalized);
      if (dotParsed != null) return dotParsed.millisecondsSinceEpoch;
    }
    return null;
  }

  static double? _parseDouble(String raw) {
    final String s = raw.trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  DatasetMetadata _buildMetadata({
    required String sha,
    required String name,
    required int barCount,
    required int firstMs,
    required int lastMs,
    required int binSizeBytes,
  }) {
    return DatasetMetadata(
      sha256: sha,
      name: name,
      barCount: barCount,
      firstTime: DateTime.fromMillisecondsSinceEpoch(firstMs),
      lastTime: DateTime.fromMillisecondsSinceEpoch(lastMs),
      importedAt: DateTime.now(),
      binSizeBytes: binSizeBytes,
    );
  }

  // ---------------------------------------------------------------------------
  // Reading
  // ---------------------------------------------------------------------------
  List<Candle> readRange(String sha256, {int startIndex = 0, int? count}) {
    final RandomAccessFile raf = _binFile(sha256).openSync();
    try {
      final Uint8List header = raf.readSync(headerBytes);
      if (header.length < headerBytes ||
          header[0] != 0x54 ||
          header[1] != 0x4C ||
          header[2] != 0x41 ||
          header[3] != 0x42) {
        throw StateError('Invalid TLAB header for $sha256');
      }
      final ByteData hb = ByteData.sublistView(header);
      final int barCount = hb.getUint64(8, Endian.little);

      final int start = startIndex.clamp(0, barCount);
      int actual = count ?? (barCount - start);
      actual = actual.clamp(0, barCount - start);

      raf.setPositionSync(headerBytes + start * recordBytes);
      final Uint8List bytes = raf.readSync(actual * recordBytes);
      final ByteData bd = ByteData.sublistView(bytes);

      final List<Candle> out = <Candle>[];
      for (int i = 0; i < actual; i++) {
        final int base = i * recordBytes;
        final int timeMs = bd.getInt64(base, Endian.little);
        out.add(
          Candle(
            index: start + i,
            time: DateTime.fromMillisecondsSinceEpoch(timeMs),
            open: bd.getFloat64(base + 8, Endian.little),
            high: bd.getFloat64(base + 16, Endian.little),
            low: bd.getFloat64(base + 24, Endian.little),
            close: bd.getFloat64(base + 32, Endian.little),
            volume: bd.getFloat64(base + 40, Endian.little),
          ),
        );
      }
      return out;
    } finally {
      raf.closeSync();
    }
  }

  // ---------------------------------------------------------------------------
  // Catalog
  // ---------------------------------------------------------------------------
  List<DatasetMetadata> listDatasets() {
    final List<DatasetMetadata> all = _readCatalog();
    all.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return all;
  }

  List<DatasetMetadata> _readCatalog() {
    final File f = _catalogFile;
    if (!f.existsSync()) return <DatasetMetadata>[];
    final dynamic decoded = jsonDecode(f.readAsStringSync());
    if (decoded is! Map) return <DatasetMetadata>[];
    final dynamic datasets = decoded['datasets'];
    if (datasets is! List) return <DatasetMetadata>[];
    return datasets
        .map((e) => DatasetMetadata.fromJson(
              Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  void _writeCatalog(List<DatasetMetadata> list) {
    final Map<String, dynamic> data = <String, dynamic>{
      'datasets': list.map((e) => e.toJson()).toList(),
    };
    _catalogFile.writeAsStringSync(jsonEncode(data));
  }

  DatasetMetadata? _findInCatalog(String sha256) {
    for (final DatasetMetadata m in _readCatalog()) {
      if (m.sha256 == sha256) return m;
    }
    return null;
  }

  void _upsertCatalog(DatasetMetadata meta) {
    final List<DatasetMetadata> list = _readCatalog();
    final int idx = list.indexWhere((m) => m.sha256 == meta.sha256);
    if (idx == -1) {
      list.add(meta);
    } else {
      final List<String> sessions = list[idx].sessionIds;
      list[idx] = meta.copyWith(sessionIds: sessions);
    }
    _writeCatalog(list);
  }

  void attachSession(String sha256, String sessionId) {
    final List<DatasetMetadata> list = _readCatalog();
    final int idx = list.indexWhere((m) => m.sha256 == sha256);
    if (idx == -1) return;
    final List<String> sessions = List<String>.from(list[idx].sessionIds);
    if (!sessions.contains(sessionId)) sessions.add(sessionId);
    list[idx] = list[idx].copyWith(sessionIds: sessions);
    _writeCatalog(list);
  }

  void detachSession(String sha256, String sessionId) {
    final List<DatasetMetadata> list = _readCatalog();
    final int idx = list.indexWhere((m) => m.sha256 == sha256);
    if (idx == -1) return;
    final List<String> sessions = List<String>.from(list[idx].sessionIds)
      ..remove(sessionId);
    list[idx] = list[idx].copyWith(sessionIds: sessions);
    _writeCatalog(list);
  }

  void deleteDataset(String sha256, {bool force = false}) {
    final DatasetMetadata? meta = _findInCatalog(sha256);
    if (meta != null && meta.sessionIds.isNotEmpty && !force) {
      throw DatasetInUseException(sha256, meta.sessionIds);
    }
    final File bin = _binFile(sha256);
    if (bin.existsSync()) bin.deleteSync();

    final List<DatasetMetadata> list = _readCatalog()
      ..removeWhere((m) => m.sha256 == sha256);
    _writeCatalog(list);
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
