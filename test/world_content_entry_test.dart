import 'package:flutter_test/flutter_test.dart';
import 'package:suki/models/world_content_entry.dart';

void main() {
  Map<String, dynamic> codexRow({
    String kind = 'witch',
    Object? subtitle = '',
    Object? imageUrl = '',
    Object? imageUrl2,
    Object? tags = const <String>[],
  }) => {
    'id': 'codex-1',
    'kind': kind,
    'title': '纸樱',
    'subtitle': subtitle,
    'image_url': imageUrl,
    'image_url2': imageUrl2,
    'tags': tags,
    'body': '详细介绍',
    'sort': 2,
    'created_at': '2026-09-09T02:04:03+08:00',
  };

  test('classifies witch and lore records', () {
    expect(
      WorldContentEntry.fromCodexJson(codexRow()).kind,
      WorldContentKind.witch,
    );
    expect(
      WorldContentEntry.fromCodexJson(codexRow(kind: 'lore')).kind,
      WorldContentKind.lore,
    );
    expect(
      WorldContentEntry.fromCodexJson(codexRow(kind: 'future')).kind,
      WorldContentKind.unknown,
    );
  });

  test('accepts empty optional fields and exposes both images', () {
    final entry = WorldContentEntry.fromCodexJson(
      codexRow(
        subtitle: null,
        imageUrl: 'https://example.com/one.png',
        imageUrl2: 'https://example.com/two.png',
        tags: null,
      ),
    );
    expect(entry.subtitle, isEmpty);
    expect(entry.tags, isEmpty);
    expect(entry.imageUrls, hasLength(2));
  });

  test('rejects invalid field types', () {
    expect(
      () => WorldContentEntry.fromCodexJson(codexRow(tags: 'tag')),
      throwsFormatException,
    );
    expect(
      () => WorldContentEntry.fromCodexJson(codexRow(imageUrl: 1)),
      throwsFormatException,
    );
  });

  test('groups endings by script while preserving response order', () {
    WorldContentEntry ending(String script, String title, int sort) {
      return WorldContentEntry.fromEndingJson({
        'id': '$script-$sort',
        'script': script,
        'title': title,
        'subtitle': '',
        'image_url': '',
        'tags': const <String>[],
        'body': '',
        'sort': sort,
        'created_at': '2026-09-09T02:04:03+08:00',
      });
    }

    final groups = groupEndingsByScript([
      ending('夜眠花', '黎明之誓', 2),
      ending('夜眠花', '永恒安眠', 5),
      ending('新剧本', '结局', 1),
    ]);

    expect(groups.keys, ['夜眠花', '新剧本']);
    expect(groups['夜眠花']!.map((entry) => entry.title), ['黎明之誓', '永恒安眠']);
  });
}
