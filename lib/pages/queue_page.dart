import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_shell.dart';
import '../services/sysbooking_api_service.dart';
import '../services/sysbooking_session_store.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class QueuePage extends StatefulWidget {
  const QueuePage({super.key});

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueuePageState extends State<QueuePage> {
  final ScrollController _scrollController = ScrollController();
  late final VoidCallback _tabListener;
  late final VoidCallback _tabReselectListener;

  bool _loading = false;
  bool _promptingLogin = false;
  bool _bootstrapped = false;
  String? _error;
  String? _bookingToken;
  List<SysbookingQueueItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _tabListener = _handleTabChanged;
    _tabReselectListener = _handleTabReselect;
    AppShell.tabIndexNotifier.addListener(_tabListener);
    AppShell.tabReselectNotifier.addListener(_tabReselectListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeBootstrap());
    });
  }

  @override
  void dispose() {
    AppShell.tabIndexNotifier.removeListener(_tabListener);
    AppShell.tabReselectNotifier.removeListener(_tabReselectListener);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    if (AppShell.tabIndexNotifier.value == AppShell.queueTabIndex()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_maybeBootstrap(forceRefresh: true));
      });
    }
  }

  void _handleTabReselect() {
    if (!mounted) return;
    final event = AppShell.tabReselectNotifier.value;
    if (event == null || event.index != AppShell.queueTabIndex()) return;
    if (event.action == TabReselectAction.scrollToTop) {
      if (_scrollController.hasClients) {
        unawaited(_scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ));
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_maybeBootstrap(forceRefresh: true));
    });
  }

  Future<void> _maybeBootstrap({bool forceRefresh = false}) async {
    if (!mounted) return;
    if (AppShell.tabIndexNotifier.value != AppShell.queueTabIndex() && !forceRefresh) {
      return;
    }
    if (_loading) return;
    if (!_bootstrapped && !forceRefresh) {
      _bootstrapped = true;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final cachedToken = await SysbookingSessionStore.loadBookingToken();
      if (cachedToken != null) {
        try {
          final items = await SysbookingApiService.fetchQueueList(cachedToken);
          if (!mounted) return;
          setState(() {
            _bookingToken = cachedToken;
            _items = items;
            _loading = false;
          });
          return;
        } on SysbookingUnauthorizedException {
          await SysbookingSessionStore.clearBookingToken();
        }
      }

      final email = await _resolvePrefillEmail();
      final credentials = await _showLoginDialog(prefillEmail: email);
      if (credentials == null) {
        if (!mounted) return;
        setState(() {
          _bookingToken = null;
          _items = const [];
          _loading = false;
          _error = '需要登录后才能查看排队预约';
        });
        return;
      }

      final token = await SysbookingApiService.exchangeSessionForBookingToken(
        session: credentials.session,
      );
      await SysbookingSessionStore.saveBookingToken(token);
      await SysbookingSessionStore.saveLastEmail(credentials.email);
      final items = await SysbookingApiService.fetchQueueList(token);
      if (!mounted) return;
      setState(() {
        _bookingToken = token;
        _items = items;
        _loading = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on SysbookingApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      if (e is SysbookingUnauthorizedException) {
        await SysbookingSessionStore.clearBookingToken();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<String?> _resolvePrefillEmail() async {
    final currentEmail = SupabaseService.client.auth.currentUser?.email?.trim();
    if (currentEmail != null && currentEmail.isNotEmpty) return currentEmail;
    return SysbookingSessionStore.loadLastEmail();
  }

  Future<_LoginResult?> _showLoginDialog({String? prefillEmail}) async {
    if (_promptingLogin) return null;
    _promptingLogin = true;

    final emailController = TextEditingController(text: prefillEmail ?? '');
    final passwordController = TextEditingController();
    var submitting = false;
    var completed = false;

    try {
      return await showDialog<_LoginResult>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> submit() async {
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (email.isEmpty || password.isEmpty) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('请输入邮箱和密码')),
                  );
                  return;
                }

                setDialogState(() => submitting = true);

                try {
                  final authResponse = await SupabaseService.client.auth.signInWithPassword(
                    email: email,
                    password: password,
                  );
                  final session = authResponse.session;
                  if (session == null) {
                    throw Exception('登录失败，未获取到会话');
                  }
                  if (!dialogContext.mounted) return;
                  completed = true;
                  Navigator.of(dialogContext).pop(_LoginResult(email: email, session: session));
                } on AuthException catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                } catch (e) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                } finally {
                  if (dialogContext.mounted && !completed) {
                    setDialogState(() => submitting = false);
                  } else {
                    submitting = false;
                  }
                }
              }

              return AlertDialog(
                title: const Text('登录'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: '邮箱'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '密码'),
                      onSubmitted: (_) => submit(),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: submitting ? null : submit,
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录并导入'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      emailController.dispose();
      passwordController.dispose();
      _promptingLogin = false;
    }
  }

  String _timeslotLabel(int timeslot) {
    switch (timeslot) {
      case 21:
        return '21';
      case 22:
        return '22';
      default:
        return timeslot.toString();
    }
  }

  String _queueLabel(int queue) {
    if (queue <= 0) return '前面无人';
    return '前面 $queue 人';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(
        title: const Text('排队'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => unawaited(_maybeBootstrap(forceRefresh: true)),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _maybeBootstrap(forceRefresh: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeaderCard(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildErrorState()
            else if (_items.isEmpty)
              _buildEmptyState()
            else
              ..._items.map(_buildQueueCard),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: const Icon(Icons.queue_play_next_rounded),
        title: Text(
          '我的排队预约',
          style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
        ),
        subtitle: Text(
          _bookingToken == null ? '需要登录后才能查看' : '已加载当前登录用户的 waiting 预约',
          style: TextStyle(color: subColor),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 42, color: subColor),
          const SizedBox(height: 12),
          Text(
            '暂无正在排队的预约',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: titleColor),
          ),
          const SizedBox(height: 6),
          Text(
            '如果你有 waiting 状态的预约，这里会列出来。',
            textAlign: TextAlign.center,
            style: TextStyle(color: subColor),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 42, color: subColor),
          const SizedBox(height: 12),
          Text(
            '加载失败',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: titleColor),
          ),
          const SizedBox(height: 6),
          Text(
            _error ?? '未知错误',
            textAlign: TextAlign.center,
            style: TextStyle(color: subColor),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => unawaited(_maybeBootstrap(forceRefresh: true)),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueCard(SysbookingQueueItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);
    final subColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7A7188);
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.12),
          child: Icon(Icons.badge_outlined, color: accent),
        ),
        title: Text(
          item.maidId,
          style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('时段 ${_timeslotLabel(item.timeslot)}', style: TextStyle(color: subColor)),
              const SizedBox(height: 4),
              Text(_queueLabel(item.queue), style: TextStyle(color: subColor)),
              const SizedBox(height: 4),
              Text(
                item.autoqueue ? '自动排队：开启' : '自动排队：关闭',
                style: TextStyle(color: subColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginResult {
  const _LoginResult({
    required this.email,
    required this.session,
  });

  final String email;
  final Session session;
}
