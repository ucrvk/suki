import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_shell.dart';
import '../services/maid_catalog_cache_service.dart';
import '../services/supabase_service.dart';
import '../widgets/main_app_bar.dart';

class _ReservationEntry {
  const _ReservationEntry({
    required this.guest,
    required this.guestUserId,
    required this.maidName,
    required this.maidVrcid,
    required this.timeSlot,
    required this.withFriend,
    required this.createdAt,
  });

  final String guest;
  final String guestUserId;
  final String maidName;
  final String maidVrcid;
  final String timeSlot;
  final bool withFriend;
  final int createdAt;
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const _pink = Color(0xFFFF66B5);

  bool _loading = true;
  String? _error;
  MaidCatalogSnapshot? _snapshot;
  User? _currentUser;
  StreamSubscription<AuthState>? _authStateSub;
  String? _cancelingReservationKey;
  final ScrollController _scrollController = ScrollController();
  late final VoidCallback _tabReselectListener;

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
    _tabReselectListener = () {
      final event = AppShell.tabReselectNotifier.value;
      if (event == null || event.index != 1) return;
      _handleTabReselect(event.action);
    };
    AppShell.tabReselectNotifier.addListener(_tabReselectListener);
    _loadData();
  }

  @override
  void dispose() {
    AppShell.tabReselectNotifier.removeListener(_tabReselectListener);
    _authStateSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleTabReselect(TabReselectAction action) async {
    if (action == TabReselectAction.scrollToTop) {
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    await _loadData(forceRefresh: true);
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await MaidCatalogCacheService.getSnapshot(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
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

  List<_ReservationEntry> _parseReservations(List<Map<String, dynamic>> rows) {
    return rows
        .map(
          (a) => _ReservationEntry(
            guest: (a['guestUsername'] ?? '').toString().trim(),
            guestUserId: (a['guestUserId'] ?? '').toString().trim(),
            maidName: (a['maidName'] ?? '').toString().trim(),
            maidVrcid: (a['maidVrcid'] ?? '').toString().trim(),
            timeSlot: (a['timeSlot'] ?? '').toString().trim(),
            withFriend: a['withFriend'] == true,
            createdAt: a['createdAt'] is num ? (a['createdAt'] as num).toInt() : 0,
          ),
        )
        .where((e) => e.maidVrcid.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: Text('排班')),
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
                onPressed: () => _loadData(forceRefresh: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null || snapshot.maids.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 220),
            Center(child: Text('暂无女仆数据')),
          ],
        ),
      );
    }

    final visibleMaids = snapshot.maids.where((m) {
      final vrcid = (m['vrcid'] ?? '').toString().trim();
      return vrcid.isNotEmpty && !snapshot.hiddenMaidVrcids.contains(vrcid);
    }).toList();
    final reservations = _parseReservations(snapshot.reservations);

    final appointmentsByMaid = <String, List<_ReservationEntry>>{};
    for (final a in reservations) {
      appointmentsByMaid.putIfAbsent(a.maidVrcid, () => <_ReservationEntry>[]).add(a);
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cols = _columnCount(constraints.maxWidth);
          final spacing = 14.0;
          final itemWidth = (constraints.maxWidth - spacing * (cols - 1) - 32) / cols;

          return ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              if (_currentUser != null) ...[
                _buildMyAppointmentsCard(snapshot.timeSlots, reservations),
                const SizedBox(height: 14),
              ],
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final maid in visibleMaids)
                    SizedBox(
                      width: itemWidth,
                      child: _buildMaidCard(
                        maid: maid,
                        timeSlots: snapshot.timeSlots,
                        appointments: appointmentsByMaid[(maid['vrcid'] ?? '').toString().trim()] ?? const [],
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

  Widget _buildMyAppointmentsCard(List<String> timeSlots, List<_ReservationEntry> reservations) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF5A5056);
    final mutedColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7D7178);
    final userId = _currentUser?.id ?? '';
    final myAppointments = reservations
        .where((a) => a.guestUserId == userId && a.timeSlot.isNotEmpty)
        .toList();

    final bySlot = <String, _ReservationEntry>{};
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
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFEFD7E2)),
          const SizedBox(height: 12),
          if (timeSlots.isEmpty)
            Text('今日未配置时段', style: TextStyle(color: mutedColor))
          else
            for (final slot in timeSlots) ...[
              _buildMySlotLine(slot, bySlot[slot]),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  Future<void> _cancelMyReservation(_ReservationEntry selected) async {
    if (_currentUser == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('确认取消预约'),
          content: Text(
            '将取消 ${selected.maidName.isEmpty ? selected.maidVrcid : selected.maidName}（${selected.timeSlot}）的预约，确定吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确认取消'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final cancelKey = '${selected.maidVrcid}|${selected.timeSlot}';
    setState(() => _cancelingReservationKey = cancelKey);
    try {
      await SupabaseService.client.rpc(
        'cancel_own_reservation',
        params: {
          'p_maid_vrcid': selected.maidVrcid,
          'p_guest_user_id': _currentUser!.id,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消预约')));
      MaidCatalogCacheService.invalidate();
      await _loadData(forceRefresh: true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) {
        setState(() => _cancelingReservationKey = null);
      } else {
        _cancelingReservationKey = null;
      }
    }
  }

  Widget _buildMySlotLine(String slot, _ReservationEntry? appointment) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineBg = isDark ? const Color(0xFF2B2530) : const Color(0xFFFFF3F8);
    final normalText = isDark ? const Color(0xFFEDE5F3) : const Color(0xFF5A5056);
    final mutedText = isDark ? const Color(0xFF9A8FA4) : const Color(0xFF9A8FA4);
    final hasBooking = appointment != null;
    final maidName = hasBooking
        ? (appointment.maidName.isEmpty ? '未命名女仆' : appointment.maidName)
        : '未预约';
    final withFriend = hasBooking && appointment.withFriend;
    final cancelKey = hasBooking ? '${appointment.maidVrcid}|${appointment.timeSlot}' : '';
    final isCanceling = hasBooking && _cancelingReservationKey == cancelKey;

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
                fontSize: 15,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hasBooking ? normalText : mutedText,
                ),
              ),
              if (withFriend) ...[
                const SizedBox(width: 8),
                const Text(
                  '+1',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _pink,
                  ),
                ),
              ],
              if (hasBooking) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: isCanceling ? null : () => _cancelMyReservation(appointment),
                  style: TextButton.styleFrom(
                    foregroundColor: _pink,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: isCanceling
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          '取消',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
    required Map<String, dynamic> maid,
    required List<String> timeSlots,
    required List<_ReservationEntry> appointments,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1F1B24) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF1EAF8) : const Color(0xFF5A5056);
    final mutedColor = isDark ? const Color(0xFFB6AABF) : const Color(0xFF7D7178);
    final slotToAppointments = <String, List<_ReservationEntry>>{};
    for (final slot in timeSlots) {
      slotToAppointments[slot] = <_ReservationEntry>[];
    }
    for (final a in appointments) {
      slotToAppointments.putIfAbsent(a.timeSlot, () => <_ReservationEntry>[]).add(a);
    }

    for (final list in slotToAppointments.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final bookedCount = slotToAppointments.values.where((list) => list.isNotEmpty).length;
    final isFull = timeSlots.isNotEmpty && bookedCount >= timeSlots.length;
    final maidName = (maid['name'] ?? '').toString().trim();

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
                ' ${maidName.isEmpty ? '未命名' : maidName}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
              const Spacer(),
              Text(
                '预约 $bookedCount 人',
                style: const TextStyle(
                  fontSize: 16,
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
                      fontSize: 12,
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

  Widget _buildSlotLine(String slot, List<_ReservationEntry> list) {
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
                fontSize: 15,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: booked ? normalText : mutedText,
                ),
              ),
              if (withFriend) ...[
                const SizedBox(width: 8),
                const Text(
                  '+1',
                  style: TextStyle(
                    fontSize: 14,
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
