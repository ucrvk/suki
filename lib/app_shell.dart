import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pages/booking_page.dart';
import 'pages/feedback_page.dart';
import 'pages/me_page.dart';
import 'pages/queue_page.dart';
import 'pages/schedule_page.dart';
import 'services/queue_tab_settings.dart';
import 'services/supabase_service.dart';
import 'utils/app_tabs.dart';
import 'widgets/responsive_shell.dart';

enum TabReselectAction { scrollToTop, refresh }

class TabReselectEvent {
  const TabReselectEvent({
    required this.index,
    required this.action,
    required this.timestamp,
  });

  /// 逻辑 Tab ID（见 [AppTabs]），不是导航下标。
  final int index;
  final TabReselectAction action;
  final DateTime timestamp;
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 左栏里「像导航项、但不是页面」的快捷入口：点击直接打开浏览器。
class _RailAction {
  const _RailAction({
    required this.icon,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String url;
}

const List<_RailAction> _railActions = [
  _RailAction(
    icon: Icons.restart_alt_rounded,
    label: '猫生重开',
    url: 'https://vrcsuki.chat/catlife',
  ),
  _RailAction(
    icon: Icons.emoji_events_outlined,
    label: '猫王争霸',
    url: 'https://vrcsuki.chat/catking',
  ),
];

const Map<int, _NavItem> _navItems = {
  AppTabs.queue: _NavItem(
    icon: Icons.format_list_numbered_rounded,
    label: '排队',
  ),
  AppTabs.booking: _NavItem(icon: Icons.calendar_month, label: '预约'),
  AppTabs.schedule: _NavItem(icon: Icons.event_note_outlined, label: '排班'),
  AppTabs.intro: _NavItem(icon: Icons.menu_book_outlined, label: '介绍'),
  AppTabs.reviews: _NavItem(icon: Icons.reviews_outlined, label: '评价'),
  AppTabs.guestbook: _NavItem(icon: Icons.forum_outlined, label: '留言'),
  AppTabs.photoWall: _NavItem(icon: Icons.photo_library_outlined, label: '照片墙'),
  AppTabs.me: _NavItem(icon: Icons.person, label: '我'),
};

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.forceAllBookableForTest = false});

  final bool forceAllBookableForTest;

  static final ValueNotifier<int> tabIndexNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<TabReselectEvent?> tabReselectNotifier =
      ValueNotifier<TabReselectEvent?>(null);

  static void switchToTab(int index) {
    tabIndexNotifier.value = index;
  }

  static bool queueTabEnabled() => QueueTabSettings.enabledNotifier.value;

  static int queueTabIndex() => AppTabs.queue;

  static int bookingTabIndex() => AppTabs.booking;

  static int scheduleTabIndex() => AppTabs.schedule;

  static int introTabIndex() => AppTabs.intro;

  /// 「介绍组」的组内 ID，窄屏把四个页面折叠成一项时使用。
  static int feedbackTabIndex() => AppTabs.intro;

  static int reviewsTabIndex() => AppTabs.reviews;

  static int guestbookTabIndex() => AppTabs.guestbook;

  static int photoWallTabIndex() => AppTabs.photoWall;

  static int meTabIndex() => AppTabs.me;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);

  int _currentTabId = AppTabs.booking;
  int _feedbackSegment = 0;
  bool _queueTabEnabled = QueueTabSettings.enabledNotifier.value;
  bool _loggingOut = false;
  int? _lastTappedTabId;
  DateTime? _lastTappedAt;
  late final VoidCallback _tabListener;
  late final VoidCallback _queueTabListener;

  @override
  void initState() {
    super.initState();
    _tabListener = () {
      if (!mounted) return;
      final tabId = AppShell.tabIndexNotifier.value;
      if (tabId == _currentTabId) return;
      setState(() => _currentTabId = tabId);
    };
    AppShell.tabIndexNotifier.addListener(_tabListener);

    _queueTabListener = () {
      final nextEnabled = QueueTabSettings.enabledNotifier.value;
      if (!mounted || nextEnabled == _queueTabEnabled) return;
      setState(() {
        _queueTabEnabled = nextEnabled;
        // 排队 tab 被关闭时，如果正停留在排队页就回到预约。
        if (!nextEnabled && _currentTabId == AppTabs.queue) {
          _currentTabId = AppTabs.booking;
          AppShell.tabIndexNotifier.value = _currentTabId;
        }
        _lastTappedTabId = null;
        _lastTappedAt = null;
      });
    };
    QueueTabSettings.enabledNotifier.addListener(_queueTabListener);
    unawaited(QueueTabSettings.load());

    _currentTabId = AppShell.bookingTabIndex();
    AppShell.tabIndexNotifier.value = _currentTabId;
  }

  @override
  void dispose() {
    AppShell.tabIndexNotifier.removeListener(_tabListener);
    QueueTabSettings.enabledNotifier.removeListener(_queueTabListener);
    super.dispose();
  }

  List<Widget> _buildPages() {
    return [
      if (_queueTabEnabled)
        const KeyedSubtree(key: ValueKey('queue-page'), child: QueuePage()),
      KeyedSubtree(
        key: const ValueKey('booking-page'),
        child: BookingPage(
          forceAllBookableForTest: widget.forceAllBookableForTest,
        ),
      ),
      const KeyedSubtree(key: ValueKey('schedule-page'), child: SchedulePage()),
      KeyedSubtree(
        key: const ValueKey('feedback-page'),
        child: FeedbackPage(
          segment: _feedbackSegment,
          onSegmentChanged: (segment) {
            if (segment == _feedbackSegment) return;
            setState(() => _feedbackSegment = segment);
          },
        ),
      ),
      const KeyedSubtree(key: ValueKey('me-page'), child: MePage()),
    ];
  }

  int _currentDestinationId({required bool wide}) {
    if (AppTabs.isFeedbackGroup(_currentTabId)) {
      return wide ? AppTabs.intro + _feedbackSegment : AppTabs.intro;
    }
    return _currentTabId;
  }

  void _handleDestinationSelected(int position, {required bool wide}) {
    final ids = AppTabs.destinationOrder(
      queueEnabled: _queueTabEnabled,
      wide: wide,
    );
    if (position < 0) return;

    // 宽屏排在真实 Tab 后面的两个快捷入口：直接打开浏览器，不切换页面。
    if (position >= ids.length) {
      final actionIndex = position - ids.length;
      if (actionIndex < _railActions.length) {
        unawaited(_openExternal(Uri.parse(_railActions[actionIndex].url)));
      }
      return;
    }

    final tabId = ids[position];
    if (tabId == _currentDestinationId(wide: wide)) {
      _emitReselect(tabId);
      return;
    }

    setState(() {
      if (AppTabs.isFeedbackGroup(tabId)) {
        _feedbackSegment = tabId - AppTabs.intro;
        _currentTabId = wide ? tabId : AppTabs.intro;
      } else {
        _currentTabId = tabId;
      }
      _lastTappedTabId = tabId;
      _lastTappedAt = DateTime.now();
    });
    AppShell.tabIndexNotifier.value = _currentTabId;
  }

  void _emitReselect(int tabId) {
    final now = DateTime.now();
    final isDoubleTap =
        _lastTappedTabId == tabId &&
        _lastTappedAt != null &&
        now.difference(_lastTappedAt!) <= _doubleTapWindow;
    AppShell.tabReselectNotifier.value = TabReselectEvent(
      index: tabId,
      action: isDoubleTap
          ? TabReselectAction.refresh
          : TabReselectAction.scrollToTop,
      timestamp: now,
    );
    _lastTappedTabId = tabId;
    _lastTappedAt = now;
  }

  Future<void> _logoutFromRail() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await SupabaseService.client.auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('退出登录失败：$error')));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 左栏链接打不开时静默失败，不影响导航。
    }
  }

  Widget _buildRailTrailing() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValueListenableBuilder<bool>(
        valueListenable: MePage.loggedIn,
        builder: (context, loggedIn, _) {
          if (!loggedIn) return const SizedBox.shrink();
          return IconButton(
            key: const Key('rail-logout-button'),
            onPressed: _loggingOut ? null : _logoutFromRail,
            tooltip: '退出登录',
            icon: _loggingOut
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = ResponsiveShell.isWide(context);
    final ids = AppTabs.destinationOrder(
      queueEnabled: _queueTabEnabled,
      wide: wide,
    );

    return ResponsiveShell(
      body: IndexedStack(
        index: AppTabs.bodyIndex(
          tabId: _currentTabId,
          queueEnabled: _queueTabEnabled,
        ),
        children: _buildPages(),
      ),
      selectedIndex: AppTabs.destinationIndex(
        tabId: _currentTabId,
        feedbackSegment: _feedbackSegment,
        queueEnabled: _queueTabEnabled,
        wide: wide,
      ),
      onDestinationSelected: (position) =>
          _handleDestinationSelected(position, wide: wide),
      destinations: [
        for (final id in ids)
          ShellDestination(
            icon: _navItems[id]!.icon,
            label: _navItems[id]!.label,
          ),
        // 宽屏时把两个宣传入口排在「我」下面，外观与普通导航项一致，
        // 但点击只打开浏览器，不切换页面。
        if (wide)
          for (final action in _railActions)
            ShellDestination(icon: action.icon, label: action.label),
      ],
      railTrailing: wide ? _buildRailTrailing() : null,
    );
  }
}
