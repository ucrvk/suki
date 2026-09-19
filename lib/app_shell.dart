import 'package:flutter/material.dart';

import 'pages/me_page.dart';
import 'pages/placeholder_page.dart';
import 'pages/roster_page.dart';
import 'pages/world_page.dart';
import 'services/account_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.rosterDataSource,
    this.worldDataSource,
    this.authService,
    this.profileService,
  });

  final RosterDataSource? rosterDataSource;
  final WorldDataSource? worldDataSource;
  final AccountAuthService? authService;
  final AccountProfileService? profileService;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _doubleTapWindow = Duration(milliseconds: 300);

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

    if (index != 0 && index != 2) return;
    final now = DateTime.now();
    final lastReselectAt = _lastReselectAt[index];
    final shouldRefresh =
        lastReselectAt != null &&
        now.difference(lastReselectAt) <= _doubleTapWindow;
    if (shouldRefresh) {
      if (index == 0) {
        _rosterController.refresh();
      } else {
        _worldController.refresh();
      }
      _lastReselectAt.remove(index);
    } else {
      if (index == 0) {
        _rosterController.scrollToTop();
      } else {
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
          RosterPage(
            controller: _rosterController,
            dataSource: widget.rosterDataSource,
          ),
          const PlaceholderPage(
            title: '预约',
            icon: Icons.calendar_month_outlined,
          ),
          WorldPage(
            controller: _worldController,
            dataSource: widget.worldDataSource,
          ),
          MePage(
            authService: widget.authService,
            profileService: widget.profileService,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: '排班',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: '预约',
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
