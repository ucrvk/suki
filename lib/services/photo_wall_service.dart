import 'supabase_service.dart';

class PhotoWallPageItem {
  const PhotoWallPageItem({
    required this.id,
    required this.date,
    required this.title,
    required this.displayOrder,
    required this.createdAt,
  });

  final int id;
  final String date;
  final String title;
  final int displayOrder;
  final DateTime? createdAt;

  String get displayLabel {
    final trimmedDate = date.trim();
    final trimmedTitle = title.trim();
    if (trimmedDate.isEmpty) return trimmedTitle;
    if (trimmedTitle.isEmpty) return trimmedDate;
    return '$trimmedDate-$trimmedTitle';
  }

  factory PhotoWallPageItem.fromMap(Map<String, dynamic> map) {
    return PhotoWallPageItem(
      id: _parseInt(map['id']),
      date: (map['date'] ?? '').toString().trim(),
      title: (map['title'] ?? '').toString().trim(),
      displayOrder: _parseInt(map['display_order']),
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

class PhotoWallPhotoItem {
  const PhotoWallPhotoItem({
    required this.id,
    required this.pageId,
    required this.url,
    required this.caption,
    required this.badge,
    required this.badgeClass,
    required this.tape,
    required this.displayOrder,
    required this.createdAt,
  });

  final int id;
  final int pageId;
  final String url;
  final String caption;
  final String badge;
  final String badgeClass;
  final String tape;
  final int displayOrder;
  final DateTime? createdAt;

  bool get hasBadge => badge.trim().isNotEmpty;

  factory PhotoWallPhotoItem.fromMap(Map<String, dynamic> map) {
    return PhotoWallPhotoItem(
      id: _parseInt(map['id']),
      pageId: _parseInt(map['page_id']),
      url: (map['url'] ?? '').toString().trim(),
      caption: (map['caption'] ?? '').toString().trim(),
      badge: (map['badge'] ?? '').toString().trim(),
      badgeClass: (map['badge_class'] ?? '').toString().trim(),
      tape: (map['tape'] ?? '').toString().trim(),
      displayOrder: _parseInt(map['display_order']),
      createdAt: _parseDateTime(map['created_at']),
    );
  }
}

class PhotoWallSnapshot {
  const PhotoWallSnapshot({required this.pages, required this.photosByPageId});

  final List<PhotoWallPageItem> pages;
  final Map<int, List<PhotoWallPhotoItem>> photosByPageId;
}

class PhotoWallService {
  PhotoWallService._();

  static Future<PhotoWallSnapshot> fetchSnapshot() async {
    final results = await Future.wait([
      SupabaseService.client
          .from('suki_photo_wall_pages')
          .select()
          .order('display_order', ascending: true)
          .order('created_at', ascending: true),
      SupabaseService.client
          .from('suki_photo_wall_photos')
          .select()
          .order('display_order', ascending: true)
          .order('created_at', ascending: true),
    ]);

    final pages = (results[0] as List)
        .whereType<Map>()
        .map((row) => PhotoWallPageItem.fromMap(Map<String, dynamic>.from(row)))
        .toList();

    final photos = (results[1] as List)
        .whereType<Map>()
        .map(
          (row) => PhotoWallPhotoItem.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();

    final photosByPageId = <int, List<PhotoWallPhotoItem>>{};
    for (final photo in photos) {
      if (photo.pageId <= 0 || photo.url.isEmpty) continue;
      photosByPageId
          .putIfAbsent(photo.pageId, () => <PhotoWallPhotoItem>[])
          .add(photo);
    }

    return PhotoWallSnapshot(
      pages: pages.where((page) => page.id > 0).toList(),
      photosByPageId: photosByPageId,
    );
  }
}

int _parseInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString().trim()) ?? 0;
}

DateTime? _parseDateTime(dynamic value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
