enum WorldContentKind { witch, lore, unknown, ending }

class WorldContentEntry {
  const WorldContentEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.imageUrl2,
    required this.tags,
    required this.body,
    required this.sort,
    required this.createdAt,
    required this.script,
  });

  factory WorldContentEntry.fromCodexJson(Map<String, dynamic> json) {
    final rawKind = _requiredString(json, 'kind');
    final kind = switch (rawKind) {
      'witch' => WorldContentKind.witch,
      'lore' => WorldContentKind.lore,
      _ => WorldContentKind.unknown,
    };
    return WorldContentEntry(
      id: _requiredString(json, 'id'),
      kind: kind,
      title: _requiredString(json, 'title'),
      subtitle: _optionalString(json, 'subtitle'),
      imageUrl: _optionalString(json, 'image_url'),
      imageUrl2: _optionalString(json, 'image_url2'),
      tags: _stringList(json, 'tags'),
      body: _optionalString(json, 'body'),
      sort: _integer(json, 'sort'),
      createdAt: _dateTime(json, 'created_at'),
      script: '',
    );
  }

  factory WorldContentEntry.fromEndingJson(Map<String, dynamic> json) {
    return WorldContentEntry(
      id: _requiredString(json, 'id'),
      kind: WorldContentKind.ending,
      title: _requiredString(json, 'title'),
      subtitle: _optionalString(json, 'subtitle'),
      imageUrl: _optionalString(json, 'image_url'),
      imageUrl2: '',
      tags: _stringList(json, 'tags'),
      body: _optionalString(json, 'body'),
      sort: _integer(json, 'sort'),
      createdAt: _dateTime(json, 'created_at'),
      script: _requiredString(json, 'script'),
    );
  }

  final String id;
  final WorldContentKind kind;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String imageUrl2;
  final List<String> tags;
  final String body;
  final int sort;
  final DateTime createdAt;
  final String script;

  List<String> get imageUrls => [
    imageUrl,
    imageUrl2,
  ].where((url) => url.isNotEmpty).toList(growable: false);

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': switch (kind) {
      WorldContentKind.witch => 'witch',
      WorldContentKind.lore => 'lore',
      WorldContentKind.unknown => 'unknown',
      WorldContentKind.ending => 'ending',
    },
    'title': title,
    'subtitle': subtitle,
    'image_url': imageUrl,
    'image_url2': imageUrl2,
    'tags': tags,
    'body': body,
    'sort': sort,
    'created_at': createdAt.toIso8601String(),
    'script': script,
  };

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value.trim();
  }

  static String _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return '';
    if (value is! String) {
      throw FormatException('$key must be a string or null');
    }
    return value.trim();
  }

  static int _integer(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num || value % 1 != 0) {
      throw FormatException('$key must be an integer');
    }
    return value.toInt();
  }

  static DateTime _dateTime(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) {
      throw FormatException('$key must be an ISO 8601 string');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('$key must be a valid ISO 8601 string');
    }
    return parsed;
  }

  static List<String> _stringList(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) throw FormatException('$key must be a list');
    return value
        .map((item) {
          if (item is! String) {
            throw FormatException('$key must contain strings');
          }
          return item.trim();
        })
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}

Map<String, List<WorldContentEntry>> groupEndingsByScript(
  Iterable<WorldContentEntry> entries,
) {
  final groups = <String, List<WorldContentEntry>>{};
  for (final entry in entries.where(
    (entry) => entry.kind == WorldContentKind.ending,
  )) {
    groups.putIfAbsent(entry.script, () => <WorldContentEntry>[]).add(entry);
  }
  return groups;
}
