// Pure Dart dataset metadata (no Flutter / dart:ui imports).
class DatasetMetadata {
  final String sha256;
  final String name;
  final int barCount;
  final DateTime firstTime;
  final DateTime lastTime;
  final DateTime importedAt;
  final int binSizeBytes;
  final List<String> sessionIds;

  const DatasetMetadata({
    required this.sha256,
    required this.name,
    required this.barCount,
    required this.firstTime,
    required this.lastTime,
    required this.importedAt,
    required this.binSizeBytes,
    this.sessionIds = const [],
  });

  DatasetMetadata copyWith({
    String? sha256,
    String? name,
    int? barCount,
    DateTime? firstTime,
    DateTime? lastTime,
    DateTime? importedAt,
    int? binSizeBytes,
    List<String>? sessionIds,
  }) {
    return DatasetMetadata(
      sha256: sha256 ?? this.sha256,
      name: name ?? this.name,
      barCount: barCount ?? this.barCount,
      firstTime: firstTime ?? this.firstTime,
      lastTime: lastTime ?? this.lastTime,
      importedAt: importedAt ?? this.importedAt,
      binSizeBytes: binSizeBytes ?? this.binSizeBytes,
      sessionIds: sessionIds ?? this.sessionIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'sha256': sha256,
        'name': name,
        'barCount': barCount,
        'firstTime': firstTime.toIso8601String(),
        'lastTime': lastTime.toIso8601String(),
        'importedAt': importedAt.toIso8601String(),
        'binSizeBytes': binSizeBytes,
        'sessionIds': sessionIds,
      };

  factory DatasetMetadata.fromJson(Map<String, dynamic> json) {
    return DatasetMetadata(
      sha256: json['sha256'] as String,
      name: json['name'] as String,
      barCount: json['barCount'] as int,
      firstTime: DateTime.parse(json['firstTime'] as String),
      lastTime: DateTime.parse(json['lastTime'] as String),
      importedAt: DateTime.parse(json['importedAt'] as String),
      binSizeBytes: json['binSizeBytes'] as int,
      sessionIds: (json['sessionIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );
  }
}
