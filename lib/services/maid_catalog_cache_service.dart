import 'dart:async';

import 'maid_content_cache_store.dart';
import 'maid_image_manifest_service.dart';
import 'supabase_service.dart';

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

  static const String _cacheKey = 'maid_catalog_snapshot';

  static MaidCatalogSnapshot? _snapshot;
  static Future<MaidCatalogSnapshot>? _refreshing;

  static Future<MaidCatalogSnapshot?> loadCachedSnapshot() async {
    await MaidContentCacheStore.ensureInitialized();
    await MaidImageManifestService.fetchManifest(forceRefresh: false);
    if (!MaidContentCacheStore.containsKey(_cacheKey)) {
      return null;
    }

    final raw = MaidContentCacheStore.read<Map>(_cacheKey);
    if (raw == null) return null;

    final snapshot = _snapshotFromCache(raw);
    _snapshot = snapshot;
    return snapshot;
  }

  static Future<MaidCatalogSnapshot> getSnapshot({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_snapshot != null) {
        await MaidImageManifestService.fetchManifest(forceRefresh: false);
        _snapshot = _normalizeSnapshotImages(_snapshot!);
        return _snapshot!;
      }

      final cached = await loadCachedSnapshot();
      if (cached != null) {
        return cached;
      }
    }

    return refreshSnapshot();
  }

  static Future<MaidCatalogSnapshot> refreshSnapshot() {
    return _refreshing ??= _fetchAndCacheSnapshot().whenComplete(() {
      _refreshing = null;
    });
  }

  static void invalidate() {
    _snapshot = null;
  }

  static Future<MaidCatalogSnapshot> _fetchAndCacheSnapshot() async {
    await MaidImageManifestService.fetchManifest(forceRefresh: true);

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

    final snapshot = _buildSnapshot(
      maids: maids,
      reservations: reservations,
      timeSlots: timeSlots,
      bookingEnabled: metaFirst['booking_enabled'] == true,
      announcement: (metaFirst['announcement'] ?? '').toString().trim(),
      fetchedAt: DateTime.now(),
    );

    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(_cacheKey, _snapshotToCache(snapshot));

    _snapshot = snapshot;
    return snapshot;
  }

  static MaidCatalogSnapshot _snapshotFromCache(Map raw) {
    final cachedMaids = ((raw['maids'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final cachedReservations = ((raw['reservations'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final cachedTimeSlots = ((raw['timeSlots'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final bookingEnabled = raw['bookingEnabled'] == true;
    final announcement = (raw['announcement'] ?? '').toString().trim();
    final fetchedAtValue = raw['fetchedAt'];
    final fetchedAt = fetchedAtValue is num
        ? DateTime.fromMillisecondsSinceEpoch(fetchedAtValue.toInt())
        : DateTime.now();

    return _buildSnapshot(
      maids: cachedMaids,
      reservations: cachedReservations,
      timeSlots: cachedTimeSlots,
      bookingEnabled: bookingEnabled,
      announcement: announcement,
      fetchedAt: fetchedAt,
    );
  }

  static Map<String, dynamic> _snapshotToCache(MaidCatalogSnapshot snapshot) {
    return {
      'maids': snapshot.maids,
      'reservations': snapshot.reservations,
      'timeSlots': snapshot.timeSlots,
      'bookingEnabled': snapshot.bookingEnabled,
      'announcement': snapshot.announcement,
      'fetchedAt': snapshot.fetchedAt.millisecondsSinceEpoch,
    };
  }

  static MaidCatalogSnapshot _buildSnapshot({
    required List<Map<String, dynamic>> maids,
    required List<Map<String, dynamic>> reservations,
    required List<String> timeSlots,
    required bool bookingEnabled,
    required String announcement,
    required DateTime fetchedAt,
  }) {
    final normalizedMaids = <Map<String, dynamic>>[];
    final maidByVrcid = <String, Map<String, dynamic>>{};
    final maidImageByVrcid = <String, String>{};
    final hiddenMaidVrcids = <String>{};

    for (final maid in maids) {
      final normalized = Map<String, dynamic>.from(maid);
      final vrcid = (normalized['vrcid'] ?? '').toString().trim();
      if (vrcid.isEmpty) {
        normalized.remove('image');
        normalizedMaids.add(normalized);
        continue;
      }

      final resolvedImage = MaidImageManifestService.resolveImageUrl(vrcid);
      normalized['image'] = resolvedImage;

      normalizedMaids.add(normalized);
      maidByVrcid[vrcid] = normalized;
      maidImageByVrcid[vrcid] = resolvedImage;
      if (_shouldHideMaid(normalized)) {
        hiddenMaidVrcids.add(vrcid);
      }
    }

    return MaidCatalogSnapshot(
      maids: normalizedMaids,
      reservations: reservations,
      timeSlots: timeSlots,
      bookingEnabled: bookingEnabled,
      announcement: announcement,
      maidByVrcid: maidByVrcid,
      maidImageByVrcid: maidImageByVrcid,
      hiddenMaidVrcids: hiddenMaidVrcids,
      fetchedAt: fetchedAt,
    );
  }

  static MaidCatalogSnapshot _normalizeSnapshotImages(MaidCatalogSnapshot snapshot) {
    final maids = snapshot.maids.map((maid) {
      final normalized = Map<String, dynamic>.from(maid);
      final vrcid = (normalized['vrcid'] ?? '').toString().trim();
      if (vrcid.isEmpty) {
        normalized.remove('image');
      } else {
        normalized['image'] = MaidImageManifestService.resolveImageUrl(vrcid);
      }
      return normalized;
    }).toList();

    return _buildSnapshot(
      maids: maids,
      reservations: snapshot.reservations,
      timeSlots: snapshot.timeSlots,
      bookingEnabled: snapshot.bookingEnabled,
      announcement: snapshot.announcement,
      fetchedAt: snapshot.fetchedAt,
    );
  }

  static bool _shouldHideMaid(Map<String, dynamic> maid) {
    final name = (maid['name'] ?? '').toString().trim();
    if (name == '鱼七') return true;

    final tags = (maid['tags'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    return tags.any((tag) => tag.contains('前台'));
  }
}
