import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:trading_lab/domain/data/binary_candle_store.dart';
import 'package:trading_lab/domain/models/candle.dart';

void main() {
  late Directory tmpRoot;
  late BinaryCandleStore store;

  setUp(() {
    tmpRoot = Directory.systemTemp.createTempSync('tlab_store_test');
    store = BinaryCandleStore(
      Directory('${tmpRoot.path}${Platform.pathSeparator}datasets'),
    );
  });

  tearDown(() {
    if (tmpRoot.existsSync()) tmpRoot.deleteSync(recursive: true);
  });

  File writeCsv(String name, String content) {
    final File f = File('${tmpRoot.path}${Platform.pathSeparator}$name');
    f.writeAsStringSync(content);
    return f;
  }

  test('imports CSV with header, missing volume and parses OHLCV', () async {
    final File csv = writeCsv('a.csv', 'timestamp,open,high,low,close\n'
        '2026-01-01 09:30,100,101,99,100.5\n'
        '2026-01-01 09:31,100.5,102,100,101\n'
        '2026-01-01 09:32,101,103,100.5,102\n');

    final DatasetImportResult res = await store.importCsvFile(csv.path);
    expect(res.deduplicated, isFalse);
    expect(res.metadata.barCount, 3);
    expect(res.metadata.binSizeBytes, BinaryCandleStore.headerBytes + 3 * 48);
    expect(res.metadata.firstTime, DateTime.utc(2026, 1, 1, 9, 30));
    expect(res.metadata.lastTime, DateTime.utc(2026, 1, 1, 9, 32));

    final List<Candle> candles = store.readRange(res.metadata.sha256);
    expect(candles, hasLength(3));
    expect(candles.first.open, 100);
    expect(candles.first.high, 101);
    expect(candles.first.low, 99);
    expect(candles.first.close, 100.5);
    expect(candles.first.volume, 0.0);
    expect(candles[2].close, 102);
  });

  test('parses semicolon delimiter and dot-separated timestamps', () async {
    final File csv = writeCsv(
      'dot.csv',
      '2026.01.02 09:30;100;101;99;100.5;1234\n'
      '2026.01.02 09:31;100.5;102;100;101;5678\n',
    );
    final DatasetImportResult res = await store.importCsvFile(csv.path);
    final List<Candle> candles = store.readRange(res.metadata.sha256);
    expect(candles, hasLength(2));
    expect(candles.first.time, DateTime.utc(2026, 1, 2, 9, 30));
    expect(candles.first.volume, 1234);
    expect(candles[1].volume, 5678);
  });

  test('parses Unix seconds and milliseconds timestamps', () async {
    final File csv = writeCsv('unix.csv', '1700000000,10,11,9,10.5\n'
        '1700000060000,10.5,12,10,11.5\n');
    final DatasetImportResult res = await store.importCsvFile(csv.path);
    final List<Candle> candles = store.readRange(res.metadata.sha256);
    expect(candles, hasLength(2));
    expect(
      candles.first.time,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
    expect(
      candles[1].time,
      DateTime.fromMillisecondsSinceEpoch(1700000060000, isUtc: true),
    );
  });

  test('deduplicates identical content via SHA-256', () async {
    const String content = '2026-01-01 09:30,100,101,99,100.5\n'
        '2026-01-01 09:31,100.5,102,100,101\n';
    final File a = writeCsv('one.csv', content);
    final File b = writeCsv('two.csv', content);

    final DatasetImportResult first = await store.importCsvFile(a.path);
    final DatasetImportResult second = await store.importCsvFile(b.path);

    expect(first.deduplicated, isFalse);
    expect(second.deduplicated, isTrue);
    expect(second.metadata.sha256, first.metadata.sha256);
    expect(store.listDatasets(), hasLength(1));
  });

  test('readRange slices with correct O(1) offset accuracy', () async {
    final StringBuffer sb = StringBuffer('time,o,h,l,c,v\n');
    for (int i = 0; i < 10; i++) {
      sb.writeln(
        '2026-01-01 09:${(30 + i).toString().padLeft(2, '0')},'
        '${100 + i},${101 + i},${99 + i},${100.5 + i},${1000 + i}',
      );
    }
    final File csv = writeCsv('range.csv', sb.toString());
    final DatasetImportResult res = await store.importCsvFile(csv.path);

    final List<Candle> slice = store.readRange(
      res.metadata.sha256,
      startIndex: 3,
      count: 4,
    );
    expect(slice, hasLength(4));
    expect(slice.first.index, 3);
    expect(slice.first.open, 103);
    expect(slice.first.close, 103.5);
    expect(slice.first.volume, 1003);
    expect(slice.last.index, 6);
    expect(slice.last.open, 106);
  });

  test('protected deletion throws while in use and succeeds when forced',
      () async {
    final File csv = writeCsv('del.csv', '2026-01-01 09:30,1,2,0,1\n');
    final DatasetImportResult res = await store.importCsvFile(csv.path);
    final String sha = res.metadata.sha256;

    store.attachSession(sha, 'sess-1');
    expect(
      () => store.deleteDataset(sha),
      throwsA(isA<DatasetInUseException>()),
    );

    expect(store.listDatasets().single.sessionIds, contains('sess-1'));

    store.deleteDataset(sha, force: true);
    expect(store.listDatasets(), isEmpty);

    store.detachSession(sha, 'sess-1');
  });
}
