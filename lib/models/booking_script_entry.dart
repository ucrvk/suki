/// 预约前的告知弹窗内容，来自 `suki_witch_scripts.notice`。
class BookingNotice {
  const BookingNotice({
    required this.title,
    required this.intro,
    required this.items,
    required this.footer,
  });

  final String title;
  final String intro;
  final List<String> items;
  final String footer;

  /// 返回 null 表示该剧本没有告知内容（字段缺失或格式不对都不算错误）。
  static BookingNotice? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final title = (json['title'] ?? '').toString().trim();
    final intro = (json['intro'] ?? '').toString().trim();
    final footer = (json['footer'] ?? '').toString().trim();
    final items =
        (json['items'] as List?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    if (title.isEmpty && intro.isEmpty && items.isEmpty && footer.isEmpty) {
      return null;
    }
    return BookingNotice(
      title: title,
      intro: intro,
      items: items,
      footer: footer,
    );
  }
}

class BookingScriptEntry {
  const BookingScriptEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.sort,
    required this.tags,
    this.notice,
  });

  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final int sort;
  final List<String> tags;
  final BookingNotice? notice;

  factory BookingScriptEntry.fromJson(Map<String, dynamic> json) {
    final sortValue = json['sort'];
    return BookingScriptEntry(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      imageUrl: (json['image_url'] ?? '').toString().trim(),
      sort: sortValue is num ? sortValue.toInt() : 0,
      tags:
          (json['tags'] as List?)
              ?.map((tag) => tag.toString().trim())
              .where((tag) => tag.isNotEmpty)
              .toList(growable: false) ??
          const <String>[],
      notice: BookingNotice.tryParse(json['notice']),
    );
  }
}
