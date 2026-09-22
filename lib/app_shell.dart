import 'package:flutter/material.dart';

import 'pages/booking_page.dart';
import 'pages/me_page.dart';
import 'pages/roster_page.dart';
import 'pages/world_page.dart';
import 'services/account_service.dart';
import 'services/booking_service.dart';
import 'services/booking_session_service.dart';
import 'services/booking_slot_service.dart';
import 'services/spoiler_mode_store.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.bookingDataSource,
    this.bookingSessionDataSource,
    this.bookingSlotDataSource,
    this.bookingService,
    this.rosterDataSource,
    this.rosterSlotDataSource,
    this.worldDataSource,
    this.authService,
    this.profileService,
    this.spoilerModeStore,
  });

  final BookingDataSource? bookingDataSource;
  final BookingSessionDataSource? bookingSessionDataSource;
  final BookingSlotDataSource? bookingSlotDataSource;
  final BookingSubmitService? bookingService;
  final RosterDataSource? rosterDataSource;
  final BookingSlotDataSource? rosterSlotDataSource;
  final WorldDataSource? worldDataSource;
  final AccountAuthService? authService;
  final AccountProfileService? profileService;
  final SpoilerModeStore? spoilerModeStore;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _doubleTapWindow = Duration(milliseconds: 300);
  static const _railBreakpoint = 840.0;

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
    final width = MediaQuery.sizeOf(context).width;
    final body = IndexedStack(
      index: _currentIndex,
      children: [
        BookingPage(
          controller: _bookingController,
          dataSource: widget.bookingDataSource,
          sessionDataSource: widget.bookingSessionDataSource,
          slotDataSource: widget.bookingSlotDataSource,
          submitService: widget.bookingService,
          authService: widget.authService,
        ),
        RosterPage(
          controller: _rosterController,
          dataSource: widget.rosterDataSource,
          slotDataSource: widget.rosterSlotDataSource,
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
    );

    if (width >= _railBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              child: NavigationRail(
                selectedIndex: _currentIndex,
                onDestinationSelected: _selectTab,
                // 文字始终显示在图标下方，保持紧凑侧栏（不展开成宽栏）。
                labelType: NavigationRailLabelType.all,
                minWidth: 92,
                groupAlignment: -0.9,
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    icon: Icon(Icons.calendar_month_outlined, size: 30),
                    selectedIcon: Icon(Icons.calendar_month_rounded, size: 30),
                    label: Text('预约'),
                  ),
                  NavigationRailDestination(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    icon: Icon(Icons.event_note_outlined, size: 30),
                    selectedIcon: Icon(Icons.event_note_rounded, size: 30),
                    label: Text('排班'),
                  ),
                  NavigationRailDestination(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    icon: Icon(Icons.public_outlined, size: 30),
                    selectedIcon: Icon(Icons.public_rounded, size: 30),
                    label: Text('世界'),
                  ),
                  NavigationRailDestination(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    icon: Icon(Icons.person_outline_rounded, size: 30),
                    label: Text('我的'),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
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
