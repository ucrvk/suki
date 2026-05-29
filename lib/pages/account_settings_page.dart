import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _usernameController = TextEditingController();
  final _qqNameController = TextEditingController();
  final _avatarUrlController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _profileLoading = true;
  bool _profileSubmitting = false;
  bool _passwordSubmitting = false;

  @override
  void initState() {
    super.initState();
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _qqNameController.dispose();
    _avatarUrlController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    try {
      final data = await SupabaseService.client
          .from('suki_profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _profileLoading = false;
        _usernameController.text = (data?['username'] ?? '').toString();
        _qqNameController.text = (data?['qq_name'] ?? '').toString();
        _avatarUrlController.text = (data?['avatar_url'] ?? '').toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _profileLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户名不能为空')),
      );
      return;
    }

    setState(() => _profileSubmitting = true);

    try {
      await SupabaseService.client.from('suki_profiles').update({
        'username': username,
        'qq_name': _qqNameController.text.trim().isEmpty
            ? null
            : _qqNameController.text.trim(),
        'avatar_url': _avatarUrlController.text.trim().isEmpty
            ? null
            : _avatarUrlController.text.trim(),
      }).eq('id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资料保存成功')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _profileSubmitting = false);
    }
  }

  Future<void> _changePassword() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入新密码')),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('两次输入的密码不一致')),
      );
      return;
    }

    setState(() => _passwordSubmitting = true);

    try {
      await SupabaseService.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码修改成功')),
      );
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _passwordSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(
        title: Text('账户设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProfileSection(),
          const SizedBox(height: 12),
          _buildPasswordSection(),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              '个人资料',
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
          ),
          if (_profileLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _qqNameController,
                decoration: const InputDecoration(
                  labelText: 'QQ昵称',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _avatarUrlController,
                decoration: const InputDecoration(
                  labelText: '头像链接',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _profileSubmitting ? null : _saveProfile,
                  child: _profileSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存资料'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF3A3250);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(
              '修改密码',
              style: TextStyle(fontWeight: FontWeight.w800, color: titleColor),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '新密码',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '确认密码',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _changePassword(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _passwordSubmitting ? null : _changePassword,
                child: _passwordSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('确认修改'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
