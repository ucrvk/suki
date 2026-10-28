import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/account_service.dart';
import '../services/app_update_service.dart';
import '../services/bgm_controller.dart';
import '../services/spoiler_mode_store.dart';
import '../widgets/account_avatar.dart';
import 'account_settings_page.dart';
import '../theme/app_colors.dart';

class MePage extends StatefulWidget {
  const MePage({
    super.key,
    this.authService,
    this.profileService,
    this.spoilerModeStore,
    this.bgmController,
    this.updateService,
  });

  final AccountAuthService? authService;
  final AccountProfileService? profileService;
  final SpoilerModeStore? spoilerModeStore;
  final BgmController? bgmController;
  final AppUpdateService? updateService;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  late final AccountAuthService _authService;
  late final AccountProfileService _profileService;
  late final AppUpdateService _updateService;
  StreamSubscription<AccountIdentity?>? _authSubscription;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _registerUsernameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmController = TextEditingController();
  SpoilerModeStore? _spoilerStore;
  BgmController? _bgmController;

  bool _loading = true;
  bool _loggingOut = false;
  bool _spoilerEnabled = false;
  bool _bgmEnabled = false;
  bool _checkingUpdate = false;
  AccountIdentity? _account;
  AccountProfile _profile = const AccountProfile.empty();
  String _appVersion = '-';
  String? _latestVersion;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? SupabaseAccountAuthService();
    _profileService = widget.profileService ?? SupabaseAccountProfileService();
    _updateService = widget.updateService ?? AppUpdateService();
    _authSubscription = _authService.authChanges.listen(_applyAccount);
    _spoilerStore = widget.spoilerModeStore;
    _spoilerEnabled = _spoilerStore?.value ?? false;
    _spoilerStore?.addListener(_handleSpoilerChanged);
    _bgmController = widget.bgmController;
    _bgmEnabled = _bgmController?.value ?? false;
    _bgmController?.addListener(_handleBgmChanged);
    unawaited(_restoreAuth());
    unawaited(_loadAppVersion());
  }

  @override
  void dispose() {
    _spoilerStore?.removeListener(_handleSpoilerChanged);
    _bgmController?.removeListener(_handleBgmChanged);
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _registerUsernameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmController.dispose();
    super.dispose();
  }

  void _handleSpoilerChanged() {
    setState(() => _spoilerEnabled = _spoilerStore?.value ?? false);
  }

  void _handleBgmChanged() {
    setState(() => _bgmEnabled = _bgmController?.value ?? false);
  }

  Future<void> _setBgmEnabled(bool enabled) async {
    final controller = _bgmController;
    if (controller == null) return;
    setState(() => _bgmEnabled = enabled);
    await controller.setEnabled(enabled);
    if (!mounted) return;
    setState(() => _bgmEnabled = controller.value);
  }

  Future<void> _setSpoilerEnabled(bool enabled) async {
    final store = _spoilerStore;
    if (store == null) return;
    setState(() => _spoilerEnabled = enabled);
    await store.setEnabled(enabled);
    if (!mounted) return;
    setState(() => _spoilerEnabled = store.value);
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
    final account = _account;
    // 未登录时保留上次输入的邮箱（注册成功后会回填），已登录则回填账号邮箱。
    if (account != null) _emailController.text = account.email;
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

  Future<void> _showRegisterDialog() async {
    _registerUsernameController.clear();
    _registerEmailController.text = _emailController.text.trim();
    _registerPasswordController.clear();
    _registerConfirmController.clear();
    var submitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !submitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final username = _registerUsernameController.text.trim();
              final email = _registerEmailController.text.trim();
              final password = _registerPasswordController.text;
              if (username.isEmpty || email.isEmpty || password.isEmpty) {
                _showMessage('请输入用户名、邮箱和密码');
                return;
              }
              if (password.length < 6) {
                _showMessage('密码至少 6 位');
                return;
              }
              if (password != _registerConfirmController.text) {
                _showMessage('两次输入的密码不一致');
                return;
              }
              setDialogState(() => submitting = true);
              try {
                final account = await _authService.signUp(
                  email: email,
                  password: password,
                  username: username,
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                // 回填邮箱，方便确认邮件后直接登录。
                _emailController.text = email;
                if (account != null) {
                  await _applyAccount(account);
                  _showMessage('注册成功');
                } else {
                  _showMessage('注册成功，请到邮箱点击确认链接后再登录');
                }
              } catch (error) {
                _showMessage(signUpErrorMessage(error));
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => submitting = false);
                }
              }
            }

            return AlertDialog(
              title: const Text('注册'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      key: const Key('register-username'),
                      controller: _registerUsernameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'VRC用户名'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('register-email'),
                      controller: _registerEmailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: '邮箱'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('register-password'),
                      controller: _registerPasswordController,
                      obscureText: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        helperText: '至少 6 位',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('register-confirm-password'),
                      controller: _registerConfirmController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '确认密码'),
                      onSubmitted: (_) => submit(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const Key('register-submit-button'),
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('注册'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      if (!mounted) return;
      setState(() {
        _appVersion = build.isEmpty ? 'v$version' : 'v$version+$build';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _appVersion = '-');
    }
  }

  /// 检查更新的适用平台：Android 与桌面端（Linux / Windows）。
  /// web 刷新页面就是最新版，不提供按钮。
  bool get _supportsUpdateCheck =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// 检查更新：拉取 GitHub 最新 tag 并与当前版本比对。
  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    AppUpdateInfo? info;
    Object? failure;
    try {
      info = await _updateService.check();
    } catch (error) {
      failure = error;
    }
    if (!mounted) return;
    setState(() {
      _checkingUpdate = false;
      _latestVersion = info != null && info.hasUpdate ? info.latestTag : null;
    });

    final messenger = ScaffoldMessenger.of(context);
    if (failure != null) {
      messenger.showSnackBar(const SnackBar(content: Text('检查更新失败，请检查网络后重试')));
      return;
    }
    final result = info!;
    if (!result.hasUpdate) {
      messenger.showSnackBar(SnackBar(content: Text('已是最新版本 $_appVersion')));
      return;
    }
    await _showUpdateDialog(result);
  }

  Future<void> _showUpdateDialog(AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('最新版本 ${info.latestTag}，当前版本 $_appVersion。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            key: const Key('open-latest-release-button'),
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(
                _openUrl(info.releaseUri ?? Uri.parse(sukiGitHubRepoUrl)),
              );
            },
            child: const Text('前往查看'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(Uri uri) async {
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened) return;
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法直接打开浏览器，已复制链接到剪贴板')));
  }

  Future<void> _openGitHub() => _openUrl(Uri.parse(sukiGitHubRepoUrl));

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
                    children: [
                      _buildAccountCard(),
                      if (_bgmController != null) const SizedBox(height: 12),
                      if (_bgmController != null) _buildBgmCard(),
                      if (_spoilerStore != null) const SizedBox(height: 12),
                      if (_spoilerStore != null) _buildSpoilerCard(),
                      const SizedBox(height: 12),
                      _buildMetaCard(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    if (_account == null) {
      return Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.account_circle_outlined),
              title: Text('账号', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('登录或注册后管理您的个人资料'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('open-register-button'),
                      onPressed: _showRegisterDialog,
                      child: const Text('注册'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('open-login-button'),
                      onPressed: _showLoginDialog,
                      child: const Text('登录'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.outline),
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
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
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

  Widget _buildBgmCard() {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: const Key('bgm-switch'),
        secondary: const Icon(Icons.music_note_outlined),
        title: const Text(
          '背景音乐',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          '开启后循环播放在线背景音乐',
          style: TextStyle(color: AppColors.textMuted),
        ),
        value: _bgmEnabled,
        onChanged: (value) => unawaited(_setBgmEnabled(value)),
      ),
    );
  }

  Widget _buildSpoilerCard() {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        key: const Key('spoiler-mode-switch'),
        secondary: const Icon(Icons.visibility_outlined),
        title: const Text(
          '剧透模式',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: const Text(
          '开启后显示全部结局；关闭时只显示你已解锁的结局',
          style: TextStyle(color: AppColors.textMuted),
        ),
        value: _spoilerEnabled,
        onChanged: (value) => unawaited(_setSpoilerEnabled(value)),
      ),
    );
  }

  Widget _buildMetaCard() {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text(
              '版本号',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              _latestVersion == null
                  ? _appVersion
                  : '$_appVersion · 有新版本 $_latestVersion',
              style: TextStyle(
                color: _latestVersion == null
                    ? AppColors.textMuted
                    : AppColors.accent,
              ),
            ),
            // 仅 Android / 桌面端提供检查更新，web 刷新即最新。
            trailing: _supportsUpdateCheck
                ? TextButton(
                    key: const Key('check-update-button'),
                    onPressed: _checkingUpdate ? null : _checkForUpdate,
                    child: _checkingUpdate
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('检查更新'),
                  )
                : null,
          ),
          const Divider(height: 1, color: AppColors.divider),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text(
              '原版及后端作者：鱼七',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '本改版作者：wenwen12305',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ListTile(
            key: const Key('github-link-button'),
            leading: const Icon(Icons.open_in_new_rounded),
            title: const Text(
              '访问项目 GitHub',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'ucrvk/suki',
              style: TextStyle(color: AppColors.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _openGitHub,
          ),
          const Divider(height: 1, color: AppColors.divider),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text(
              '开源使用',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '查看开源许可',
              style: TextStyle(color: AppColors.textMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              showLicensePage(context: context, applicationName: 'suki');
            },
          ),
        ],
      ),
    );
  }
}
