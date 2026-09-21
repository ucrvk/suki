import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/models/world_content_entry.dart';
import 'package:suki/pages/world_page.dart';
import 'package:suki/services/account_service.dart';
import 'package:suki/services/ending_unlock_service.dart';
import 'package:suki/services/spoiler_mode_store.dart';
import 'package:suki/services/world_content_service.dart';

void main() {
  testWidgets('switches branches and keeps ending body hidden until tapped', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(WorldPage(dataSource: _WorldFixture())));
    await tester.pumpAndSettle();

    expect(find.text('纸樱'), findsOneWidget);
    expect(find.byKey(const Key('world-image-fallback')), findsWidgets);

    await tester.tap(find.text('世界观'));
    await tester.pumpAndSettle();
    expect(find.text('夜眠花'), findsOneWidget);

    await tester.tap(find.text('结局'));
    await tester.pumpAndSettle();
    expect(find.text('黎明之誓'), findsOneWidget);
    expect(find.text('真相'), findsOneWidget);
    expect(find.text('結婚'), findsOneWidget);
    expect(find.text('结局正文不应预先显示'), findsNothing);

    await tester.tap(find.text('黎明之誓'));
    await tester.pumpAndSettle();
    expect(find.text('结局正文不应预先显示'), findsOneWidget);
    expect(find.byKey(const Key('world-detail-body')), findsOneWidget);
  });

  testWidgets('shows independent failure and retry state', (tester) async {
    await tester.pumpWidget(_testApp(WorldPage(dataSource: _FailingWorld())));
    await tester.pumpAndSettle();

    expect(find.text('内容加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('结局'));
    await tester.pumpAndSettle();
    expect(find.text('结局加载失败'), findsOneWidget);
  });

  testWidgets('hides endings that the account has not unlocked', (tester) async {
    final spoiler = _FakeSpoilerModeStore(false);
    await tester.pumpWidget(
      _testApp(
        WorldPage(
          dataSource: _EndingsFixture(),
          spoilerModeStore: spoiler,
          unlockRepository: _FakeUnlockRepository({'ending-1'}),
          authService: _FakeWorldAuthService('user-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('结局'));
    await tester.pumpAndSettle();

    expect(find.text('黎明之誓'), findsOneWidget);
    expect(find.text('永恒安眠'), findsNothing);
  });

  testWidgets('shows every ending once spoiler mode is enabled', (tester) async {
    final spoiler = _FakeSpoilerModeStore(false);
    await tester.pumpWidget(
      _testApp(
        WorldPage(
          dataSource: _EndingsFixture(),
          spoilerModeStore: spoiler,
          unlockRepository: _FakeUnlockRepository({'ending-1'}),
          authService: _FakeWorldAuthService('user-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('结局'));
    await tester.pumpAndSettle();
    expect(find.text('永恒安眠'), findsNothing);

    await spoiler.setEnabled(true);
    await tester.pumpAndSettle();

    expect(find.text('黎明之誓'), findsOneWidget);
    expect(find.text('永恒安眠'), findsOneWidget);
  });

  testWidgets('asks for a sign in while spoiler mode is off', (tester) async {
    await tester.pumpWidget(
      _testApp(
        WorldPage(
          dataSource: _EndingsFixture(),
          spoilerModeStore: _FakeSpoilerModeStore(false),
          unlockRepository: _FakeUnlockRepository({'ending-1'}),
          authService: _FakeWorldAuthService(null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('结局'));
    await tester.pumpAndSettle();

    expect(find.text('登录后查看已解锁结局'), findsOneWidget);
    expect(find.text('黎明之誓'), findsNothing);
  });
}

Widget _testApp(Widget child) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: Scaffold(body: child),
);

WorldContentEntry _codex(WorldContentKind kind, String title) {
  return WorldContentEntry(
    id: '${kind.name}-$title',
    kind: kind,
    title: title,
    subtitle: '副标题',
    imageUrl: '',
    imageUrl2: '',
    tags: const ['标签'],
    body: '详细内容',
    sort: 1,
    createdAt: DateTime(2026),
    script: '',
  );
}

WorldContentEntry _ending() => WorldContentEntry(
  id: 'ending-1',
  kind: WorldContentKind.ending,
  title: '黎明之誓',
  subtitle: '结局副标题',
  imageUrl: '',
  imageUrl2: '',
  tags: const ['真相', '結婚'],
  body: '结局正文不应预先显示',
  sort: 1,
  createdAt: DateTime(2026),
  script: '夜眠花',
);

class _WorldFixture implements WorldDataSource {
  final codex = WorldContentSnapshot(
    entries: [
      _codex(WorldContentKind.witch, '纸樱'),
      _codex(WorldContentKind.lore, '夜眠花'),
    ],
    fetchedAt: DateTime(2026),
  );
  final endings = WorldContentSnapshot(
    entries: [_ending()],
    fetchedAt: DateTime(2026),
  );

  @override
  Future<WorldContentSnapshot?> loadCachedCodex() async => null;

  @override
  Future<WorldContentSnapshot?> loadCachedEndings() async => null;

  @override
  Future<WorldContentSnapshot> refreshCodex() async => codex;

  @override
  Future<WorldContentSnapshot> refreshEndings() async => endings;
}

WorldContentEntry _endingEntry({
  required String id,
  required String title,
  List<String> tags = const [],
}) => WorldContentEntry(
  id: id,
  kind: WorldContentKind.ending,
  title: title,
  subtitle: '',
  imageUrl: '',
  imageUrl2: '',
  tags: tags,
  body: '$title 正文',
  sort: 1,
  createdAt: DateTime(2026),
  script: '夜眠花',
);

class _EndingsFixture implements WorldDataSource {
  @override
  Future<WorldContentSnapshot?> loadCachedCodex() async => null;

  @override
  Future<WorldContentSnapshot?> loadCachedEndings() async => null;

  @override
  Future<WorldContentSnapshot> refreshCodex() async => WorldContentSnapshot(
    entries: const [],
    fetchedAt: DateTime(2026),
  );

  @override
  Future<WorldContentSnapshot> refreshEndings() async => WorldContentSnapshot(
    entries: [
      _endingEntry(id: 'ending-1', title: '黎明之誓'),
      _endingEntry(id: 'ending-2', title: '永恒安眠'),
    ],
    fetchedAt: DateTime(2026),
  );
}

class _FakeUnlockRepository implements EndingUnlockRepository {
  _FakeUnlockRepository(this.unlocked);

  final Set<String> unlocked;

  @override
  Future<Set<String>> loadCached(String userId) async => unlocked;

  @override
  Future<Set<String>> refresh(String userId) async => unlocked;
}

class _FakeSpoilerModeStore extends ChangeNotifier
    implements SpoilerModeStore {
  _FakeSpoilerModeStore(this._enabled);

  bool _enabled;

  @override
  bool get value => _enabled;

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    notifyListeners();
  }
}

class _FakeWorldAuthService implements AccountAuthService {
  _FakeWorldAuthService(this.userId);

  final String? userId;

  @override
  Stream<AccountIdentity?> get authChanges => const Stream.empty();

  @override
  AccountIdentity? get currentAccount => userId == null
      ? null
      : AccountIdentity(
          id: userId!,
          email: 'witch@example.com',
          usernameMetadata: '',
          expiresAt: null,
        );

  @override
  Future<AccountIdentity?> refreshSession() async => currentAccount;

  @override
  Future<AccountIdentity?> signIn({
    required String email,
    required String password,
  }) async => currentAccount;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> updatePassword(String password) async {}
}

class _FailingWorld implements WorldDataSource {
  @override
  Future<WorldContentSnapshot?> loadCachedCodex() async => null;

  @override
  Future<WorldContentSnapshot?> loadCachedEndings() async => null;

  @override
  Future<WorldContentSnapshot> refreshCodex() =>
      Future.error(Exception('codex offline'));

  @override
  Future<WorldContentSnapshot> refreshEndings() =>
      Future.error(Exception('endings offline'));
}
