import 'dart:async';

import 'package:flutter/material.dart';

import 'pages/booking_page.dart';
import 'pages/feedback_page.dart';
import 'pages/me_page.dart';
import 'pages/queue_page.dart';
import 'pages/schedule_page.dart';
import 'services/queue_tab_settings.dart';

enum TabReselectAction { scrollToTop, refresh }

class TabReselectEvent {
  const TabReselectEvent({
    required this.index,
    required this.action,
    required this.timestamp,
  });

  final int index;
  final TabReselectAction action;
  final DateTime timestamp;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.forceAllBookableForTest = false});

  final bool forceAllBookableForTest;

  static final ValueNotifier<int> tabIndexNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<TabReselectEvent?> tabReselectNotifier = ValueNotifier<TabReselectEvent?>(null);

  static void switchToTab(int index) {
    tabIndexNotifier.value = index;
  }

  static bool queueTabEnabled() => QueueTabSettings.enabledNotifier.value;

  static int queueTabIndex() => 0;

  static int bookingTabIndex() => queueTabEnabled() ? 1 : 0;

  static int scheduleTabIndex() => queueTabEnabled() ? 2 : 1;

  static int feedbackTabIndex() => queueTabEnabled() ? 3 : 2;

  static int meTabIndex() => queueTabEnabled() ? 4 : 3;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final VoidCallback _tabListener;
  late final VoidCallback _queueTabListener;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);
  int? _lastTappedIndex;
  DateTime? _lastTappedAt;
  bool _queueTabEnabled = QueueTabSettings.enabledNotifier.value;

  int _normalizeIndex({
    required int index,
    required bool fromQueueEnabled,
    required bool toQueueEnabled,
  }) {
    if (fromQueueEnabled == toQueueEnabled) return index;

    if (toQueueEnabled) {
      switch (index) {
        case 0:
          return 1;
        case 1:
          return 2;
        case 2:
          return 3;
        case 3:
          return 4;
        default:
          return 0;
      }
    }

    switch (index) {
      case 0:
        return 0;
      case 1:
        return 0;
      case 2:
        return 1;
      case 3:
        return 2;
      case 4:
        return 3;
      default:
        return 0;
    }
  }

  List<NavigationDestination> _buildDestinations() {
    final destinations = <NavigationDestination>[
      if (_queueTabEnabled)
        const NavigationDestination(
          icon: Icon(Icons.format_list_numbered_rounded),
          label: '排队',
        ),
      const NavigationDestination(icon: Icon(Icons.calendar_month), label: '预约'),
    ];
    destinations.addAll(const [
      NavigationDestination(icon: Icon(Icons.event_note_outlined), label: '排班'),
      NavigationDestination(icon: Icon(Icons.reviews_outlined), label: '介绍'),
      NavigationDestination(icon: Icon(Icons.person), label: '我'),
    ]);
    return destinations;
  }

  List<Widget> _buildPages() {
    final pages = <Widget>[
      if (_queueTabEnabled)
        const KeyedSubtree(
          key: ValueKey('queue-page'),
          child: QueuePage(),
        ),
      KeyedSubtree(
        key: const ValueKey('booking-page'),
        child: BookingPage(forceAllBookableForTest: widget.forceAllBookableForTest),
      ),
    ];
    pages.addAll(const [
      KeyedSubtree(
        key: ValueKey('schedule-page'),
        child: SchedulePage(),
      ),
      KeyedSubtree(
        key: ValueKey('feedback-page'),
        child: FeedbackPage(),
      ),
      KeyedSubtree(
        key: ValueKey('me-page'),
        child: MePage(),
      ),
    ]);
    return pages;
  }

  @override
  void initState() {
    super.initState();
    _tabListener = () {
      if (!mounted) return;
      setState(() {
        _currentIndex = AppShell.tabIndexNotifier.value;
      });
    };
    AppShell.tabIndexNotifier.addListener(_tabListener);
    _queueTabListener = () {
      if (!mounted) return;
      final nextEnabled = QueueTabSettings.enabledNotifier.value;
      if (nextEnabled == _queueTabEnabled) return;
      setState(() {
        final nextIndex = _normalizeIndex(
          index: _currentIndex,
          fromQueueEnabled: _queueTabEnabled,
          toQueueEnabled: nextEnabled,
        );
        _queueTabEnabled = nextEnabled;
        _currentIndex = nextIndex;
        AppShell.tabIndexNotifier.value = nextIndex;
        _lastTappedIndex = nextIndex;
        _lastTappedAt = null;
      });
    };
    QueueTabSettings.enabledNotifier.addListener(_queueTabListener);
    unawaited(QueueTabSettings.load());
    _currentIndex = AppShell.bookingTabIndex();
    AppShell.tabIndexNotifier.value = _currentIndex;
  }

  @override
  void dispose() {
    AppShell.tabIndexNotifier.removeListener(_tabListener);
    QueueTabSettings.enabledNotifier.removeListener(_queueTabListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _buildPages(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          if (index == _currentIndex) {
            final now = DateTime.now();
            final isDoubleTap = _lastTappedIndex == index &&
                _lastTappedAt != null &&
                now.difference(_lastTappedAt!) <= _doubleTapWindow;
            AppShell.tabReselectNotifier.value = TabReselectEvent(
              index: index,
              action: isDoubleTap ? TabReselectAction.refresh : TabReselectAction.scrollToTop,
              timestamp: now,
            );
            _lastTappedIndex = index;
            _lastTappedAt = now;
            return;
          }
          setState(() {
            _currentIndex = index;
          });
          AppShell.tabIndexNotifier.value = index;
          _lastTappedIndex = index;
          _lastTappedAt = DateTime.now();
        },
        destinations: _buildDestinations(),
      ),
    );
  }
}
