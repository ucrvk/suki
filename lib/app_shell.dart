import 'package:flutter/material.dart';

import 'pages/booking_page.dart';
import 'pages/me_page.dart';
import 'pages/roster_page.dart';
import 'pages/world_page.dart';
import 'services/account_service.dart';
import 'services/spoiler_mode_store.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.bookingDataSource,
    this.rosterDataSource,
    this.worldDataSource,
    this.authService,
    this.profileService,
    this.spoilerModeStore,
  });

  final BookingDataSource? bookingDataSource;
  final RosterDataSource? rosterDataSource;
  final WorldDataSource? worldDataSource;
  final AccountAuthService? authService;
  final AccountProfileService? profileService;
  final SpoilerModeStore? spoilerModeStore;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _doubleTapWindow = Duration(milliseconds: 300);

  final BookingPageController _bookingController = BookingPageController();
  final RosterPageController _rosterController = RosterPageController();
  final WorldPageController _worldController = WorldPageController();
  int _currentIndex = 0;
  final Map<int, DateTime> _lastReselectAt = {};

  void _selectTab(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      _lastReselectAt.clear();
      return;
    }

    if (index == 3) return;
    final now = DateTime.now();
    final lastReselectAt = _lastReselectAt[index];
    final shouldRefresh =
        lastReselectAt != null &&
        now.difference(lastReselectAt) <= _doubleTapWindow;
    if (shouldRefresh) {
      switch (index) {
        case 0:
          _bookingController.refresh();
        case 1:
          _rosterController.refresh();
        case 2:
          _worldController.refresh();
      }
      _lastReselectAt.remove(index);
    } else {
      switch (index) {
        case 0:
          _bookingController.scrollToTop();
        case 1:
          _rosterController.scrollToTop();
        case 2:
          _worldController.scrollToTop();
      }
      _lastReselectAt[index] = now;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          BookingPage(
            controller: _bookingController,
            dataSource: widget.bookingDataSource,
          ),
          RosterPage(
            controller: _rosterController,
            dataSource: widget.rosterDataSource,
          ),
          WorldPage(
            controller: _worldController,
            dataSource: widget.worldDataSource,
            spoilerModeStore: widget.spoilerModeStore,
            authService: widget.authService,
          ),
          MePage(
            authService: widget.authService,
            profileService: widget.profileService,
            spoilerModeStore: widget.spoilerModeStore,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: '预约',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: '排班',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public_rounded),
            label: '世界',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
