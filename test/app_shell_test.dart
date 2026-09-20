import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/app_shell.dart';
import 'package:suki/models/booking_script_entry.dart';
import 'package:suki/models/roster_entry.dart';
import 'package:suki/pages/booking_page.dart';
import 'package:suki/pages/roster_page.dart';
import 'package:suki/pages/world_page.dart';
import 'package:suki/services/account_service.dart';
import 'package:suki/services/roster_service.dart';
import 'package:suki/services/world_content_service.dart';
import 'package:suki/theme/app_colors.dart';

void main() {
  testWidgets('shows booking list, grouped roster and switches tabs', (
    tester,
  ) async {
    final source = _FakeDataSource(_sampleSnapshot());
    await tester.pumpWidget(
      _testApp(
        AppShell(
          bookingDataSource: _FakeBookingDataSource(),
          rosterDataSource: source,
          worldDataSource: _EmptyWorldDataSource(),
          authService: _ShellAuthService(),
          profileService: _ShellProfileService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('雾雨之城'), findsOneWidget);
    expect(find.byKey(const Key('booking-apply-button')), findsOneWidget);

    await tester.tap(find.text('排班').last);
    await tester.pumpAndSettle();
    expect(find.text('夜眠花'), findsOneWidget);
    expect(find.text('无忧无虑的狼'), findsOneWidget);
    expect(find.text('天子tenko'), findsOneWidget);
    expect(find.text('DMW'), findsOneWidget);
    expect(find.text('肆安_Sensei'), findsOneWidget);

    await tester.tap(find.text('世界').last);
    await tester.pumpAndSettle();
    expect(find.text('魔女图鉴'), findsOneWidget);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-login-button')), findsOneWidget);
  });

  testWidgets('shows retry state when there is no cache and refresh fails', (
    tester,
  ) async {
    final source = _FailingDataSource();
    await tester.pumpWidget(_testApp(RosterPage(dataSource: source)));
    await tester.pumpAndSettle();

    expect(find.text('排班加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('shows empty state for an empty response', (tester) async {
    final source = _FakeDataSource(
      RosterSnapshot(entries: const [], fetchedAt: DateTime(2026)),
    );
    await tester.pumpWidget(_testApp(RosterPage(dataSource: source)));
    await tester.pumpAndSettle();

    expect(find.text('暂无排班'), findsOneWidget);
  });
}

Widget _testApp(Widget child) => MaterialApp(
  theme: ThemeData.dark(
    useMaterial3: true,
  ).copyWith(scaffoldBackgroundColor: AppColors.background),
  home: child,
);

RosterSnapshot _sampleSnapshot() {
  RosterEntry entry(
    String group,
    int guests,
    String id,
    List<String> companions,
  ) {
    return RosterEntry(
      scriptName: '夜眠花',
      sessionAt: DateTime.parse('2026-09-19T13:30:00Z'),
      sessionEnd: null,
      groupName: group,
      guests: guests,
      bookingId: id,
      companions: companions,
    );
  }

  return RosterSnapshot(
    entries: [
      entry('无忧无虑的狼', 1, '1', const []),
      entry('天子tenko', 1, '2', const []),
      entry('DMW', 2, '3', const ['肆安_Sensei']),
    ],
    fetchedAt: DateTime(2026),
  );
}

class _FakeDataSource implements RosterDataSource {
  _FakeDataSource(this.snapshot);
  final RosterSnapshot snapshot;

  @override
  Future<RosterSnapshot?> loadCached() async => null;

  @override
  Future<RosterSnapshot> refresh() async => snapshot;
}

class _FakeBookingDataSource implements BookingDataSource {
  @override
  Future<List<BookingScriptEntry>> fetchScripts() async => const [
    BookingScriptEntry(
      id: 'script-1',
      name: '雾雨之城',
      description: '示例剧本简介',
      imageUrl: '',
      sort: 1,
      tags: ['剧情'],
    ),
  ];
}

class _FailingDataSource implements RosterDataSource {
  @override
  Future<RosterSnapshot?> loadCached() async => null;

  @override
  Future<RosterSnapshot> refresh() => Future.error(Exception('offline'));
}

class _EmptyWorldDataSource implements WorldDataSource {
  final snapshot = WorldContentSnapshot(
    entries: const [],
    fetchedAt: DateTime(2026),
  );

  @override
  Future<WorldContentSnapshot?> loadCachedCodex() async => null;

  @override
  Future<WorldContentSnapshot?> loadCachedEndings() async => null;

  @override
  Future<WorldContentSnapshot> refreshCodex() async => snapshot;

  @override
  Future<WorldContentSnapshot> refreshEndings() async => snapshot;
}

class _ShellAuthService implements AccountAuthService {
  @override
  Stream<AccountIdentity?> get authChanges => const Stream.empty();

  @override
  AccountIdentity? get currentAccount => null;

  @override
  Future<AccountIdentity?> refreshSession() async => null;

  @override
  Future<AccountIdentity?> signIn({
    required String email,
    required String password,
  }) async => null;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String password) async {}
}

class _ShellProfileService implements AccountProfileService {
  @override
  Future<AccountProfile> load(String userId) async =>
      const AccountProfile.empty();

  @override
  Future<void> save(String userId, AccountProfile profile) async {}
}
