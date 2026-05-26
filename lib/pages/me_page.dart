import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/maid_catalog_cache_service.dart';
import '../services/supabase_service.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  bool _loading = true;
  bool _isLoggedIn = false;
  bool _submitting = false;
  String? _email;
  String? _username;
  String? _announcement;
  StreamSubscription<AuthState>? _authStateSub;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _restoreAuth();
    _loadAnnouncement();
    _authStateSub = SupabaseService.client.auth.onAuthStateChange.listen((event) {
      _applySession(event.session);
    });
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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

  Future<void> _loadAnnouncement() async {
    try {
      final snapshot = await MaidCatalogCacheService.getSnapshot();
      final announcement = snapshot.announcement;
      if (!mounted) return;
      setState(() {
        _announcement = announcement;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _announcement = '';
      });
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
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF3EFF5),
        title: const Text(
          '我',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
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
        _buildMetaSection(),
      ],
    );
  }

  Widget _buildAccountSection() {
    if (!_isLoggedIn) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFFFEAF4),
          child: Icon(Icons.person, color: Color(0xFFFF5DAF)),
        ),
        title: Text(
          _displayName(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3A3250)),
        ),
        subtitle: Text(
          _email ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF7A7188)),
        ),
      ),
    );
  }

  Widget _buildNoticeSection() {
    final text = (_announcement ?? '').trim();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: ListTile(
        leading: const Icon(Icons.campaign_outlined),
        title: const Text('公告', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3A3250))),
        subtitle: Text(
          text.isEmpty ? '暂无公告' : text,
          style: const TextStyle(color: Color(0xFF7A7188)),
        ),
      ),
    );
  }

  Widget _buildMetaSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('版本号', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3A3250))),
            subtitle: Text('v1.0.0', style: TextStyle(color: Color(0xFF7A7188))),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('开源使用', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF3A3250))),
            subtitle: const Text('查看开源许可', style: TextStyle(color: Color(0xFF7A7188))),
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
}
