import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../theme/app_colors.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    required this.account,
    required this.authService,
    required this.profileService,
    super.key,
  });

  final AccountIdentity account;
  final AccountAuthService authService;
  final AccountProfileService profileService;

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
    _loadProfile();
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
    try {
      final profile = await widget.profileService.load(widget.account.id);
      if (!mounted) return;
      _usernameController.text = profile.username.isEmpty
          ? widget.account.usernameMetadata
          : profile.username;
      _qqNameController.text = profile.qqName;
      _avatarUrlController.text = profile.avatarUrl;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(accountErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('用户名不能为空')));
      return;
    }
    setState(() => _profileSubmitting = true);
    try {
      await widget.profileService.save(
        widget.account.id,
        AccountProfile(
          username: username,
          qqName: _qqNameController.text.trim(),
          avatarUrl: _avatarUrlController.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('资料保存成功')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(accountErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _profileSubmitting = false);
    }
  }

  Future<void> _changePassword() async {
    final password = _newPasswordController.text;
    if (password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入新密码')));
      return;
    }
    if (password != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('两次输入的密码不一致')));
      return;
    }
    setState(() => _passwordSubmitting = true);
    try {
      await widget.authService.updatePassword(password);
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密码修改成功')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(accountErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _passwordSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账户设置'),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          _buildProfileCard(),
          const SizedBox(height: 14),
          _buildPasswordCard(),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.outline),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.person_outline),
            title: Text('个人资料', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (_profileLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )
          else ...[
            TextField(
              key: const Key('profile-username'),
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('profile-qq-name'),
              controller: _qqNameController,
              decoration: const InputDecoration(
                labelText: 'QQ昵称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('profile-avatar-url'),
              controller: _avatarUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '头像链接',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('save-profile-button'),
                onPressed: _profileSubmitting ? null : _saveProfile,
                child: _profileSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存资料'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.outline),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.lock_outline_rounded),
            title: Text('修改密码', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          TextField(
            key: const Key('new-password'),
            controller: _newPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '新密码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('confirm-password'),
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '确认密码',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _changePassword(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('change-password-button'),
              onPressed: _passwordSubmitting ? null : _changePassword,
              child: _passwordSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确认修改'),
            ),
          ),
        ],
      ),
    );
  }
}
