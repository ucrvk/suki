import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/widgets/random_maid_dialog.dart';

Map<String, dynamic> _maid(String name) => {
  'name': name,
  'image': '',
  'signature': '$name 的签名',
  'tags': const <String>[],
};

Map<String, dynamic>? _result;

Future<void> _openDialog(
  WidgetTester tester, {
  required List<Map<String, dynamic>> maids,
  bool canBook = false,
  Random? random,
}) async {
  // 足够大的画布，保证弹窗底部按钮在可视区域内。
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  _result = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-dialog'),
              onPressed: () async {
                _result = await showRandomMaidDialog(
                  context,
                  maids,
                  canBook: canBook,
                  random: random,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-dialog')));
  await tester.pumpAndSettle();
}

String _shownMaidName(WidgetTester tester, List<String> names) {
  for (final name in names) {
    if (find.text(name).evaluate().isNotEmpty) return name;
  }
  fail('对话框中没有出现任何预期的女仆名字');
}

void main() {
  const names = ['Alice', 'Bob'];
  final maids = names.map(_maid).toList();

  testWidgets('browse mode only shows the reroll button', (tester) async {
    await _openDialog(tester, maids: maids, random: Random(1));

    expect(find.byKey(const Key('random-maid-reroll-button')), findsOneWidget);
    expect(find.byKey(const Key('random-maid-book-button')), findsNothing);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(_result, isNull);
  });

  testWidgets('booking mode puts 就是TA了 above 再来一个', (tester) async {
    await _openDialog(tester, maids: maids, canBook: true, random: Random(1));

    final book = find.byKey(const Key('random-maid-book-button'));
    final reroll = find.byKey(const Key('random-maid-reroll-button'));
    expect(book, findsOneWidget);
    expect(reroll, findsOneWidget);
    expect(tester.getTopLeft(book).dy, lessThan(tester.getTopLeft(reroll).dy));

    final shown = _shownMaidName(tester, names);
    await tester.tap(book);
    await tester.pumpAndSettle();

    expect(_result, isNotNull);
    expect(_result!['name'], shown);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('reroll picks another maid locally', (tester) async {
    await _openDialog(tester, maids: maids, random: Random(7));

    final first = _shownMaidName(tester, names);
    await tester.tap(find.byKey(const Key('random-maid-reroll-button')));
    await tester.pumpAndSettle();

    final second = _shownMaidName(tester, names);
    expect(second, isNot(first));
  });

  testWidgets('single maid hides the reroll button', (tester) async {
    await _openDialog(tester, maids: [_maid('Alice')], canBook: true);

    expect(find.byKey(const Key('random-maid-book-button')), findsOneWidget);
    expect(find.byKey(const Key('random-maid-reroll-button')), findsNothing);
  });

  testWidgets('empty maids shows a hint and returns null', (tester) async {
    await _openDialog(tester, maids: const []);

    expect(find.text('没有可展示的女仆'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(_result, isNull);
  });
}
