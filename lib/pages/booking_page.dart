import 'dart:async';

import 'package:flutter/material.dart';

import '../models/booking_script_entry.dart';
import '../models/booking_session.dart';
import '../models/booking_slot.dart';
import '../services/account_service.dart';
import '../services/booking_config_service.dart';
import '../services/booking_script_service.dart';
import '../services/booking_service.dart';
import '../services/booking_session_service.dart';
import '../services/booking_slot_service.dart';
import '../theme/app_colors.dart';

abstract interface class BookingDataSource {
  Future<List<BookingScriptEntry>> fetchScripts();
}

class RepositoryBookingDataSource implements BookingDataSource {
  RepositoryBookingDataSource([BookingScriptService? service])
    : _service = service ?? BookingScriptService();

  final BookingScriptService _service;

  @override
  Future<List<BookingScriptEntry>> fetchScripts() => _service.fetchScripts();
}

class BookingPageController {
  VoidCallback? _scrollToTop;
  VoidCallback? _refresh;

  void scrollToTop() => _scrollToTop?.call();
  void refresh() => _refresh?.call();
}

class BookingPage extends StatefulWidget {
  const BookingPage({
    super.key,
    this.controller,
    this.dataSource,
    this.configDataSource,
    this.sessionDataSource,
    this.slotDataSource,
    this.submitService,
    this.authService,
  });

  final BookingPageController? controller;
  final BookingDataSource? dataSource;
  final BookingConfigDataSource? configDataSource;
  final BookingSessionDataSource? sessionDataSource;
  final BookingSlotDataSource? slotDataSource;
  final BookingSubmitService? submitService;
  final AccountAuthService? authService;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final ScrollController _scrollController = ScrollController();
  late final BookingDataSource _dataSource;
  late final BookingConfigDataSource _configDataSource;
  late final BookingSessionDataSource _sessionDataSource;
  late final BookingSlotDataSource _slotDataSource;
  late final BookingSubmitService _submitService;
  List<BookingScriptEntry> _scripts = const [];
  List<BookingSession> _sessions = const [];
  List<BookingSlot> _slots = const [];
  Object? _error;
  Object? _sessionsError;
  Object? _slotsError;
  bool _loading = true;
  bool _refreshing = false;
  bool _bookingEnabled = true;

  AccountAuthService? _authService;
  StreamSubscription<AccountIdentity?>? _authSubscription;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? RepositoryBookingDataSource();
    _configDataSource =
        widget.configDataSource ?? RepositoryBookingConfigDataSource();
    _sessionDataSource =
        widget.sessionDataSource ?? RepositoryBookingSessionDataSource();
    _slotDataSource =
        widget.slotDataSource ?? RepositoryBookingSlotDataSource();
    _submitService = widget.submitService ?? SupabaseBookingService();
    _initAuth();
    widget.controller?._scrollToTop = _scrollToTop;
    widget.controller?._refresh = () => unawaited(_refresh(showFailure: true));
    unawaited(_refresh(showFailure: false));
  }

  /// 测试环境没有初始化 Supabase 时安静降级为「未登录」。
  void _initAuth() {
    _authService = widget.authService ?? _createDefaultAuthService();
    final service = _authService;
    if (service == null) return;
    try {
      _userId = service.currentAccount?.id;
      _authSubscription = service.authChanges.listen((account) {
        if (!mounted) return;
        setState(() => _userId = account?.id);
      }, onError: (_) {});
    } catch (_) {
      _authService = null;
      _userId = null;
    }
  }

  AccountAuthService? _createDefaultAuthService() {
    try {
      return SupabaseAccountAuthService();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    widget.controller?._scrollToTop = null;
    widget.controller?._refresh = null;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh({required bool showFailure}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (_scripts.isEmpty) _loading = true;
      _error = null;
    });

    List<BookingScriptEntry>? scripts;
    Object? scriptsError;
    List<BookingSession>? sessions;
    Object? sessionsError;
    List<BookingSlot>? slots;
    Object? slotsError;
    bool? bookingEnabled;

    await Future.wait<void>([
      () async {
        try {
          scripts = await _dataSource.fetchScripts();
        } catch (error) {
          scriptsError = error;
        }
      }(),
      () async {
        try {
          sessions = await _sessionDataSource.fetchSessions();
        } catch (error) {
          sessionsError = error;
        }
      }(),
      () async {
        try {
          slots = await _slotDataSource.fetchSlots();
        } catch (error) {
          slotsError = error;
        }
      }(),
      () async {
        try {
          bookingEnabled = await _configDataSource.fetchBookingEnabled();
        } catch (_) {
          bookingEnabled = null;
        }
      }(),
    ]);

    if (!mounted) return;
    // 局部变量需在 setState 外取出，闭包内才能正确做空值收敛。
    final enabledResult = bookingEnabled;
    final sessionsResult = sessions;
    final scriptsResult = scripts;
    final slotsResult = slots;
    setState(() {
      if (enabledResult != null) _bookingEnabled = enabledResult;
      if (sessionsResult != null) {
        _sessions = sessionsResult;
        _sessionsError = null;
      } else if (_sessions.isEmpty) {
        _sessionsError = sessionsError;
      }
      if (slotsResult != null) {
        _slots = slotsResult;
        _slotsError = null;
      } else if (_slots.isEmpty) {
        _slotsError = slotsError;
      }
      final loadFailed =
          scriptsError != null || sessionsError != null || slotsError != null;
      if (scriptsResult != null) {
        _scripts = scriptsResult;
        _loading = false;
      } else if (_scripts.isEmpty) {
        _error = scriptsError;
        _loading = false;
      } else if (showFailure && loadFailed) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('刷新失败，已保留当前内容')));
      }
      _refreshing = false;
    });
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  /// 当前时间之后、且还有剩余名额的场次。
  List<BookingSession> _bookableSessions(String scriptId, DateTime now) {
    return _sessions
        .where((s) => s.scriptId == scriptId && s.hasSeatsAt(now))
        .toList(growable: false);
  }

  /// 当前时间之后的场次（用于区分「没场次」和「名额已满」）。
  List<BookingSession> _upcomingSessions(String scriptId, DateTime now) {
    return _sessions
        .where((s) => s.scriptId == scriptId && s.isUpcomingAt(now))
        .toList(growable: false);
  }

  Future<void> _startBooking(
    BookingScriptEntry script,
    List<BookingSession> sessions,
  ) async {
    // 点击瞬间重新校验时间槽，避免停留在页面太久后过期提交（服务端仍会兜底）。
    if (!resolveBookingWindow(_slots, DateTime.now()).isOpen) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前不在预约时间')));
      unawaited(_refresh(showFailure: false));
      return;
    }

    final notice = script.notice;
    if (notice != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => _BookingNoticeDialog(notice: notice),
      );
      if (confirmed != true || !mounted) return;
    }
    if (!mounted) return;

    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BookingSheet(
        title: script.name,
        sessions: sessions,
        submitService: _submitService,
      ),
    );
    if (!mounted || booked != true) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('预约成功')));
    unawaited(_refresh(showFailure: false));
  }

  @override
  Widget build(BuildContext context) {
    final window = resolveBookingWindow(_slots, DateTime.now());
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
                    '预约',
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
          if (_showClosedBanner(window)) _buildBookingDisabledBanner(window),
          Expanded(child: _buildBody(window)),
        ],
      ),
    );
  }

  /// 顶栏「未开放」提示：全局开关关闭，或时间槽未到（拉取失败时不提示，
  /// 因为此时无法判断是否开放）。
  bool _showClosedBanner(BookingWindowState window) {
    if (!_bookingEnabled) return true;
    if (_slotsError != null) return false;
    return !window.isOpen;
  }

  Widget _buildBookingDisabledBanner(BookingWindowState window) {
    final headline = _bookingEnabled ? '当前不在预约时间，暂时无法预约' : '预约未开始，当前无法预约';
    final nextOpen = window.nextOpenAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        key: const Key('booking-disabled-banner'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.pause_circle_outline,
              size: 20,
              color: AppColors.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (nextOpen != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '预计下次开放时间为${formatNextOpenFull(nextOpen)}',
                        key: const Key('banner-next-open'),
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BookingWindowState window) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _scripts.isEmpty) {
      return _MessageState(
        icon: Icons.cloud_off_rounded,
        title: '预约项目加载失败',
        message: _error.toString(),
        actionLabel: '重试',
        onAction: () => _refresh(showFailure: false),
      );
    }
    if (_scripts.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _refresh(showFailure: true),
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            _MessageState(
              icon: Icons.auto_stories_outlined,
              title: '暂无可预约的项目',
              message: '下拉即可重新获取',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(showFailure: true),
      child: ListView.separated(
        key: const Key('booking-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _scripts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 14),
        itemBuilder: (context, index) =>
            _buildScriptCard(_scripts[index], window),
      ),
    );
  }

  Widget _buildScriptCard(
    BookingScriptEntry script,
    BookingWindowState window,
  ) {
    return Container(
      key: ValueKey(script.id),
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
            script.name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (script.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in script.tags)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: AppColors.field,
                    label: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (script.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              script.description,
              style: const TextStyle(
                color: AppColors.textMuted,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          _buildSessionSummary(script, window),
          const SizedBox(height: 14),
          _buildApplyButton(script, window),
        ],
      ),
    );
  }

  /// 卡片内的场次/名额速览 + 下次开放时间。
  Widget _buildSessionSummary(
    BookingScriptEntry script,
    BookingWindowState window,
  ) {
    if (!_bookingEnabled || _userId == null) return const SizedBox.shrink();
    final now = DateTime.now().toUtc();
    final bookable = _bookableSessions(script.id, now);
    final upcoming = _upcomingSessions(script.id, now);
    final showNextOpen = !window.isOpen && window.nextOpenAt != null;
    if (bookable.isEmpty && upcoming.isEmpty && !showNextOpen) {
      return const SizedBox.shrink();
    }

    final nearest = bookable.isNotEmpty ? bookable.first : upcoming.firstOrNull;
    final seatText = bookable.isEmpty
        ? '名额已满'
        : '剩余 ${bookable.first.remaining} 名';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        key: const Key('booking-session-summary'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (nearest != null)
            Row(
              children: [
                const Icon(
                  Icons.event_available_outlined,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  '最近场次 ${nearest.label}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  seatText,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          if (showNextOpen)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                key: const Key('booking-next-open'),
                children: [
                  const Icon(
                    Icons.lock_clock_outlined,
                    size: 18,
                    color: AppColors.accentSoft,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    formatNextOpen(window.nextOpenAt!),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void Function()? _applyAction(
    BookingScriptEntry script,
    BookingWindowState window,
  ) {
    if (!_bookingEnabled) return null;
    if (_userId == null) return null;
    // 拿不到时间槽时宁可不让约，避免放行过期预约（fail-closed）。
    if (_slotsError != null && _slots.isEmpty) return null;
    if (!window.isOpen) return null;
    if (_sessionsError != null && _sessions.isEmpty) return null;
    final now = DateTime.now().toUtc();
    final bookable = _bookableSessions(script.id, now);
    if (bookable.isEmpty) return null;
    return () => unawaited(_startBooking(script, bookable));
  }

  String _applyLabel(BookingScriptEntry script, BookingWindowState window) {
    if (!_bookingEnabled) return '预约未开放';
    if (_userId == null) return '登录后可预约';
    if (_slotsError != null && _slots.isEmpty) return '预约时间加载失败';
    if (!window.isOpen) return '当前不在预约时间';
    if (_sessionsError != null && _sessions.isEmpty) return '场次加载失败';
    final now = DateTime.now().toUtc();
    if (_bookableSessions(script.id, now).isNotEmpty) return '预约';
    if (_upcomingSessions(script.id, now).isNotEmpty) return '名额已满';
    return '暂无可预约场次';
  }

  Widget _buildApplyButton(
    BookingScriptEntry script,
    BookingWindowState window,
  ) {
    final action = _applyAction(script, window);
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const Key('booking-apply-button'),
        onPressed: action,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          disabledBackgroundColor: AppColors.fieldDisabled,
          foregroundColor: AppColors.accentInk,
          disabledForegroundColor: AppColors.textDisabled,
        ),
        child: Text(_applyLabel(script, window)),
      ),
    );
  }
}

/// 预约前的告知弹窗：确认按钮 5 秒倒计时后才可点击。
class _BookingNoticeDialog extends StatefulWidget {
  const _BookingNoticeDialog({required this.notice});

  final BookingNotice notice;

  @override
  State<_BookingNoticeDialog> createState() => _BookingNoticeDialogState();
}

class _BookingNoticeDialogState extends State<_BookingNoticeDialog> {
  static const _waitSeconds = 5;

  int _remaining = _waitSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        _remaining = 0;
        timer.cancel();
      } else {
        _remaining -= 1;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = widget.notice;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (notice.title.isNotEmpty) ...[
                Text(
                  notice.title,
                  key: const Key('booking-notice-title'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (notice.intro.isNotEmpty) ...[
                Text(
                  notice.intro,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (notice.items.isNotEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < notice.items.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${i + 1}. ',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    notice.items[i],
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (notice.footer.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  notice.footer,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      '离开',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('booking-notice-confirm'),
                    onPressed: _remaining > 0
                        ? null
                        : () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      disabledBackgroundColor: AppColors.fieldDisabled,
                      foregroundColor: AppColors.accentInk,
                      disabledForegroundColor: AppColors.textDisabled,
                    ),
                    child: Text(
                      _remaining > 0 ? '请等待 $_remaining 秒' : '我已知晓，继续预约',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 预约弹层：先选场次，再选人数与同行者 ID。
class _BookingSheet extends StatefulWidget {
  const _BookingSheet({
    required this.title,
    required this.sessions,
    required this.submitService,
  });

  final String title;
  final List<BookingSession> sessions;
  final BookingSubmitService submitService;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  BookingSession? _selected;
  int _guests = 1;
  final List<TextEditingController> _controllers = [];
  bool _submitting = false;
  String? _submitError;

  int get _maxGuests => _selected?.remaining ?? 1;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _selectSession(BookingSession session) {
    setState(() {
      _selected = session;
      _guests = 1;
      _submitError = null;
      _syncControllers();
    });
  }

  void _changeGuests(int delta) {
    final session = _selected;
    if (session == null) return;
    final upper = session.remaining < 1 ? 1 : session.remaining;
    setState(() {
      final next = _guests + delta;
      _guests = next < 1 ? 1 : (next > upper ? upper : next);
      _syncControllers();
    });
  }

  /// 同行者输入框数量 = 人数 - 1。
  void _syncControllers() {
    final target = _guests - 1;
    while (_controllers.length > target) {
      _controllers.removeLast().dispose();
    }
    while (_controllers.length < target) {
      _controllers.add(TextEditingController());
    }
  }

  bool get _companionsValid =>
      _controllers.every((c) => c.text.trim().isNotEmpty);

  Future<void> _submit() async {
    final session = _selected;
    if (session == null || !_companionsValid || _submitting) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.submitService.book(
        sessionId: session.id,
        guests: _guests,
        companions: _controllers
            .map((c) => c.text.trim())
            .toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = bookingErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: _selected == null ? _buildSessionStep() : _buildGuestStep(),
      ),
    );
  }

  Widget _buildHeader(Widget title, {Widget? leading}) {
    return Row(
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 8)],
        Expanded(child: title),
      ],
    );
  }

  Widget _buildSessionStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          Text(
            '选择场次 · ${widget.title}',
            key: const Key('booking-sheet-title'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '仅显示未来且有剩余名额的场次',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        for (final session in widget.sessions)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              key: ValueKey('session-${session.id}'),
              onTap: () => _selectSession(session),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _selected == session
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: AppColors.accent,
              ),
              title: Text(
                session.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '剩余 ${session.remaining} 名',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          '点击场次进入人数选择',
          style: TextStyle(color: AppColors.textDisabled, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textMuted,
              side: const BorderSide(color: AppColors.outline),
            ),
            child: const Text('取消'),
          ),
        ),
      ],
    );
  }

  Widget _buildGuestStep() {
    final session = _selected!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(
          Text(
            '预约人数 · ${widget.title}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          leading: IconButton(
            key: const Key('booking-sheet-back'),
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _selected = null;
                    _guests = 1;
                    _submitError = null;
                    _syncControllers();
                  }),
            icon: const Icon(Icons.arrow_back, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '场次 ${session.label} · 剩余 ${session.remaining} 名',
          key: const Key('booking-sheet-session'),
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Text('人数', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 12),
            IconButton(
              key: const Key('booking-guest-minus'),
              onPressed: _submitting || _guests <= 1
                  ? null
                  : () => _changeGuests(-1),
              icon: const Icon(Icons.remove_circle_outline),
              color: AppColors.accent,
            ),
            Text(
              '$_guests 人',
              key: const Key('booking-guest-count'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            IconButton(
              key: const Key('booking-guest-plus'),
              onPressed: _submitting || _guests >= _maxGuests
                  ? null
                  : () => _changeGuests(1),
              icon: const Icon(Icons.add_circle_outline),
              color: AppColors.accent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '最多 $_maxGuests 人',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        if (_controllers.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            '每超过一人需填写一位同行者的 ID',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _controllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: Key('booking-companion-field-$i'),
                controller: _controllers[i],
                enabled: !_submitting,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '同行者 ${i + 1} ID',
                  hintText: '填写对方的用户 ID',
                  filled: true,
                  fillColor: AppColors.field,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  labelStyle: const TextStyle(color: AppColors.textMuted),
                  hintStyle: const TextStyle(color: AppColors.textDisabled),
                ),
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
        ],
        if (_submitError != null) ...[
          Text(
            _submitError!,
            key: const Key('booking-sheet-error'),
            style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('booking-sheet-submit'),
            onPressed: !_submitting && _companionsValid ? _submit : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              disabledBackgroundColor: AppColors.fieldDisabled,
              foregroundColor: AppColors.accentInk,
              disabledForegroundColor: AppColors.textDisabled,
            ),
            child: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : const Text('确认预约'),
          ),
        ),
      ],
    );
  }
}

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
