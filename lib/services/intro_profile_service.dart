import 'maid_content_cache_store.dart';
import 'supabase_service.dart';

class IntroProfileRecord {
  const IntroProfileRecord({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.illustrationUrl,
    required this.extraImage1Url,
    required this.extraImage2Url,
    required this.shortBio,
    required this.fullBio,
    required this.statHp,
    required this.statAtk,
    required this.statDef,
  });

  final String userId;
  final String username;
  final String avatarUrl;
  final String illustrationUrl;
  final String extraImage1Url;
  final String extraImage2Url;
  final String shortBio;
  final String fullBio;
  final int statHp;
  final int statAtk;
  final int statDef;

  bool get hasDetailImage =>
      illustrationUrl.isNotEmpty ||
      extraImage1Url.isNotEmpty ||
      extraImage2Url.isNotEmpty;
}

class IntroProfileService {
  IntroProfileService._();

  static const String _cacheKey = 'intro_profile_records';

  static Future<List<IntroProfileRecord>?> loadCachedProfiles() async {
    await MaidContentCacheStore.ensureInitialized();
    if (!MaidContentCacheStore.containsKey(_cacheKey)) {
      return null;
    }

    final raw = MaidContentCacheStore.read<Map>(_cacheKey);
    if (raw == null) return null;
    final records = _recordsFromCache(raw);
    return records;
  }

  static Future<List<IntroProfileRecord>> refreshProfiles() async {
    final records = await _fetchProfilesFromNetwork();
    await MaidContentCacheStore.ensureInitialized();
    await MaidContentCacheStore.write(
      _cacheKey,
      {
        'records': records.map(_recordToCache).toList(),
        'fetchedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
    return records;
  }

  static Future<List<IntroProfileRecord>> getProfiles({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await loadCachedProfiles();
      if (cached != null) return cached;
    }
    return refreshProfiles();
  }

  static Future<List<IntroProfileRecord>> _fetchProfilesFromNetwork() async {
    final results = await Future.wait([
      SupabaseService.client
          .from('suki_catgirl_profiles')
          .select(
            'user_id,illustration_url,extra_image_1_url,extra_image_2_url,short_bio,full_bio,stat_atk,stat_def,stat_hp',
          ),
      SupabaseService.client
          .from('suki_profiles')
          .select('id,username,avatar_url,role'),
    ]);

    final catgirlRows = results[0];
    final profileRows = results[1];

    final profilesById = <String, Map<String, dynamic>>{};
    for (final row in profileRows.whereType<Map>()) {
      final profile = Map<String, dynamic>.from(row);
      final id = (profile['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      profilesById[id] = profile;
    }

    final records = <IntroProfileRecord>[];
    for (final row in catgirlRows.whereType<Map>()) {
      final catgirl = Map<String, dynamic>.from(row);
      final userId = (catgirl['user_id'] ?? '').toString().trim();
      if (userId.isEmpty) continue;

      final profile = profilesById[userId];
      if (profile == null) continue;

      final shortBio = (catgirl['short_bio'] ?? '').toString().trim();
      final fullBio = (catgirl['full_bio'] ?? '').toString().trim();
      if (shortBio.isEmpty && fullBio.isEmpty) continue;

      final username = (profile['username'] ?? '').toString().trim();
      records.add(
        IntroProfileRecord(
          userId: userId,
          username: username.isEmpty ? userId : username,
          avatarUrl: (profile['avatar_url'] ?? '').toString().trim(),
          illustrationUrl: (catgirl['illustration_url'] ?? '').toString().trim(),
          extraImage1Url: (catgirl['extra_image_1_url'] ?? '').toString().trim(),
          extraImage2Url: (catgirl['extra_image_2_url'] ?? '').toString().trim(),
          shortBio: shortBio.isEmpty ? fullBio : shortBio,
          fullBio: fullBio.isEmpty ? shortBio : fullBio,
          statHp: _parseInt(catgirl['stat_hp']),
          statAtk: _parseInt(catgirl['stat_atk']),
          statDef: _parseInt(catgirl['stat_def']),
        ),
      );
    }

    records.sort((a, b) {
      final byName = a.username.compareTo(b.username);
      if (byName != 0) return byName;
      return a.userId.compareTo(b.userId);
    });

    return records;
  }

  static List<IntroProfileRecord> _recordsFromCache(Map raw) {
    final records = ((raw['records'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(_recordFromCache)
        .toList();

    records.sort((a, b) {
      final byName = a.username.compareTo(b.username);
      if (byName != 0) return byName;
      return a.userId.compareTo(b.userId);
    });

    return records;
  }

  static Map<String, dynamic> _recordToCache(IntroProfileRecord record) {
    return {
      'userId': record.userId,
      'username': record.username,
      'avatarUrl': record.avatarUrl,
      'illustrationUrl': record.illustrationUrl,
      'extraImage1Url': record.extraImage1Url,
      'extraImage2Url': record.extraImage2Url,
      'shortBio': record.shortBio,
      'fullBio': record.fullBio,
      'statHp': record.statHp,
      'statAtk': record.statAtk,
      'statDef': record.statDef,
    };
  }

  static IntroProfileRecord _recordFromCache(Map<String, dynamic> raw) {
    return IntroProfileRecord(
      userId: (raw['userId'] ?? '').toString().trim(),
      username: (raw['username'] ?? '').toString().trim(),
      avatarUrl: (raw['avatarUrl'] ?? '').toString().trim(),
      illustrationUrl: (raw['illustrationUrl'] ?? '').toString().trim(),
      extraImage1Url: (raw['extraImage1Url'] ?? '').toString().trim(),
      extraImage2Url: (raw['extraImage2Url'] ?? '').toString().trim(),
      shortBio: (raw['shortBio'] ?? '').toString().trim(),
      fullBio: (raw['fullBio'] ?? '').toString().trim(),
      statHp: _parseInt(raw['statHp']),
      statAtk: _parseInt(raw['statAtk']),
      statDef: _parseInt(raw['statDef']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim()) ?? 0;
  }
}
