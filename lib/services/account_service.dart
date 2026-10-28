import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class AccountIdentity {
  const AccountIdentity({
    required this.id,
    required this.email,
    required this.usernameMetadata,
    required this.expiresAt,
  });

  final String id;
  final String email;
  final String usernameMetadata;
  final int? expiresAt;
}

abstract interface class AccountAuthService {
  AccountIdentity? get currentAccount;
  Stream<AccountIdentity?> get authChanges;
  Future<AccountIdentity?> signIn({
    required String email,
    required String password,
  });

  /// 注册新账号。返回会话说明已直接登录；返回 null 表示注册成功、
  /// 但还需要用户去邮箱点击确认链接（项目开启了 Confirm email）。
  Future<AccountIdentity?> signUp({
    required String email,
    required String password,
    String? username,
  });
  Future<AccountIdentity?> refreshSession();
  Future<void> signOut();
  Future<void> updatePassword(String password);
}

class SupabaseAccountAuthService implements AccountAuthService {
  SupabaseAccountAuthService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  @override
  AccountIdentity? get currentAccount =>
      _identityFromSession(_client.auth.currentSession);

  @override
  Stream<AccountIdentity?> get authChanges => _client.auth.onAuthStateChange
      .map((event) => _identityFromSession(event.session));

  @override
  Future<AccountIdentity?> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return _identityFromSession(response.session);
  }

  @override
  Future<AccountIdentity?> signUp({
    required String email,
    required String password,
    String? username,
  }) async {
    final name = username?.trim() ?? '';
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      // 与 POST /auth/v1/signup 的 data 字段一致，用户名会进 user metadata。
      data: {if (name.isNotEmpty) 'username': name},
    );
    return _identityFromSession(response.session);
  }

  @override
  Future<AccountIdentity?> refreshSession() async {
    final response = await _client.auth.refreshSession();
    return _identityFromSession(response.session);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  static AccountIdentity? _identityFromSession(Session? session) {
    final user = session?.user;
    if (user == null) return null;
    return AccountIdentity(
      id: user.id,
      email: user.email?.trim() ?? '',
      usernameMetadata: (user.userMetadata?['username'] ?? '')
          .toString()
          .trim(),
      expiresAt: session?.expiresAt,
    );
  }
}

class AccountProfile {
  const AccountProfile({
    required this.username,
    required this.qqName,
    required this.avatarUrl,
  });

  const AccountProfile.empty() : username = '', qqName = '', avatarUrl = '';

  final String username;
  final String qqName;
  final String avatarUrl;
}

abstract interface class AccountProfileService {
  Future<AccountProfile> load(String userId);
  Future<void> save(String userId, AccountProfile profile);
}

class SupabaseAccountProfileService implements AccountProfileService {
  SupabaseAccountProfileService({SupabaseClient? client})
    : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  @override
  Future<AccountProfile> load(String userId) async {
    final data = await _client
        .from('suki_profiles')
        .select('username,qq_name,avatar_url')
        .eq('id', userId)
        .maybeSingle();
    if (data == null) return const AccountProfile.empty();
    return AccountProfile(
      username: (data['username'] ?? '').toString().trim(),
      qqName: (data['qq_name'] ?? '').toString().trim(),
      avatarUrl: (data['avatar_url'] ?? '').toString().trim(),
    );
  }

  @override
  Future<void> save(String userId, AccountProfile profile) async {
    await _client
        .from('suki_profiles')
        .update({
          'username': profile.username,
          'qq_name': profile.qqName.isEmpty ? null : profile.qqName,
          'avatar_url': profile.avatarUrl.isEmpty ? null : profile.avatarUrl,
        })
        .eq('id', userId);
  }
}

String accountErrorMessage(Object error) =>
    error is AuthException ? error.message : error.toString();

/// 注册失败提示：把 Supabase Auth 的英文报错翻成中文。
String signUpErrorMessage(Object error) {
  if (error is! AuthException) return accountErrorMessage(error);
  final message = error.message.toLowerCase();
  if (message.contains('already registered')) {
    return '该邮箱已注册，请直接登录';
  }
  if (message.contains('at least 6 characters')) {
    return '密码至少 6 位';
  }
  if (message.contains('weak') || message.contains('easy to guess')) {
    return '密码强度不足，请换一个更复杂的密码';
  }
  if (message.contains('validate email') ||
      message.contains('invalid format')) {
    return '邮箱格式不正确';
  }
  if (message.contains('rate limit') ||
      message.contains('only request this after')) {
    return '操作太频繁，请稍后再试';
  }
  if (message.contains('signups not allowed') ||
      message.contains('signup is disabled')) {
    return '当前未开放注册';
  }
  return accountErrorMessage(error);
}
