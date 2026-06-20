import 'maid_content_cache_store.dart';
import 'guestbook_service.dart';
import 'supabase_service.dart';

class GuestbookCacheSnapshot {
  const GuestbookCacheSnapshot({
    required this.entries,
    required this.fetchedAt,
  });

  final List<GuestbookEntry> entries;
  final DateTime fetchedAt;
}

class GuestbookCacheService {
  GuestbookCacheService._();

  static const String _cacheKey = 'guestbook_snapshot';
  static const int _pageSize = 100;

  static Future<GuestbookCacheSnapshot?> loadCachedSnapshot() async {
    await MaidContentCacheStore.ensureInitialized();
    if (!MaidContentCacheStore.containsKey(_cacheKey)) {
      return null;
    }

    final raw = MaidContentCacheStore.read<Map>(_cacheKey);
    if (raw == null) return null;
    return _snapshotFromCache(raw);
  }

  static Future<GuestbookCacheSnapshot> refreshSnapshot() async {
    final rows = await _fetchAllApprovedEntries();
    final snapshot = GuestbookCacheSnapshot(
      entries: rows,
      fetchedAt: DateTime.now(),
    );

    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(_cacheKey, _snapshotToCache(snapshot));
    return snapshot;
  }

  static Future<GuestbookCacheSnapshot> getSnapshot({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await loadCachedSnapshot();
      if (cached != null) return cached;
    }
    return refreshSnapshot();
  }

  static Future<List<GuestbookEntry>> _fetchAllApprovedEntries() async {
    final entries = <GuestbookEntry>[];
    var offset = 0;

    while (true) {
      final response = await SupabaseService.client
          .from('suki_guestbook')
          .select()
          .eq('approved', true)
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      final page = (response as List<dynamic>)
          .map((json) => GuestbookEntry.fromJson(Map<String, dynamic>.from(json as Map)))
          .toList();
      entries.addAll(page);

      if (page.length < _pageSize) break;
      offset += _pageSize;
    }

    return entries;
  }

  static GuestbookCacheSnapshot _snapshotFromCache(Map raw) {
    final entries = ((raw['entries'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => GuestbookEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final fetchedAtValue = raw['fetchedAt'];
    final fetchedAt = fetchedAtValue is num
        ? DateTime.fromMillisecondsSinceEpoch(fetchedAtValue.toInt())
        : DateTime.now();

    return GuestbookCacheSnapshot(
      entries: entries,
      fetchedAt: fetchedAt,
    );
  }

  static Map<String, dynamic> _snapshotToCache(GuestbookCacheSnapshot snapshot) {
    return {
      'entries': snapshot.entries.map((entry) => entry.toJson()).toList(),
      'fetchedAt': snapshot.fetchedAt.millisecondsSinceEpoch,
    };
  }
}
