import 'dart:async';

import 'package:flutter/material.dart';

import '../models/roster_entry.dart';
import '../models/booking_slot.dart';
import '../services/booking_slot_service.dart';
import '../services/roster_service.dart';
import '../theme/app_colors.dart';

abstract interface class RosterDataSource {
  Future<RosterSnapshot?> loadCached(String day);
  Future<RosterSnapshot> refresh(String day);
}

class RepositoryRosterDataSource implements RosterDataSource {
  RepositoryRosterDataSource([RosterRepository? repository])
    : _repository = repository ?? RosterRepository();

  final RosterRepository _repository;

  @override
  Future<RosterSnapshot?> loadCached(String day) => _repository.loadCached(day);

  @override
  Future<RosterSnapshot> refresh(String day) => _repository.refresh(day);
}

class RosterPageController {
  VoidCallback? _scrollToTop;
  VoidCallback? _refresh;

  void scrollToTop() => _scrollToTop?.call();
  void refresh() => _refresh?.call();
}

class RosterPage extends StatefulWidget {
  const RosterPage({
    super.key,
    this.controller,
    this.dataSource,
    this.slotDataSource,
  });

  final RosterPageController? controller;
  final RosterDataSource? dataSource;
  final BookingSlotDataSource? slotDataSource;

  @override
  State<RosterPage> createState() => _RosterPageState();
}

class _RosterPageState extends State<RosterPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _dayController = TextEditingController();
  late final RosterDataSource _dataSource;
  late final BookingSlotDataSource _slotDataSource;
  RosterSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _refreshing = false;

  List<BookingSlot> _slots = const [];
  BookingWindowState? _window;
  late DateTime _selectedDay;

  /// 每次切换选中日自增，丢弃过期的加载结果。
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? RepositoryRosterDataSource();
    _slotDataSource =
        widget.slotDataSource ?? RepositoryBookingSlotDataSource();
    _selectedDay = rosterDayOf(DateTime.now());
    _dayController.text = rosterDayKey(_selectedDay);
    widget.controller?._scrollToTop = _scrollToTop;
    widget.controller?._refresh = () => unawaited(_refresh(showFailure: true));
    unawaited(_init());
  }

  @override
  void dispose() {
    widget.controller?._scrollToTop = null;
    widget.controller?._refresh = null;
    _scrollController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  /// 先拉时间槽算出默认选中日，再加载该天排班。
  Future<void> _init() async {
    List<BookingSlot>? slots;
    try {
      slots = await _slotDataSource.fetchSlots();
    } catch (_) {
      // 时间槽拿不到时默认今天，快捷 chip 置灰。
    }
    if (!mounted) return;
    if (slots != null) _slots = slots;
    final window = resolveBookingWindow(_slots, DateTime.now());
    final today = rosterDayOf(DateTime.now());
    final defaultDay = window.isOpen
        ? today
        : (window.nextOpenAt != null ? rosterDayOf(window.nextOpenAt!) : today);
    setState(() {
      _window = window;
      _selectedDay = defaultDay;
      _dayController.text = rosterDayKey(defaultDay);
    });
    await _load();
  }

  Future<void> _load() async {
    final day = _selectedDay;
    final token = _loadToken;
    final key = rosterDayKey(day);
    try {
      final cached = await _dataSource.loadCached(key);
      if (!mounted || token != _loadToken) return;
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
    final day = _selectedDay;
    final token = ++_loadToken;
    final key = rosterDayKey(day);
    setState(() {
      _refreshing = true;
      if (_snapshot == null) _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _dataSource.refresh(key);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) return;
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
      if (mounted && token == _loadToken) {
        setState(() => _refreshing = false);
      }
    }
  }

  /// 切换到指定日期：先清空并尝试读取该天缓存。
  Future<void> _selectDay(DateTime day) async {
    final normalized = rosterDayOf(day);
    if (normalized == _selectedDay) return;
    _loadToken++;
    setState(() {
      _selectedDay = normalized;
      _dayController.text = rosterDayKey(normalized);
      _snapshot = null;
      _error = null;
      _loading = true;
      _refreshing = false;
    });
    await _load();
  }

  /// 手动输入日期：`YYYY-MM-DD`，非法时提示。
  void _applyManualDay(String raw) {
    final day = parseRosterDay(raw);
    if (day == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日期格式应为 YYYY-MM-DD，例如 2026-09-19')),
      );
      // 输入框回到当前选中日，避免显示一个非法值。
      _dayController.text = rosterDayKey(_selectedDay);
      return;
    }
    unawaited(_selectDay(day));
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
          _buildDaySelector(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  /// 日期选择区：上次/下次开放快捷 chip + 手动输入。
  ///
  /// 外层套透明 Material：宿主可能没有 Scaffold（纯 MaterialApp 挂载时）。
  Widget _buildDaySelector() {
    final window = _window;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _dayChip(
                  key: const Key('roster-prev-chip'),
                  label: _shortDayLabel(window?.prevOpenAt, '上次开放'),
                  day: window?.prevOpenAt,
                ),
                _dayChip(
                  key: const Key('roster-next-chip'),
                  label: _shortDayLabel(window?.nextOpenAt, '下次开放'),
                  day: window?.nextOpenAt,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('roster-day-input'),
                    controller: _dayController,
                    keyboardType: TextInputType.datetime,
                    onSubmitted: _applyManualDay,
                    decoration: InputDecoration(
                      labelText: '手动输入日期',
                      hintText: '2026-09-19',
                      helperText: '当前：${formatRosterDayLabel(_selectedDay)}',
                      filled: true,
                      fillColor: AppColors.field,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      labelStyle: const TextStyle(color: AppColors.textMuted),
                      helperStyle: const TextStyle(
                        color: AppColors.textDisabled,
                      ),
                    ),
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('roster-day-confirm'),
                  onPressed: () => _applyManualDay(_dayController.text),
                  icon: const Icon(Icons.check_circle_outline),
                  color: AppColors.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortDayLabel(DateTime? day, String prefix) {
    if (day == null) return '$prefix --';
    String two(int value) => value.toString().padLeft(2, '0');
    final local = day.toLocal();
    return '$prefix ${two(local.month)}月${two(local.day)}日';
  }

  Widget _dayChip({
    required Key key,
    required String label,
    required DateTime? day,
  }) {
    if (day == null) {
      // 时间槽未知（拉取失败）时置灰，仍展示占位文案。
      return ChoiceChip(
        key: key,
        label: Text(label),
        selected: false,
        onSelected: null,
        backgroundColor: AppColors.field,
        labelStyle: const TextStyle(color: AppColors.textDisabled),
        side: const BorderSide(color: AppColors.fieldDisabled),
      );
    }
    final selected = rosterDayOf(day) == rosterDayOf(_selectedDay);
    return ChoiceChip(
      key: key,
      label: Text(label),
      selected: selected,
      onSelected: (_) => unawaited(_selectDay(day)),
      selectedColor: AppColors.accent,
      backgroundColor: AppColors.field,
      labelStyle: TextStyle(
        color: selected ? AppColors.accentInk : AppColors.textMuted,
        fontWeight: FontWeight.w700,
      ),
      side: const BorderSide(color: AppColors.outline),
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
              const Icon(
                Icons.schedule_rounded,
                size: 18,
                color: AppColors.accent,
              ),
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
