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

  static Future<List<IntroProfileRecord>> fetchProfiles() async {
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

  static int _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString().trim()) ?? 0;
  }
}
