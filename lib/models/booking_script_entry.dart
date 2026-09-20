class BookingScriptEntry {
  const BookingScriptEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.sort,
    required this.tags,
  });

  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final int sort;
  final List<String> tags;

  factory BookingScriptEntry.fromJson(Map<String, dynamic> json) {
    final sortValue = json['sort'];
    return BookingScriptEntry(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString().trim(),
      description: (json['description'] ?? '').toString().trim(),
      imageUrl: (json['image_url'] ?? '').toString().trim(),
      sort: sortValue is num ? sortValue.toInt() : 0,
      tags: (json['tags'] as List?)
          ?.map((tag) => tag.toString().trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false) ?? const <String>[],
    );
  }
}
