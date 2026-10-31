import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_update_service.dart';
import '../services/auth_log_service.dart';
import '../services/maid_catalog_cache_service.dart';
import '../services/queue_tab_settings.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';
import 'account_settings_page.dart';

class MePage extends StatefulWidget {
  const MePage({super.key, this.updateService});

  final AppUpdateService? updateService;

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  bool _loading = true;
  bool _isLoggedIn = false;
  bool _submitting = false;
  bool _authLogExporting = false;
  bool _checkingUpdate = false;
  String? _latestVersion;
  late final AppUpdateService _updateService;
  String? _email;
  String? _username;
  String? _announcement;
  String _appVersion = '-';
  StreamSubscription<AuthState>? _authStateSub;
  late final VoidCallback _queueTabListener;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _registerUsernameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerConfirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _updateService = widget.updateService ?? AppUpdateService();
    _restoreAuth();
    _loadAnnouncement();
    _loadAppVersion();
    unawaited(QueueTabSettings.load());
    _queueTabListener = () {
      if (mounted) {
        setState(() {});
      }
    };
    QueueTabSettings.enabledNotifier.addListener(_queueTabListener);
    _authStateSub = SupabaseService.client.auth.onAuthStateChange.listen((
      event,
    ) {
      _applySession(event.session);
    });
  }

  @override
  void dispose() {
    QueueTabSettings.enabledNotifier.removeListener(_queueTabListener);
    _authStateSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _registerUsernameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    _registerConfirmController.dispose();

    super.dispose();
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
      setState(() {
        _appVersion = '版本未知';
      });
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
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.latestTag == null ? '暂无可用的 2.x 正式版本' : '已是最新版本 $_appVersion',
          ),
        ),
      );
      return;
    }
    await _showUpdateDialog(result);
  }

  Future<void> _showUpdateDialog(AppUpdateInfo info) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: Text('最新版本 ${info.latestTag}，当前版本 ${info.currentVersion}。'),
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
      // Fall back to copying the link when no browser is available.
    }
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法直接打开浏览器，已复制链接到剪贴板')));
  }

  Future<void> _restoreAuth() async {
    Session? session;
    try {
      session = SupabaseService.client.auth.currentSession;
      if (session != null && session.expiresAt != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (session.expiresAt! <= now) {
          final sessionBeforeRefresh = session;
          try {
            final refreshed = await SupabaseService.client.auth
                .refreshSession();
            session = refreshed.session;
            await AuthLogService.record(
              event: 'session_refresh',
              source: 'MePage._restoreAuth',
              succeeded: session != null,
              email: session?.user.email,
              detail: session == null ? '认证服务未返回会话' : null,
              session: session,
              usedSession: sessionBeforeRefresh,
            );
          } catch (error) {
            await AuthLogService.record(
              event: 'session_refresh',
              source: 'MePage._restoreAuth',
              succeeded: false,
              email: session?.user.email,
              detail: AuthLogService.errorDetail(error),
              usedSession: sessionBeforeRefresh,
            );
            rethrow;
          }
        }
      }
      await AuthLogService.record(
        event: 'startup_session_check',
        source: 'MePage._restoreAuth',
        succeeded: true,
        email: session?.user.email,
        detail: session == null ? '未检测到登录会话' : '检测到有效登录会话',
        session: session,
      );
      _applySession(session);
    } catch (error) {
      await AuthLogService.record(
        event: 'startup_session_check',
        source: 'MePage._restoreAuth',
        succeeded: false,
        email: session?.user.email,
        detail: AuthLogService.errorDetail(error),
        session: session,
      );
      _applySession(null);
    }
  }

  void _applySession(Session? session) {
    final user = session?.user;
    final email = user?.email;
    final username = (user?.userMetadata?['username'] ?? '').toString();

    if (!mounted) return;
    setState(() {
      _loading = false;
      _isLoggedIn = user != null;
      _email = email;
      _username = username;
    });
  }

  Future<void> _logout() async {
    await SupabaseService.client.auth.signOut();
    _applySession(null);
  }

  Future<void> _exportAuthLog() async {
    if (_authLogExporting) return;
    setState(() => _authLogExporting = true);
    try {
      final exportedPath = await AuthLogService.export();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('登录日志已导出至 $exportedPath')));
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导出登录日志失败')));
    } finally {
      if (mounted) {
        setState(() => _authLogExporting = false);
      }
    }
  }

  Future<void> _loadAnnouncement() async {
    try {
      final cached = await MaidCatalogCacheService.loadCachedSnapshot();
      if (cached != null && mounted) {
        setState(() {
          _announcement = cached.announcement;
        });
        unawaited(_refreshAnnouncement());
        return;
      }

      final snapshot = await MaidCatalogCacheService.refreshSnapshot();
      if (!mounted) return;
      setState(() {
        _announcement = snapshot.announcement;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _announcement = '';
      });
    }
  }

  Future<void> _refreshAnnouncement() async {
    try {
      final snapshot = await MaidCatalogCacheService.refreshSnapshot();
      if (!mounted) return;
      setState(() {
        _announcement = snapshot.announcement;
      });
    } catch (_) {
      // Keep the cached announcement if refresh fails.
    }
  }

  String _displayName() {
    final username = (_username ?? '').trim();
    if (username.isNotEmpty) return username;
    final email = (_email ?? '').trim();
    if (email.contains('@')) return email.split('@').first;
    return email.isEmpty ? '未命名用户' : email;
  }

  Future<void> _showLoginDialog() async {
    if (_isLoggedIn) _emailController.text = _email ?? '';
    _passwordController.clear();

    await showDialog<void>(
      context: context,
      barrierDismissible: !_submitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              final email = _emailController.text.trim();
              final password = _passwordController.text;
              if (email.isEmpty || password.isEmpty) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请输入邮箱和密码')));
                return;
              }

              setDialogState(() => _submitting = true);

              try {
                final authResponse = await SupabaseService.client.auth
                    .signInWithPassword(email: email, password: password);
                await AuthLogService.record(
                  event: 'password_sign_in',
                  source: 'MePage._showLoginDialog',
                  succeeded: authResponse.session != null,
                  email: email,
                  detail: authResponse.session == null ? '认证服务未返回会话' : null,
                  session: authResponse.session,
                );
                _applySession(authResponse.session);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              } on AuthException catch (e) {
                await AuthLogService.record(
                  event: 'password_sign_in',
                  source: 'MePage._showLoginDialog',
                  succeeded: false,
                  email: email,
                  detail: e.message,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.message)));
              } catch (e) {
                await AuthLogService.record(
                  event: 'password_sign_in',
                  source: 'MePage._showLoginDialog',
                  succeeded: false,
                  email: email,
                  detail: AuthLogService.errorDetail(e),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.toString())));
              } finally {
                if (context.mounted) {
                  setDialogState(() => _submitting = false);
                } else {
                  _submitting = false;
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
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: _submitting ? null : submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
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
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit() async {
              if (submitting) return;
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
                final response = await SupabaseService.client.auth.signUp(
                  email: email,
                  password: password,
                  data: {'username': username},
                );
                if (response.user == null) {
                  throw const AuthException('注册失败，未获取到用户信息');
                }
                if (!dialogContext.mounted || !mounted) return;
                setDialogState(() => submitting = false);
                Navigator.of(dialogContext).pop();
                // 回填邮箱，方便确认邮件后直接登录。
                _emailController.text = email;
                if (response.session != null) {
                  _applySession(response.session);
                  _showMessage('注册成功');
                } else {
                  _showMessage('注册成功，请到邮箱点击确认链接后再登录');
                }
              } catch (error) {
                _showMessage(_signUpErrorMessage(error));
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => submitting = false);
                }
              }
            }

            return PopScope(
              canPop: !submitting,
              child: AlertDialog(
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
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(
        title: const Text('我'),
        actions: [
          if (_isLoggedIn)
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              tooltip: '退出登录',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAccountSection(),
        const SizedBox(height: 12),
        _buildNoticeSection(),
        const SizedBox(height: 12),
        _buildQueueSection(),
        const SizedBox(height: 12),
        _buildMetaSection(),
      ],
    );
  }

  Widget _buildAccountSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark
        ? const Color(0xFFF1EAF8)
        : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);
    final avatarBg = isDark ? const Color(0xFF3A2A35) : const Color(0xFFFFEAF4);
    final avatarFg = isDark ? const Color(0xFFFF8BC8) : const Color(0xFFFF5DAF);

    if (!_isLoggedIn) {
      return Material(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.account_circle_outlined),
              title: Text('账号', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('登录或注册后管理您的个人资料'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: avatarBg,
              child: Icon(Icons.person, color: avatarFg),
            ),
            title: Text(
              _displayName(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
            subtitle: Text(
              _email ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subColor),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: Text(
              '账户设置',
              style: TextStyle(fontWeight: FontWeight.w700, color: titleColor),
            ),
            trailing: Icon(Icons.chevron_right, color: subColor),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark
        ? const Color(0xFFF1EAF8)
        : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    final text = (_announcement ?? '').trim();
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.campaign_outlined),
        title: Text(
          '公告',
          style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
        ),
        subtitle: Text(
          text.isEmpty ? '暂无公告' : text,
          style: TextStyle(color: subColor),
        ),
      ),
    );
  }

  Widget _buildMetaSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark
        ? const Color(0xFFF1EAF8)
        : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(
              '版本号',
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
            subtitle: Text(
              _latestVersion == null
                  ? _appVersion
                  : '$_appVersion · 有新版本 $_latestVersion',
              style: TextStyle(color: subColor),
            ),
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
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text(
              '原版及后端作者：鱼七',
              style: TextStyle(fontWeight: FontWeight.w700, color: titleColor),
            ),
            subtitle: Text(
              '本改版作者：wenwen12305',
              style: TextStyle(color: subColor),
            ),
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(
                '导出登录日志',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                ),
              ),
              subtitle: Text(
                '导出登录、令牌刷新和登录态检测记录',
                style: TextStyle(color: subColor),
              ),
              trailing: _authLogExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _authLogExporting ? null : _exportAuthLog,
            ),
          ListTile(
            leading: const Icon(Icons.open_in_new_outlined),
            title: Text(
              '访问项目github',
              style: TextStyle(fontWeight: FontWeight.w700, color: titleColor),
            ),
            subtitle: Text('ucrvk/suki', style: TextStyle(color: subColor)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final uri = Uri.parse('https://github.com/ucrvk/suki');
              final opened = await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
              if (opened) return;

              await Clipboard.setData(
                const ClipboardData(text: 'https://github.com/ucrvk/suki'),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('无法直接打开浏览器，已复制链接到剪贴板')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(
              '开源使用',
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
            subtitle: Text('查看开源许可', style: TextStyle(color: subColor)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(context: context, applicationName: 'suki');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQueueSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark
        ? const Color(0xFFF1EAF8)
        : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              '显示排队栏',
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
            subtitle: Text(
              QueueTabSettings.enabledNotifier.value
                  ? '底栏将显示排队入口'
                  : '打开后在底栏左侧显示排队入口',
              style: TextStyle(color: subColor),
            ),
            value: QueueTabSettings.enabledNotifier.value,
            onChanged: (enabled) =>
                unawaited(QueueTabSettings.setEnabled(enabled)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

String _signUpErrorMessage(Object error) {
  if (error is! AuthException) {
    return error.toString();
  }
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
  return error.message;
}
