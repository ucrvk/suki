import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/schedule_cache_service.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const _pink = Color(0xFFFF66B5);

  bool _loading = true;
  String? _error;
  ScheduleSnapshot? _schedule;
  User? _currentUser;
  StreamSubscription<AuthState>? _authStateSub;

  @override
  void initState() {
    super.initState();
    _currentUser = SupabaseService.client.auth.currentUser;
    _authStateSub = SupabaseService.client.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      setState(() {
        _currentUser = event.session?.user;
      });
    });
    _loadSchedule();
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSchedule({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final schedule = await ScheduleCacheService.getTodaySchedule(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _schedule = schedule;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _columnCount(double width) {
    if (width >= 1800) return 5;
    if (width >= 1400) return 4;
    if (width >= 1100) return 3;
    if (width >= 760) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(title: Text('排班 ${_schedule?.date ?? ''}')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('请求失败: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _loadSchedule(forceRefresh: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final schedule = _schedule;
    if (schedule == null || schedule.maids.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadSchedule(forceRefresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(child: Text('今日暂无排班')),
          ],
        ),
      );
    }

    final appointmentsByMaid = <String, List<ScheduleAppointment>>{};
    for (final a in schedule.appointments) {
      if (a.maidVrcid.isEmpty) continue;
      appointmentsByMaid.putIfAbsent(a.maidVrcid, () => <ScheduleAppointment>[]).add(a);
    }

    return RefreshIndicator(
      onRefresh: () => _loadSchedule(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = _columnCount(constraints.maxWidth);
          final spacing = 14.0;
          final itemWidth = (constraints.maxWidth - spacing * (cols - 1) - 32) / cols;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              if (_currentUser != null) ...[
                _buildMyAppointmentsCard(schedule),
                const SizedBox(height: 14),
              ],
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final maid in schedule.maids)
                    SizedBox(
                      width: itemWidth,
                      child: _buildMaidCard(
                        maid: maid,
                        timeSlots: schedule.timeSlots,
                        appointments: appointmentsByMaid[maid.vrcid] ?? const [],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMyAppointmentsCard(ScheduleSnapshot schedule) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF5A5056);
    final mutedColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7D7178);
    final userId = _currentUser?.id ?? '';
    final myAppointments = schedule.appointments
        .where((a) => a.guestUserId == userId && a.timeSlot.isNotEmpty)
        .toList();

    final bySlot = <String, ScheduleAppointment>{};
    for (final appointment in myAppointments) {
      bySlot[appointment.timeSlot] = appointment;
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '您的预约',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFEFD7E2)),
          const SizedBox(height: 12),
          if (schedule.timeSlots.isEmpty)
            Text('今日未配置时段', style: TextStyle(color: mutedColor))
          else
            for (final slot in schedule.timeSlots) ...[
              _buildMySlotLine(slot, bySlot[slot]),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _buildMySlotLine(String slot, ScheduleAppointment? appointment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFFFF3F8);
    final normalText = isDark ? const Color(0xFFEDE5F3) : const Color(0xFF5A5056);
    final mutedText = isDark ? const Color(0xFF9A8FA4) : const Color(0xFF9A8FA4);
    final hasBooking = appointment != null;
    final maidName = hasBooking
        ? (appointment.maidName.isEmpty ? '未命名女仆' : appointment.maidName)
        : '未预约';
    final withFriend = hasBooking && appointment.withFriend;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: lineBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              slot,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _pink,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 18,
                color: hasBooking ? const Color(0xFF6A4D93) : const Color(0xFF9A8FA4),
              ),
              const SizedBox(width: 6),
              Text(
                maidName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: hasBooking ? normalText : mutedText,
                ),
              ),
              if (withFriend) ...[
                const SizedBox(width: 8),
                const Text(
                  '+1',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _pink,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMaidCard({
    required ScheduleMaid maid,
    required List<String> timeSlots,
    required List<ScheduleAppointment> appointments,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF5A5056);
    final mutedColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7D7178);
    final slotToAppointments = <String, List<ScheduleAppointment>>{};
    for (final slot in timeSlots) {
      slotToAppointments[slot] = <ScheduleAppointment>[];
    }
    for (final a in appointments) {
      slotToAppointments.putIfAbsent(a.timeSlot, () => <ScheduleAppointment>[]).add(a);
    }

    for (final list in slotToAppointments.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final bookedCount = slotToAppointments.values.where((list) => list.isNotEmpty).length;
    final isFull = timeSlots.isNotEmpty && bookedCount >= timeSlots.length;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '🐱 ${maid.maidName.isEmpty ? maid.name : maid.maidName}',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
              const Spacer(),
              Text(
                '预约 $bookedCount 人',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _pink,
                ),
              ),
              if (isFull) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _pink,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '预约已满',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFEFD7E2)),
          const SizedBox(height: 12),
          if (timeSlots.isEmpty)
            Text('今日未配置时段', style: TextStyle(color: mutedColor))
          else
            for (final slot in timeSlots) ...[
              _buildSlotLine(slot, slotToAppointments[slot] ?? const []),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Widget _buildSlotLine(String slot, List<ScheduleAppointment> list) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFFFF3F8);
    final normalText = isDark ? const Color(0xFFEDE5F3) : const Color(0xFF5A5056);
    final mutedText = isDark ? const Color(0xFF9A8FA4) : const Color(0xFF9A8FA4);
    final booked = list.isNotEmpty;
    final first = booked ? list.first : null;
    final withFriend = booked && first!.withFriend;

    String guestText;
    if (!booked) {
      guestText = '空闲';
    } else {
      final base = (first!.guest.isEmpty ? '匿名' : first.guest);
      guestText = base;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: lineBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              slot,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _pink,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person,
                size: 18,
                color: booked ? const Color(0xFF6A4D93) : const Color(0xFF9A8FA4),
              ),
              const SizedBox(width: 6),
              Text(
                guestText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: booked ? normalText : mutedText,
                ),
              ),
              if (withFriend) ...[
                const SizedBox(width: 8),
                const Text(
                  '+1',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _pink,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
