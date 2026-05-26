import 'package:flutter/material.dart';

import 'pages/booking_page.dart';
import 'pages/me_page.dart';
import 'pages/reviews_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.forceAllBookableForTest = false,
  });

  final bool forceAllBookableForTest;

  static final ValueNotifier<int> tabIndexNotifier = ValueNotifier<int>(0);

  static void switchToTab(int index) {
    tabIndexNotifier.value = index;
  }

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  late final VoidCallback _tabListener;

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
          const ReviewsPage(),
          const MePage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
          AppShell.tabIndexNotifier.value = index;
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '预约'),
          NavigationDestination(icon: Icon(Icons.reviews_outlined), label: '评价'),
          NavigationDestination(icon: Icon(Icons.person), label: '我'),
        ],
      ),
    );
  }
}
