class BlacklistEntry {
  const BlacklistEntry({
    required this.key,
    required this.type,
    required this.label,
    required this.createdAt,
    this.reason,
    this.sourceSongId,
    this.unblockedAt,
  });

  final String key;
  final String type;
  final String label;
  final DateTime createdAt;
  final String? reason;
  final String? sourceSongId;
  final DateTime? unblockedAt;

  bool get isActive => unblockedAt == null;

  BlacklistEntry copyWith({DateTime? unblockedAt}) {
    return BlacklistEntry(
      key: key,
      type: type,
      label: label,
      createdAt: createdAt,
      reason: reason,
      sourceSongId: sourceSongId,
      unblockedAt: unblockedAt,
    );
  }

  factory BlacklistEntry.fromJson(Map<dynamic, dynamic> json) {
    final label = json['label'] as String?;
    return BlacklistEntry(
      key: json['key'] as String,
      type: json['type'] as String,
      label: label ?? json['key'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      reason: json['reason'] as String?,
      sourceSongId: json['sourceSongId'] as String?,
      unblockedAt: json['unblockedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['unblockedAt'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'type': type,
      'label': label,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'reason': reason,
      'sourceSongId': sourceSongId,
      'unblockedAt': unblockedAt?.millisecondsSinceEpoch,
    };
  }
}
