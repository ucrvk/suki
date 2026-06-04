
import 'supabase_service.dart';
import 'maid_image_manifest_service.dart';

class MaidCatalogSnapshot {
  const MaidCatalogSnapshot({
    required this.maids,
    required this.reservations,
    required this.timeSlots,
    required this.bookingEnabled,
    required this.announcement,
    required this.maidByVrcid,
    required this.maidImageByVrcid,
    required this.hiddenMaidVrcids,
    required this.fetchedAt,
  });

  final List<Map<String, dynamic>> maids;
  final List<Map<String, dynamic>> reservations;
  final List<String> timeSlots;
  final bool bookingEnabled;
  final String announcement;
  final Map<String, Map<String, dynamic>> maidByVrcid;
  final Map<String, String> maidImageByVrcid;
  final Set<String> hiddenMaidVrcids;
  final DateTime fetchedAt;
}

class MaidCatalogCacheService {
  MaidCatalogCacheService._();

  static MaidCatalogSnapshot? _snapshot;

  static Future<MaidCatalogSnapshot> getSnapshot({bool forceRefresh = false}) async {
    if (!forceRefresh && _snapshot != null) {
      return _snapshot!;
    }

    await MaidImageManifestService.fetchManifest(forceRefresh: forceRefresh);

    final results = await Future.wait([
      SupabaseService.client.from('suki_booking').select('maids').limit(1),
      SupabaseService.client.from('suki_booking').select('reservations').limit(1),
      SupabaseService.client.from('suki_booking').select('time_slots').limit(1),
      SupabaseService.client.from('suki_booking').select('booking_enabled,announcement').limit(1),
    ]);

    final maidsRows = results[0];
    final reservationsRows = results[1];
    final timeSlotsRows = results[2];
    final metaRows = results[3];

    if (maidsRows.isEmpty || reservationsRows.isEmpty || timeSlotsRows.isEmpty || metaRows.isEmpty) {
      throw Exception('返回数据为空');
    }

    final maidsFirst = Map<String, dynamic>.from(maidsRows.first);
    final reservationsFirst = Map<String, dynamic>.from(reservationsRows.first);
    final timeSlotsFirst = Map<String, dynamic>.from(timeSlotsRows.first);
    final metaFirst = Map<String, dynamic>.from(metaRows.first);

    final maids = ((maidsFirst['maids'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final reservations = ((reservationsFirst['reservations'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final timeSlots = ((timeSlotsFirst['time_slots'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final maidByVrcid = <String, Map<String, dynamic>>{};
    final maidImageByVrcid = <String, String>{};
    final hiddenMaidVrcids = <String>{};

    for (final maid in maids) {
      final vrcid = (maid['vrcid'] ?? '').toString().trim();
      if (vrcid.isEmpty) continue;

      final resolvedImage = MaidImageManifestService.resolveImageUrl(vrcid);
      maid['image'] = resolvedImage;
      maidByVrcid[vrcid] = maid;
      maidImageByVrcid[vrcid] = resolvedImage;
      if (_shouldHideMaid(maid)) {
        hiddenMaidVrcids.add(vrcid);
      }
    }

    _snapshot = MaidCatalogSnapshot(
      maids: maids,
      reservations: reservations,
      timeSlots: timeSlots,
      bookingEnabled: metaFirst['booking_enabled'] == true,
      announcement: (metaFirst['announcement'] ?? '').toString().trim(),
      maidByVrcid: maidByVrcid,
      maidImageByVrcid: maidImageByVrcid,
      hiddenMaidVrcids: hiddenMaidVrcids,
      fetchedAt: DateTime.now(),
    );

    return _snapshot!;
  }

  static void invalidate() {
    _snapshot = null;
  }

  static bool _shouldHideMaid(Map<String, dynamic> maid) {
    final name = (maid['name'] ?? '').toString().trim();
    if (name == '鱼七') return true;

    final tags = (maid['tags'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return tags.any((tag) => tag.contains('前台'));
  }
}
