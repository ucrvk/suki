import 'maid_content_cache_store.dart';
import 'supabase_service.dart';

class ReviewsCacheSnapshot {
  const ReviewsCacheSnapshot({
    required this.rawReviews,
    required this.presetComments,
    required this.maxReviewsPerUser,
    required this.fetchedAt,
  });

  final List<Map<String, dynamic>> rawReviews;
  final List<String> presetComments;
  final int? maxReviewsPerUser;
  final DateTime fetchedAt;
}

class ReviewsCacheService {
  ReviewsCacheService._();

  static const String _cacheKey = 'reviews_snapshot';

  static Future<ReviewsCacheSnapshot?> loadCachedSnapshot() async {
    await MaidContentCacheStore.ensureInitialized();
    if (!MaidContentCacheStore.containsKey(_cacheKey)) {
      return null;
    }

    final raw = MaidContentCacheStore.read<Map>(_cacheKey);
    if (raw == null) return null;
    return _snapshotFromCache(raw);
  }

  static Future<ReviewsCacheSnapshot> refreshSnapshot() async {
    final raw = await SupabaseService.client.from('suki_reviews').select('*');
    final config = await SupabaseService.client.from('suki_review_config').select('*').limit(1);

    final parsedRaw = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    final firstConfig = config.isNotEmpty ? Map<String, dynamic>.from(config.first) : null;
    final presetComments = ((firstConfig?['preset_comments'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final maxReviewsPerUser = firstConfig?['max_reviews_per_user'] is num
        ? (firstConfig!['max_reviews_per_user'] as num).toInt()
        : null;

    final snapshot = ReviewsCacheSnapshot(
      rawReviews: parsedRaw,
      presetComments: presetComments,
      maxReviewsPerUser: maxReviewsPerUser,
      fetchedAt: DateTime.now(),
    );

    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(_cacheKey, _snapshotToCache(snapshot));
    return snapshot;
  }

  static Future<ReviewsCacheSnapshot> getSnapshot({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await loadCachedSnapshot();
      if (cached != null) return cached;
    }
    return refreshSnapshot();
  }

  static ReviewsCacheSnapshot _snapshotFromCache(Map raw) {
    final rawReviews = ((raw['rawReviews'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final presetComments = ((raw['presetComments'] as List?) ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final maxReviewsPerUser = raw['maxReviewsPerUser'] is num
        ? (raw['maxReviewsPerUser'] as num).toInt()
        : null;
    final fetchedAtValue = raw['fetchedAt'];
    final fetchedAt = fetchedAtValue is num
        ? DateTime.fromMillisecondsSinceEpoch(fetchedAtValue.toInt())
        : DateTime.now();

    return ReviewsCacheSnapshot(
      rawReviews: rawReviews,
      presetComments: presetComments,
      maxReviewsPerUser: maxReviewsPerUser,
      fetchedAt: fetchedAt,
    );
  }

  static Map<String, dynamic> _snapshotToCache(ReviewsCacheSnapshot snapshot) {
    return {
      'rawReviews': snapshot.rawReviews,
      'presetComments': snapshot.presetComments,
      'maxReviewsPerUser': snapshot.maxReviewsPerUser,
      'fetchedAt': snapshot.fetchedAt.millisecondsSinceEpoch,
    };
  }
}
