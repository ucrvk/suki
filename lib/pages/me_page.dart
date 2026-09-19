import 'dart:async';

import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../widgets/account_avatar.dart';
import 'account_settings_page.dart';

class MePage extends StatefulWidget {
  const MePage({super.key, this.authService, this.profileService});

  final AccountAuthService? authService;
  final AccountProfileService? profileService;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  static const _cardColor = Color(0xFF33205C);
  static const _mutedColor = Color(0xFFC4B4DC);

  late final AccountAuthService _authService;
  late final AccountProfileService _profileService;
  StreamSubscription<AccountIdentity?>? _authSubscription;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = true;
  bool _loggingOut = false;
  AccountIdentity? _account;
  AccountProfile _profile = const AccountProfile.empty();

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? SupabaseAccountAuthService();
    _profileService = widget.profileService ?? SupabaseAccountProfileService();
    _authSubscription = _authService.authChanges.listen(_applyAccount);
    unawaited(_restoreAuth());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _restoreAuth() async {
    AccountIdentity? account = _authService.currentAccount;
    try {
      final expiresAt = account?.expiresAt;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (expiresAt != null && expiresAt <= now) {
        account = await _authService.refreshSession();
      }
    } catch (_) {
      account = null;
    }
    await _applyAccount(account);
  }

  Future<void> _applyAccount(AccountIdentity? account) async {
    if (!mounted) return;
    setState(() {
      _account = account;
      _loading = false;
      if (account == null) _profile = const AccountProfile.empty();
    });
    if (account != null) await _loadProfile(account);
  }

  Future<void> _loadProfile(AccountIdentity account) async {
    try {
      final profile = await _profileService.load(account.id);
      if (!mounted || _account?.id != account.id) return;
      setState(() => _profile = profile);
    } catch (_) {
      // Authentication remains usable when profile loading fails.
    }
  }

  String get _displayName {
    if (_profile.username.isNotEmpty) return _profile.username;
    final metadataName = _account?.usernameMetadata ?? '';
    if (metadataName.isNotEmpty) return metadataName;
    final email = _account?.email ?? '';
    final at = email.indexOf('@');
    if (at > 0) return email.substring(0, at);
    return email.isEmpty ? '未命名用户' : email;
  }

  Future<void> _showLoginDialog() async {
    _emailController.text = _account?.email ?? '';
    _passwordController.clear();
    var submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final email = _emailController.text.trim();
              final password = _passwordController.text;
              if (email.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请输入邮箱和密码')));
                return;
              }
              setDialogState(() => submitting = true);
              try {
                final account = await _authService.signIn(
                  email: email,
                  password: password,
                );
                if (account == null) {
                  throw StateError('认证服务未返回会话');
                }
                await _applyAccount(account);
                if (context.mounted) Navigator.of(context).pop();
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(accountErrorMessage(error))),
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => submitting = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('登录'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('login-email'),
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '邮箱'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('login-password'),
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码'),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const Key('login-submit-button'),
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await _authService.signOut();
      await _applyAccount(null);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(accountErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _openSettings() async {
    final account = _account;
    if (account == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AccountSettingsPage(
          account: account,
          authService: _authService,
          profileService: _profileService,
        ),
      ),
    );
    if (mounted && _account?.id == account.id) await _loadProfile(account);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '我的',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_account != null)
                  IconButton(
                    key: const Key('logout-button'),
                    onPressed: _loggingOut ? null : _logout,
                    tooltip: '退出登录',
                    icon: _loggingOut
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout_rounded),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [_buildAccountCard()],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    if (_account == null) {
      return Material(
        color: _cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFF4A2F80)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.account_circle_outlined),
              title: Text('账号', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('登录后管理您的个人资料'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('open-login-button'),
                  onPressed: _showLoginDialog,
                  child: const Text('登录'),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFF4A2F80)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: AccountAvatar(imageUrl: _profile.avatarUrl),
            title: Text(
              _displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              _account!.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _mutedColor),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF4A2F80)),
          ListTile(
            key: const Key('account-settings-button'),
            leading: const Icon(Icons.settings_outlined),
            title: const Text(
              '账户设置',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _openSettings,
          ),
        ],
      ),
    );
  }
}
