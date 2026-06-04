import 'package:flutter/material.dart';

import 'pages/booking_page.dart';
import 'pages/feedback_page.dart';
import 'pages/me_page.dart';
import 'pages/schedule_page.dart';

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

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final VoidCallback _tabListener;
  static const Duration _doubleTapWindow = Duration(milliseconds: 300);
  int? _lastTappedIndex;
  DateTime? _lastTappedAt;

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
  }

  @override
  void dispose() {
    AppShell.tabIndexNotifier.removeListener(_tabListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          BookingPage(forceAllBookableForTest: widget.forceAllBookableForTest),
          const SchedulePage(),
          const FeedbackPage(),
          const MePage(),
        ],
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
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '预约'),
          NavigationDestination(icon: Icon(Icons.event_note_outlined), label: '排班'),
          NavigationDestination(icon: Icon(Icons.reviews_outlined), label: '评价'),
          NavigationDestination(icon: Icon(Icons.person), label: '我'),
        ],
      ),
    );
  }
}
