import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/maid_catalog_cache_service.dart';
import '../services/fcm_service.dart';
import '../services/sysbooking_api_service.dart';
import '../services/sysbooking_session_store.dart';
import '../services/queue_tab_settings.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';
import 'account_settings_page.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  static const _notificationEnabledKey = 'notification_enabled';
  static const _bookingOpenEnabledKey = 'notification_booking_open_enabled';
  static const _queueNotificationEnabledKey = 'queue_notification_enabled';
  static const _queueNotificationFcmTokenKey = 'queue_notification_fcm_token';

  bool _loading = true;
  bool _isLoggedIn = false;
  bool _submitting = false;
  bool _notificationLoading = true;
  bool _notificationSubmitting = false;
  bool _notificationEnabled = false;
  bool _bookingOpenEnabled = false;
  bool _queueNotificationLoading = true;
  bool _queueNotificationSubmitting = false;
  bool _queueNotificationEnabled = false;
  String? _email;
  String? _username;
  String? _announcement;
  String _appVersion = '-';
  StreamSubscription<AuthState>? _authStateSub;
  late final VoidCallback _queueTabListener;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restoreAuth();
    _loadAnnouncement();
    _loadAppVersion();
    unawaited(_loadNotificationSettings());
    unawaited(_loadQueueNotificationSettings());
    unawaited(QueueTabSettings.load());
    _queueTabListener = () {
      if (mounted) {
        setState(() {});
      }
    };
    QueueTabSettings.enabledNotifier.addListener(_queueTabListener);
    _authStateSub = SupabaseService.client.auth.onAuthStateChange.listen((event) {
      _applySession(event.session);
    });
  }

  @override
  void dispose() {
    QueueTabSettings.enabledNotifier.removeListener(_queueTabListener);
    _authStateSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
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
        _appVersion = 'v1.0.0+1';
      });
    }
  }

  Future<void> _restoreAuth() async {
    try {
      var session = SupabaseService.client.auth.currentSession;
      if (session != null && session.expiresAt != null) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (session.expiresAt! <= now) {
          final refreshed = await SupabaseService.client.auth.refreshSession();
          session = refreshed.session;
        }
      }
      _applySession(session);
    } catch (_) {
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

  Future<void> _loadNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationEnabled = prefs.getBool(_notificationEnabledKey) ?? false;
    final bookingOpenEnabled = prefs.getBool(_bookingOpenEnabledKey) ?? false;
    final normalizedBookingOpenEnabled = notificationEnabled ? bookingOpenEnabled : false;
    final queueNotificationEnabled = prefs.getBool(_queueNotificationEnabledKey) ?? false;
    final normalizedQueueNotificationEnabled = notificationEnabled ? queueNotificationEnabled : false;

    if (!mounted) return;
    setState(() {
      _notificationEnabled = notificationEnabled;
      _bookingOpenEnabled = normalizedBookingOpenEnabled;
      _queueNotificationEnabled = normalizedQueueNotificationEnabled;
      _notificationLoading = false;
    });

    if (!notificationEnabled && bookingOpenEnabled) {
      await prefs.setBool(_bookingOpenEnabledKey, false);
    }

    if (!notificationEnabled && queueNotificationEnabled) {
      await prefs.setBool(_queueNotificationEnabledKey, false);
    }

    if (notificationEnabled && normalizedBookingOpenEnabled) {
      unawaited(FcmService.setBookingOpenTopicEnabled(true));
    }
  }

  Future<void> _saveNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationEnabledKey, _notificationEnabled);
    await prefs.setBool(_bookingOpenEnabledKey, _bookingOpenEnabled);
    if (!_notificationEnabled) {
      await prefs.setBool(_queueNotificationEnabledKey, false);
      setState(() {
        _queueNotificationEnabled = false;
      });
    }
  }

  Future<String?> _resolveQueueNotificationFcmToken({
    String? fallbackToken,
    bool allowFallback = true,
  }) async {
    try {
      final currentToken = await FcmService.getCurrentToken()
          .timeout(const Duration(seconds: 5));
      final normalizedCurrent = currentToken?.trim();
      if (normalizedCurrent != null && normalizedCurrent.isNotEmpty) {
        return normalizedCurrent;
      }
    } on TimeoutException {
      // Fall through to the cached token if allowed.
    } catch (_) {
      // Fall through to the cached token if allowed.
    }

    if (!allowFallback) return null;

    final normalizedFallback = fallbackToken?.trim();
    if (normalizedFallback != null && normalizedFallback.isNotEmpty) {
      return normalizedFallback;
    }
    return null;
  }

  Future<void> _loadQueueNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedEnabled = prefs.getBool(_queueNotificationEnabledKey) ?? false;
    final cachedToken = prefs.getString(_queueNotificationFcmTokenKey)?.trim();

    if (!mounted) return;
    setState(() {
      _queueNotificationEnabled = cachedEnabled;
      _queueNotificationLoading = false;
    });

    if (!cachedEnabled) return;

    final bookingToken = await SysbookingSessionStore.loadBookingToken();
    if (bookingToken == null) {
      if (!mounted) return;
      setState(() {
        _queueNotificationEnabled = false;
      });
      await prefs.setBool(_queueNotificationEnabledKey, false);
      return;
    }

    final resolvedFcmToken = await _resolveQueueNotificationFcmToken(
      fallbackToken: cachedToken,
      allowFallback: true,
    );
    if (resolvedFcmToken == null) {
      if (!mounted) return;
      setState(() {
        _queueNotificationEnabled = false;
      });
      await prefs.setBool(_queueNotificationEnabledKey, false);
      return;
    }

    try {
      await SysbookingApiService.setQueueNotificationEnabled(
        bookingToken: bookingToken,
        fcmToken: resolvedFcmToken,
        enabled: true,
      );
      await prefs.setString(_queueNotificationFcmTokenKey, resolvedFcmToken);
      await prefs.setBool(_queueNotificationEnabledKey, true);
    } on SysbookingUnauthorizedException {
      await SysbookingSessionStore.clearBookingToken();
      if (!mounted) return;
      setState(() {
        _queueNotificationEnabled = false;
      });
      await prefs.setBool(_queueNotificationEnabledKey, false);
    } catch (_) {
      // Keep the local state as-is on transient failures.
    }
  }

  Future<void> _saveQueueNotificationSettings({
    required bool enabled,
    String? fcmToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_queueNotificationEnabledKey, enabled);
    if (fcmToken != null && fcmToken.trim().isNotEmpty) {
      await prefs.setString(_queueNotificationFcmTokenKey, fcmToken.trim());
    }
  }

  Future<void> _setQueueNotificationEnabled(bool enabled) async {
    if (_queueNotificationSubmitting) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _queueNotificationSubmitting = true;
    });

    try {
      final bookingToken = await SysbookingSessionStore.loadBookingToken();
      if (bookingToken == null) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('请先到排队页完成登录，再开启排队通知')),
        );
        return;
      }

      if (enabled) {
        await FcmService.requestNotificationPermission();
        final fcmToken = await _resolveQueueNotificationFcmToken(
          allowFallback: false,
        );
        if (fcmToken == null) {
          throw const SysbookingApiException('无法获取 FCM token');
        }

        await SysbookingApiService.setQueueNotificationEnabled(
          bookingToken: bookingToken,
          fcmToken: fcmToken,
          enabled: true,
        );
        if (!mounted) return;
        setState(() {
          _queueNotificationEnabled = true;
        });
        await _saveQueueNotificationSettings(
          enabled: true,
          fcmToken: fcmToken,
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        final cachedToken = prefs.getString(_queueNotificationFcmTokenKey);
        final fcmToken = await _resolveQueueNotificationFcmToken(
          fallbackToken: cachedToken,
          allowFallback: true,
        );
        if (fcmToken == null) {
          throw const SysbookingApiException('无法获取 FCM token');
        }

        await SysbookingApiService.setQueueNotificationEnabled(
          bookingToken: bookingToken,
          fcmToken: fcmToken,
          enabled: false,
        );
        if (!mounted) return;
        setState(() {
          _queueNotificationEnabled = false;
        });
        await _saveQueueNotificationSettings(
          enabled: false,
          fcmToken: fcmToken,
        );
      }
    } on NotificationPermissionDeniedException catch (e) {
      if (!mounted) return;
      if (e.needsAppSettings) {
        await openAppSettings();
      }
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } on SysbookingUnauthorizedException catch (e) {
      await SysbookingSessionStore.clearBookingToken();
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } on SysbookingApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _queueNotificationSubmitting = false;
        });
      } else {
        _queueNotificationSubmitting = false;
      }
    }
  }

  Future<void> _setNotificationEnabled(bool enabled) async {
    if (_notificationSubmitting) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _notificationSubmitting = true;
    });

    try {
      if (enabled) {
        try {
          await FcmService.requestNotificationPermission();
          if (!mounted) return;
          setState(() {
            _notificationEnabled = true;
          });
          await _saveNotificationSettings();
          if (_bookingOpenEnabled) {
            try {
              await FcmService.setBookingOpenTopicEnabled(true);
            } catch (e) {
              if (!mounted) return;
              setState(() {
                _bookingOpenEnabled = false;
              });
              await _saveNotificationSettings();
              messenger.showSnackBar(SnackBar(content: Text(e.toString())));
            }
          }
        } on NotificationPermissionDeniedException catch (e) {
          if (!mounted) return;
          if (e.needsAppSettings) {
            await openAppSettings();
          }
          setState(() {
            _notificationEnabled = false;
            _bookingOpenEnabled = false;
            _queueNotificationEnabled = false;
          });
          await _saveNotificationSettings();
          await FcmService.setBookingOpenTopicEnabled(false);
          messenger.showSnackBar(SnackBar(content: Text(e.toString())));
        }
      } else {
        try {
          await FcmService.setBookingOpenTopicEnabled(false);
          if (!mounted) return;
          setState(() {
            _notificationEnabled = false;
            _bookingOpenEnabled = false;
            _queueNotificationEnabled = false;
          });
          await _saveNotificationSettings();
        } catch (e) {
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _notificationSubmitting = false;
        });
      } else {
        _notificationSubmitting = false;
      }
    }
  }

  Future<void> _setBookingOpenEnabled(bool enabled) async {
    if (_notificationSubmitting || !_notificationEnabled) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _notificationSubmitting = true;
    });

    try {
      setState(() {
        _bookingOpenEnabled = enabled;
      });
      await FcmService.setBookingOpenTopicEnabled(enabled);
      await _saveNotificationSettings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookingOpenEnabled = !enabled;
      });
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() {
          _notificationSubmitting = false;
        });
      } else {
        _notificationSubmitting = false;
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
    _emailController.text = _email ?? '';
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入邮箱和密码')),
                );
                return;
              }

              setDialogState(() => _submitting = true);

              try {
                final authResponse = await SupabaseService.client.auth.signInWithPassword(
                  email: email,
                  password: password,
                );
                _applySession(authResponse.session);
                if (!context.mounted) return;
                Navigator.of(context).pop();
              } on AuthException catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
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
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '邮箱'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码'),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(),
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
        _buildNotificationSection(),
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
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);
    final avatarBg = isDark ? const Color(0xFF3A2A35) : const Color(0xFFFFEAF4);
    final avatarFg = isDark ? const Color(0xFFFF8BC8) : const Color(0xFFFF5DAF);

    if (!_isLoggedIn) {
      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [
          const ListTile(
            leading: Icon(Icons.account_circle_outlined),
            title: Text(
              '账号',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _showLoginDialog,
                child: const Text('登录'),
              ),
            ),
          ),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
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
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    final text = (_announcement ?? '').trim();
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: const Icon(Icons.campaign_outlined),
        title: Text('公告', style: TextStyle(fontWeight: FontWeight.w800, color: titleColor)),
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
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('版本号', style: TextStyle(fontWeight: FontWeight.w800, color: titleColor)),
            subtitle: Text(_appVersion, style: TextStyle(color: subColor)),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: Text('原版及后端作者：鱼七', style: TextStyle(fontWeight: FontWeight.w700, color: titleColor)),
            subtitle: Text('本改版作者：wenwen12305', style: TextStyle(color: subColor)),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new_outlined),
            title: Text('访问项目github', style: TextStyle(fontWeight: FontWeight.w700, color: titleColor)),
            subtitle: Text(
              'ucrvk/suki',
              style: TextStyle(color: subColor),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final uri = Uri.parse('https://github.com/ucrvk/suki');
              final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (opened) return;

              await Clipboard.setData(const ClipboardData(text: 'https://github.com/ucrvk/suki'));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('无法直接打开浏览器，已复制链接到剪贴板')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text('开源使用', style: TextStyle(fontWeight: FontWeight.w800, color: titleColor)),
            subtitle: Text('查看开源许可', style: TextStyle(color: subColor)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'suki',
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_none_rounded),
            title: Text(
              '通知设置',
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
            subtitle: Text(
              '为了在应用关闭时仍然能接收到消息，请开启自启动权限',
              style: TextStyle(color: subColor),
            ),
          ),
          if (_notificationLoading)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text('通知总开关'),
              subtitle: Text(
                '开启后可接收系统通知',
                style: TextStyle(color: subColor),
              ),
              value: _notificationEnabled,
              onChanged: _notificationSubmitting ? null : _setNotificationEnabled,
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text('订阅预约开始提示'),
              subtitle: Text(
                _notificationEnabled ? '订阅 booking_open topic' : '请先打开总开关',
                style: TextStyle(color: subColor),
              ),
              value: _bookingOpenEnabled,
              onChanged: (!_notificationEnabled || _notificationSubmitting)
                  ? null
                  : _setBookingOpenEnabled,
            ),
              if (QueueTabSettings.enabledNotifier.value)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text('排队通知'),
                  subtitle: Text(
                    _queueNotificationLoading
                        ? '正在恢复排队通知状态'
                        : !_notificationEnabled
                            ? '请先打开通知总开关'
                        : _queueNotificationEnabled
                            ? '已同步排队相关通知'
                            : '开启后会先发送当前设备的 FCM token',
                    style: TextStyle(color: subColor),
                  ),
                  value: _queueNotificationEnabled,
                  onChanged: (_queueNotificationLoading || _queueNotificationSubmitting || !_notificationEnabled)
                      ? null
                      : (enabled) => unawaited(_setQueueNotificationEnabled(enabled)),
                ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildQueueSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
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
              QueueTabSettings.enabledNotifier.value ? '底栏将显示排队入口' : '打开后在底栏左侧显示排队入口',
              style: TextStyle(color: subColor),
            ),
            value: QueueTabSettings.enabledNotifier.value,
            onChanged: _notificationSubmitting ? null : (enabled) => unawaited(QueueTabSettings.setEnabled(enabled)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
