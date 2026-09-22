import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:suki/models/booking_script_entry.dart';
import 'package:suki/models/booking_session.dart';
import 'package:suki/models/booking_slot.dart';
import 'package:suki/pages/booking_page.dart';
import 'package:suki/services/account_service.dart';
import 'package:suki/services/booking_config_service.dart';
import 'package:suki/services/booking_service.dart';
import 'package:suki/services/booking_session_service.dart';
import 'package:suki/services/booking_slot_service.dart';

const _notice = BookingNotice(
  title: '预约前，请听魔女一句',
  intro: '请确认自己状态安稳。',
  items: ['今晚状态安稳', '身体状况良好'],
  footer: '照顾好自己才是第一位。',
);

BookingScriptEntry _script({BookingNotice? notice, String id = 's1'}) =>
    BookingScriptEntry(
      id: id,
      name: '夜眠花',
      description: '简介',
      imageUrl: '',
      sort: 1,
      tags: const ['剧情'],
      notice: notice,
    );

BookingSession _session({
  String id = 'sess-1',
  String scriptId = 's1',
  DateTime? startsAt,
  int capacity = 10,
  int booked = 0,
}) => BookingSession(
  id: id,
  scriptId: scriptId,
  startsAt: startsAt ?? DateTime.now().toUtc().add(const Duration(days: 1)),
  capacity: capacity,
  booked: booked,
);

class _Scripts implements BookingDataSource {
  _Scripts(this.entries);
  final List<BookingScriptEntry> entries;

  @override
  Future<List<BookingScriptEntry>> fetchScripts() async => entries;
}

class _Config implements BookingConfigDataSource {
  _Config([this.enabled = true]);
  final bool enabled;

  @override
  Future<bool> fetchBookingEnabled() async => enabled;
}

class _Sessions implements BookingSessionDataSource {
  _Sessions(this.rows);
  final List<BookingSession> rows;
  int calls = 0;

  @override
  Future<List<BookingSession>> fetchSessions() async {
    calls += 1;
    return rows;
  }
}

/// 全周 00:00–24:00 常开的时间槽。
BookingSlot _openSlot() => const BookingSlot(
  id: 'slot-all',
  weekdays: {0, 1, 2, 3, 4, 5, 6},
  startSeconds: 0,
  endSeconds: 86400,
  enabled: true,
  sort: 0,
);

/// 两小时后才开始的时间槽，用于验证窗口未开放。
BookingSlot _laterSlot() {
  final start = DateTime.now().add(const Duration(hours: 2));
  final end = start.add(const Duration(hours: 1));
  var endSeconds = end.day == start.day
      ? end.hour * 3600 + end.minute * 60
      : 86400;
  final startSeconds = start.hour * 3600 + start.minute * 60;
  if (endSeconds <= startSeconds) endSeconds = 86400;
  return BookingSlot(
    id: 'slot-later',
    weekdays: {BookingSlot.jsWeekdayOf(start)},
    startSeconds: startSeconds,
    endSeconds: endSeconds,
    enabled: true,
    sort: 0,
  );
}

class _Slots implements BookingSlotDataSource {
  _Slots({List<BookingSlot>? rows, this.fail = false})
    : rows = rows ?? [_openSlot()];

  final List<BookingSlot> rows;
  final bool fail;

  @override
  Future<List<BookingSlot>> fetchSlots() async {
    if (fail) throw Exception('slots offline');
    return rows;
  }
}

class _Submit implements BookingSubmitService {
  _Submit({this.error});
  final Object? error;
  final List<(String, int, List<String>)> calls = [];

  @override
  Future<void> book({
    required String sessionId,
    required int guests,
    required List<String> companions,
  }) async {
    calls.add((sessionId, guests, companions));
    if (error != null) throw error!;
  }
}

class _Auth implements AccountAuthService {
  _Auth({this.account});
  final AccountIdentity? account;

  @override
  AccountIdentity? get currentAccount => account;

  @override
  Stream<AccountIdentity?> get authChanges => const Stream.empty();

  @override
  Future<AccountIdentity?> refreshSession() async => account;

  @override
  Future<AccountIdentity?> signIn({
    required String email,
    required String password,
  }) async => account;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String password) async {}
}

AccountIdentity _identity(String id) => AccountIdentity(
  id: id,
  email: 'a@b.c',
  usernameMetadata: 'tester',
  expiresAt: null,
);

/// 页面标题也是「预约」，按钮文案统一从按钮自身读取。
String _applyLabel(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.byKey(const Key('booking-apply-button')),
  );
  return (button.child as Text).data ?? '';
}

Widget _page({
  required List<BookingScriptEntry> scripts,
  List<BookingSession> sessions = const [],
  List<BookingSlot>? slots,
  bool slotsFail = false,
  bool enabled = true,
  BookingSubmitService? submit,
  AccountIdentity? account,
}) => MaterialApp(
  home: Scaffold(
    body: BookingPage(
      // 每次 pump 都是新实例，避免测试里复用旧 State 的缓存数据。
      key: UniqueKey(),
      dataSource: _Scripts(scripts),
      configDataSource: _Config(enabled),
      sessionDataSource: _Sessions(sessions),
      slotDataSource: _Slots(rows: slots, fail: slotsFail),
      submitService: submit ?? _Submit(),
      authService: _Auth(account: account),
    ),
  ),
);

void main() {
  testWidgets('disables apply button when logged out', (tester) async {
    await tester.pumpWidget(_page(scripts: [_script(notice: _notice)]));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('booking-apply-button')),
    );
    expect(button.onPressed, isNull);
    expect(_applyLabel(tester), '登录后可预约');
    // 未登录时看不到场次速览。
    expect(find.byKey(const Key('booking-session-summary')), findsNothing);
  });

  testWidgets('shows notice with 5s countdown before booking', (tester) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script(notice: _notice)],
        sessions: [_session()],
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(_applyLabel(tester), '预约');
    await tester.tap(find.byKey(const Key('booking-apply-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking-notice-title')), findsOneWidget);
    expect(find.text('预约前，请听魔女一句'), findsOneWidget);
    expect(find.text('请确认自己状态安稳。'), findsOneWidget);
    expect(find.text('1. '), findsOneWidget);
    expect(find.text('今晚状态安稳'), findsOneWidget);
    expect(find.text('身体状况良好'), findsOneWidget);
    expect(find.text('照顾好自己才是第一位。'), findsOneWidget);

    final waiting = tester.widget<FilledButton>(
      find.byKey(const Key('booking-notice-confirm')),
    );
    expect(waiting.onPressed, isNull);
    expect(find.text('请等待 5 秒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('请等待 1 秒'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    final ready = tester.widget<FilledButton>(
      find.byKey(const Key('booking-notice-confirm')),
    );
    expect(ready.onPressed, isNotNull);
    expect(find.text('我已知晓，继续预约'), findsOneWidget);

    await tester.tap(find.byKey(const Key('booking-notice-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking-sheet-title')), findsOneWidget);
    expect(find.byKey(const Key('session-sess-1')), findsOneWidget);
    expect(find.text('剩余 10 名'), findsAtLeastNWidgets(1));
  });

  testWidgets('skips notice when script has none', (tester) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session()],
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('booking-apply-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking-notice-title')), findsNothing);
    expect(find.byKey(const Key('booking-sheet-title')), findsOneWidget);
  });

  testWidgets('distinguishes sold out, no session and disabled config', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session(capacity: 5, booked: 5)],
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_applyLabel(tester), '名额已满');

    await tester.pumpWidget(
      _page(scripts: [_script()], account: _identity('u1')),
    );
    await tester.pumpAndSettle();
    expect(_applyLabel(tester), '暂无可预约场次');

    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session()],
        account: _identity('u1'),
        enabled: false,
      ),
    );
    await tester.pumpAndSettle();
    expect(_applyLabel(tester), '预约未开放');
    expect(find.byKey(const Key('booking-disabled-banner')), findsOneWidget);
    expect(find.text('预约未开始，当前无法预约'), findsOneWidget);
    // 时间槽处于开放中，无法预测开关何时手动打开，不编造时间。
    expect(find.byKey(const Key('banner-next-open')), findsNothing);
  });

  testWidgets('ignores past sessions', (tester) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [
          _session(
            startsAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          ),
        ],
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_applyLabel(tester), '暂无可预约场次');
  });

  testWidgets('guest count caps at remaining seats', (tester) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session(capacity: 5, booked: 2)],
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-apply-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-sess-1')));
    await tester.pumpAndSettle();

    expect(find.text('1 人'), findsOneWidget);
    expect(find.text('最多 3 人'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('booking-companion-field-0')), findsNothing);

    await tester.tap(find.byKey(const Key('booking-guest-plus')));
    await tester.pump();
    expect(find.text('2 人'), findsOneWidget);
    expect(find.byKey(const Key('booking-companion-field-0')), findsOneWidget);
    expect(find.byKey(const Key('booking-companion-field-1')), findsNothing);

    await tester.tap(find.byKey(const Key('booking-guest-plus')));
    await tester.pump();
    expect(find.text('3 人'), findsOneWidget);
    expect(find.byKey(const Key('booking-companion-field-1')), findsOneWidget);

    final plus = tester.widget<IconButton>(
      find.byKey(const Key('booking-guest-plus')),
    );
    expect(plus.onPressed, isNull);

    await tester.tap(find.byKey(const Key('booking-guest-minus')));
    await tester.pump();
    expect(find.text('2 人'), findsOneWidget);
    expect(find.byKey(const Key('booking-companion-field-1')), findsNothing);
  });

  testWidgets('submit stays disabled until every companion id is filled', (
    tester,
  ) async {
    final submit = _Submit();
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session()],
        account: _identity('u1'),
        submit: submit,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-apply-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-sess-1')));
    await tester.pumpAndSettle();

    // 单人无需同行者，可直接提交。
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('booking-sheet-submit')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('booking-guest-plus')));
    await tester.pump();
    final disabled = tester.widget<FilledButton>(
      find.byKey(const Key('booking-sheet-submit')),
    );
    expect(disabled.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('booking-companion-field-0')),
      '  guest-a  ',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('booking-sheet-submit')))
          .onPressed,
      isNotNull,
    );

    await tester.enterText(
      find.byKey(const Key('booking-companion-field-0')),
      '   ',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('booking-sheet-submit')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('submits guests = companions + 1 and refreshes', (tester) async {
    final submit = _Submit();
    final sessions = _Sessions([_session(capacity: 10, booked: 1)]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookingPage(
            dataSource: _Scripts([_script()]),
            configDataSource: _Config(),
            sessionDataSource: sessions,
            slotDataSource: _Slots(),
            submitService: submit,
            authService: _Auth(account: _identity('u1')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(sessions.calls, 1);

    await tester.tap(find.byKey(const Key('booking-apply-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-sess-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('booking-guest-plus')));
    await tester.tap(find.byKey(const Key('booking-guest-plus')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('booking-companion-field-0')),
      'friend-1',
    );
    await tester.enterText(
      find.byKey(const Key('booking-companion-field-1')),
      'friend-2',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('booking-sheet-submit')));
    await tester.pumpAndSettle();

    expect(submit.calls, hasLength(1));
    final (sessionId, guests, companions) = submit.calls.single;
    expect(sessionId, 'sess-1');
    expect(guests, 3);
    expect(companions, ['friend-1', 'friend-2']);

    expect(find.text('预约成功'), findsOneWidget);
    expect(sessions.calls, 2);
  });

  testWidgets('keeps sheet open and shows server error', (tester) async {
    final submit = _Submit(
      error: const PostgrestException(message: '该场次已被约满', code: 'P0001'),
    );
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session()],
        account: _identity('u1'),
        submit: submit,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-apply-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-sess-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('booking-sheet-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('booking-sheet-error')), findsOneWidget);
    expect(find.text('该场次已被约满'), findsOneWidget);
    expect(find.byKey(const Key('booking-sheet-submit')), findsOneWidget);
    expect(find.text('预约成功'), findsNothing);
  });

  testWidgets('disables booking outside the slot window and shows next open', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session()],
        slots: [_laterSlot()],
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('booking-apply-button')),
    );
    expect(button.onPressed, isNull);
    expect(_applyLabel(tester), '当前不在预约时间');

    // 顶栏给出未开放提示 + 预计下次开放时间。
    expect(find.byKey(const Key('booking-disabled-banner')), findsOneWidget);
    expect(find.text('当前不在预约时间，暂时无法预约'), findsOneWidget);
    final bannerNext = find.byKey(const Key('banner-next-open'));
    expect(bannerNext, findsOneWidget);
    expect(tester.widget<Text>(bannerNext).data, startsWith('预计下次开放时间为'));
    expect(tester.widget<Text>(bannerNext).data, contains('星期'));

    // 场次速览照常显示，同时给出下次开放时间。
    expect(find.byKey(const Key('booking-session-summary')), findsOneWidget);
    final nextOpen = find.byKey(const Key('booking-next-open'));
    expect(nextOpen, findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(of: nextOpen, matching: find.byType(Text)),
          )
          .data,
      startsWith('下次开放 周'),
    );
  });

  testWidgets('fails closed when slots cannot be loaded', (tester) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script()],
        sessions: [_session()],
        slotsFail: true,
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('booking-apply-button')),
    );
    expect(button.onPressed, isNull);
    expect(_applyLabel(tester), '预约时间加载失败');
    expect(find.byKey(const Key('booking-next-open')), findsNothing);
    // 时间槽拿不到时无法判断开放状态，不显示顶栏提示。
    expect(find.byKey(const Key('booking-disabled-banner')), findsNothing);
  });

  testWidgets('window check runs again when the apply button is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(
        scripts: [_script(notice: _notice)],
        sessions: [_session()],
        slots: [_openSlot()],
        account: _identity('u1'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('booking-apply-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking-notice-title')), findsOneWidget);
  });
}
