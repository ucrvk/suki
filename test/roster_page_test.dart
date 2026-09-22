import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:suki/models/booking_slot.dart';
import 'package:suki/models/roster_entry.dart';
import 'package:suki/pages/roster_page.dart';
import 'package:suki/services/booking_slot_service.dart';
import 'package:suki/services/roster_service.dart';

RosterEntry _entry({String id = 'booking-1', String group = 'DMW'}) =>
    RosterEntry.fromJson({
      'script_name': '夜眠花',
      'session_at': '2026-09-19T13:30:00Z',
      'session_end': null,
      'group_name': group,
      'guests': 2,
      'booking_id': id,
      'companions': const <String>[],
    });

BookingSlot _allDaySlot() => const BookingSlot(
  id: 'slot-all',
  weekdays: {0, 1, 2, 3, 4, 5, 6},
  startSeconds: 0,
  endSeconds: 86400,
  enabled: true,
  sort: 0,
);

/// 只有明天开放的时间槽（用于验证默认选中「下次开放日」）。
BookingSlot _tomorrowSlot() {
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  return BookingSlot(
    id: 'slot-tomorrow',
    weekdays: {BookingSlot.jsWeekdayOf(tomorrow)},
    startSeconds: 0,
    endSeconds: 86400,
    enabled: true,
    sort: 0,
  );
}

class _Slots implements BookingSlotDataSource {
  _Slots({this.rows, this.fail = false});
  final List<BookingSlot>? rows;
  final bool fail;

  @override
  Future<List<BookingSlot>> fetchSlots() async {
    if (fail) throw Exception('slots offline');
    return rows ?? [_allDaySlot()];
  }
}

class _DataSource implements RosterDataSource {
  _DataSource({this.cache, this.fail = false, this.gateRefresh = false});
  final RosterSnapshot? cache;
  final bool fail;
  final bool gateRefresh;
  final Completer<void> refreshGate = Completer<void>();
  final List<String> cachedDays = [];
  final List<String> refreshedDays = [];

  @override
  Future<RosterSnapshot?> loadCached(String day) async {
    cachedDays.add(day);
    return cache;
  }

  @override
  Future<RosterSnapshot> refresh(String day) async {
    refreshedDays.add(day);
    if (gateRefresh) await refreshGate.future;
    if (fail) throw Exception('offline');
    return RosterSnapshot(entries: [_entry()], fetchedAt: DateTime.now());
  }
}

Widget _page({RosterDataSource? dataSource, BookingSlotDataSource? slots}) =>
    MaterialApp(
      home: Scaffold(
        body: RosterPage(
          key: UniqueKey(),
          dataSource: dataSource ?? _DataSource(),
          slotDataSource: slots ?? _Slots(),
        ),
      ),
    );

String _inputText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('roster-day-input')))
    .controller!
    .text;

void main() {
  testWidgets('defaults to today when the window is open', (tester) async {
    final source = _DataSource();
    await tester.pumpWidget(_page(dataSource: source));
    await tester.pumpAndSettle();

    final today = rosterDayKey(DateTime.now());
    expect(_inputText(tester), today);
    expect(source.refreshedDays, [today]);
    expect(find.text('夜眠花'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('roster-day-input')))
          .decoration
          ?.helperText,
      '当前：${formatRosterDayLabel(rosterDayOf(DateTime.now()))}',
    );
  });

  testWidgets('defaults to the next open day when closed', (tester) async {
    final source = _DataSource();
    await tester.pumpWidget(
      _page(
        dataSource: source,
        slots: _Slots(rows: [_tomorrowSlot()]),
      ),
    );
    await tester.pumpAndSettle();

    final tomorrow = rosterDayKey(DateTime.now().add(const Duration(days: 1)));
    expect(_inputText(tester), tomorrow);
    expect(source.refreshedDays, [tomorrow]);

    // 下次开放 chip 指向明天，上次开放 chip 是具体的过去日期（非占位）。
    expect(find.text('下次开放 ${_short(tomorrow)}'), findsOneWidget);
    final prev = tester.widget<ChoiceChip>(
      find.byKey(const Key('roster-prev-chip')),
    );
    expect((prev.label as Text).data, matches(RegExp(r'^上次开放 \d{2}月\d{2}日$')));
  });

  testWidgets('tapping the prev chip loads that day', (tester) async {
    final source = _DataSource();
    await tester.pumpWidget(
      _page(
        dataSource: source,
        slots: _Slots(rows: [_tomorrowSlot()]),
      ),
    );
    await tester.pumpAndSettle();

    final prevLabel =
        tester
                .widget<ChoiceChip>(find.byKey(const Key('roster-prev-chip')))
                .label
            as Text;
    expect(prevLabel.data, startsWith('上次开放 '));

    await tester.tap(find.byKey(const Key('roster-prev-chip')));
    await tester.pumpAndSettle();

    final prevKey = prevLabel.data!.replaceFirst('上次开放 ', '');
    final prevDay = _keyFromLabel(prevKey);
    expect(source.refreshedDays.last, prevDay);
    expect(_inputText(tester), prevDay);
  });

  testWidgets('manual input switches day and validates the format', (
    tester,
  ) async {
    final source = _DataSource();
    await tester.pumpWidget(_page(dataSource: source));
    await tester.pumpAndSettle();
    expect(source.refreshedDays, hasLength(1));

    await tester.enterText(
      find.byKey(const Key('roster-day-input')),
      '2026-09-19',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(source.refreshedDays.last, '2026-09-19');
    expect(_inputText(tester), '2026-09-19');

    await tester.enterText(
      find.byKey(const Key('roster-day-input')),
      'bad-date',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('日期格式应为 YYYY-MM-DD'), findsOneWidget);
    // 非法输入回滚到当前选中日，且不发起新的请求。
    expect(_inputText(tester), '2026-09-19');
    expect(source.refreshedDays.last, '2026-09-19');
  });

  testWidgets('disables quick chips and keeps manual input when slots fail', (
    tester,
  ) async {
    final source = _DataSource();
    await tester.pumpWidget(
      _page(dataSource: source, slots: _Slots(fail: true)),
    );
    await tester.pumpAndSettle();

    final today = rosterDayKey(DateTime.now());
    expect(_inputText(tester), today);
    expect(source.refreshedDays, [today]);

    final prev = tester.widget<ChoiceChip>(
      find.byKey(const Key('roster-prev-chip')),
    );
    final next = tester.widget<ChoiceChip>(
      find.byKey(const Key('roster-next-chip')),
    );
    expect(prev.onSelected, isNull);
    expect(next.onSelected, isNull);

    // 手动输入仍然可用。
    await tester.enterText(
      find.byKey(const Key('roster-day-input')),
      '2026-01-01',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(source.refreshedDays.last, '2026-01-01');
  });

  testWidgets('shows cached entries first and then refreshes', (tester) async {
    final source = _DataSource(
      cache: RosterSnapshot(
        entries: [RosterEntry.fromJson(_cachedRow())],
        fetchedAt: DateTime(2026),
      ),
      gateRefresh: true,
    );
    await tester.pumpWidget(_page(dataSource: source));
    // 刷新被挂起时 header 转圈动画不会停，pumpAndSettle 会超时，手动 pump。
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(source.cachedDays, hasLength(1));
    expect(source.refreshedDays, hasLength(1));
    // 刷新被挂起时先展示缓存内容。
    expect(find.text('雾雨之城'), findsOneWidget);
    expect(find.text('夜眠花'), findsNothing);

    source.refreshGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('夜眠花'), findsOneWidget);
    expect(find.text('雾雨之城'), findsNothing);
  });

  testWidgets('keeps the failure state for a day without cache', (
    tester,
  ) async {
    final source = _DataSource(fail: true);
    await tester.pumpWidget(_page(dataSource: source));
    await tester.pumpAndSettle();

    expect(find.text('排班加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}

Map<String, dynamic> _cachedRow() => {
  'script_name': '雾雨之城',
  'session_at': '2026-09-19T13:30:00Z',
  'session_end': null,
  'group_name': '缓存组',
  'guests': 1,
  'booking_id': 'cached-1',
  'companions': const <String>[],
};

/// `09月19日` → `2026-09-19`（chip 文案不含年份，用当前年份还原）。
String _keyFromLabel(String label) {
  final match = RegExp(r'^(\d{2})月(\d{2})日$').firstMatch(label)!;
  return '${DateTime.now().year}-${match.group(1)}-${match.group(2)}';
}

/// `2026-09-19` → `09月19日`，月份恒为两位（含 10/11/12 月）。
String _short(String key) => '${key.substring(5).replaceFirst('-', '月')}日';
