import 'dart:async';

import 'package:flutter/material.dart';

import '../models/roster_entry.dart';
import '../services/roster_service.dart';
import '../theme/app_colors.dart';

abstract interface class RosterDataSource {
  Future<RosterSnapshot?> loadCached();
  Future<RosterSnapshot> refresh();
}

class RepositoryRosterDataSource implements RosterDataSource {
  RepositoryRosterDataSource([RosterRepository? repository])
    : _repository = repository ?? RosterRepository();

  final RosterRepository _repository;

  @override
  Future<RosterSnapshot?> loadCached() => _repository.loadCached();

  @override
  Future<RosterSnapshot> refresh() => _repository.refresh();
}

class RosterPageController {
  VoidCallback? _scrollToTop;
  VoidCallback? _refresh;

  void scrollToTop() => _scrollToTop?.call();
  void refresh() => _refresh?.call();
}

class RosterPage extends StatefulWidget {
  const RosterPage({super.key, this.controller, this.dataSource});

  final RosterPageController? controller;
  final RosterDataSource? dataSource;

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {

  final ScrollController _scrollController = ScrollController();
  late final RosterDataSource _dataSource;
  RosterSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? RepositoryRosterDataSource();
    widget.controller?._scrollToTop = _scrollToTop;
    widget.controller?._refresh = () => unawaited(_refresh(showFailure: true));
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.controller?._scrollToTop = null;
    widget.controller?._refresh = null;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final cached = await _dataSource.loadCached();
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _snapshot = cached;
          _loading = false;
        });
        unawaited(_refresh(showFailure: true));
        return;
      }
    } catch (_) {
      // A broken cache must never prevent a network refresh.
    }
    await _refresh(showFailure: false);
  }

  Future<void> _refresh({required bool showFailure}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (_snapshot == null) _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _dataSource.refresh();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (_snapshot == null) {
        setState(() {
          _error = error;
          _loading = false;
        });
      } else if (showFailure) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('刷新失败，已保留本地排班')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '排班',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (_refreshing)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: '排班加载失败',
        message: _error.toString(),
        actionLabel: '重试',
        onAction: () => _refresh(showFailure: false),
      );
    }

    final sessions = groupRosterEntries(_snapshot?.entries ?? const []);
    if (sessions.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refresh(showFailure: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            _MessageState(
              icon: Icons.event_available_outlined,
              title: '暂无排班',
              message: '下拉即可重新获取',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(showFailure: true),
      child: ListView.separated(
        key: const Key('roster-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: sessions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) => _buildSessionCard(sessions[index]),
      ),
    );
  }

  Widget _buildSessionCard(RosterSession session) {
    final localStart = session.sessionAt.toLocal();
    final localEnd = session.sessionEnd?.toLocal();
    return Container(
      key: ValueKey(
        '${session.scriptName}-${session.sessionAt.toUtc().toIso8601String()}',
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.scriptName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  formatSessionTime(localStart, localEnd),
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.divider),
          for (final entry in session.entries) _buildBooking(entry),
        ],
      ),
    );
  }

  Widget _buildBooking(RosterEntry entry) {
    return Padding(
      key: ValueKey(entry.bookingId),
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.field,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.groups_2_outlined, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.groupName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.guests} 人',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                if (entry.companions.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final companion in entry.companions)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          side: BorderSide.none,
                          backgroundColor: AppColors.field,
                          avatar: const Icon(Icons.person_outline, size: 16),
                          label: Text(companion),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String formatSessionTime(DateTime start, DateTime? end) {
  final date = '${_twoDigits(start.month)}月${_twoDigits(start.day)}日';
  final startTime = '${_twoDigits(start.hour)}:${_twoDigits(start.minute)}';
  if (end == null) return '$date  $startTime';
  final isSameDay =
      start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  final endTime = '${_twoDigits(end.hour)}:${_twoDigits(end.minute)}';
  if (isSameDay) return '$date  $startTime - $endTime';
  return '$date  $startTime - '
      '${_twoDigits(end.month)}月${_twoDigits(end.day)}日  $endTime';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 50, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
