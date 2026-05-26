
import 'supabase_service.dart';

class MaidCatalogSnapshot {
  const MaidCatalogSnapshot({
    required this.maids,
    required this.reservations,
    required this.bookingEnabled,
    required this.announcement,
    required this.maidByVrcid,
    required this.maidImageByVrcid,
    required this.hiddenMaidVrcids,
    required this.fetchedAt,
  });

  final List<Map<String, dynamic>> maids;
  final List<Map<String, dynamic>> reservations;
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

    final decoded = await SupabaseService.client.from('suki_booking').select('*').limit(1);
    if (decoded.isEmpty) {
      throw Exception('返回数据为空');
    }

    final first = Map<String, dynamic>.from(decoded.first);
    final maids = ((first['maids'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final reservations = ((first['reservations'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final maidByVrcid = <String, Map<String, dynamic>>{};
    final maidImageByVrcid = <String, String>{};
    final hiddenMaidVrcids = <String>{};

    for (final maid in maids) {
      final vrcid = (maid['vrcid'] ?? '').toString().trim();
      if (vrcid.isEmpty) continue;

      maidByVrcid[vrcid] = maid;
      maidImageByVrcid[vrcid] = (maid['image'] ?? '').toString().trim();
      if (_shouldHideMaid(maid)) {
        hiddenMaidVrcids.add(vrcid);
      }
    }

    _snapshot = MaidCatalogSnapshot(
      maids: maids,
      reservations: reservations,
      bookingEnabled: first['booking_enabled'] == true,
      announcement: (first['announcement'] ?? '').toString().trim(),
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
