import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/widgets/announcement_card.dart';

const _longText = '''
第一行公告
第二行公告
第三行公告
第四行公告
第五行公告
第六行公告
第七行公告
第八行公告
第九行公告
第十行公告
第十一行公告
第十二行公告''';

Widget _wrap(String text) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 320, child: AnnouncementCard(text: text)),
      ),
    ),
  );
}

Text _textWidget(WidgetTester tester, String text) {
  return tester.widget<Text>(find.text(text));
}

void main() {
  testWidgets('short announcement has no expand arrow', (tester) async {
    await tester.pumpWidget(_wrap('这是一条短公告'));

    expect(find.text('这是一条短公告'), findsOneWidget);
    expect(find.byTooltip('展开公告'), findsNothing);
    expect(_textWidget(tester, '这是一条短公告').maxLines, 10);
  });

  testWidgets('announcement over 10 lines is collapsed with a down arrow', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_longText));

    expect(find.byTooltip('展开公告'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.text('展开'), findsNothing);

    final text = _textWidget(tester, _longText.trim());
    expect(text.maxLines, 10);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('tapping the arrow expands and collapses the announcement', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_longText));

    await tester.tap(find.byTooltip('展开公告'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('收起公告'), findsOneWidget);
    expect(find.text('收起'), findsNothing);
    expect(_textWidget(tester, _longText.trim()).maxLines, isNull);
    expect(
      _textWidget(tester, _longText.trim()).overflow,
      TextOverflow.visible,
    );

    await tester.tap(find.byTooltip('收起公告'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('展开公告'), findsOneWidget);
    expect(_textWidget(tester, _longText.trim()).maxLines, 10);
  });

  testWidgets('empty announcement shows a placeholder without an arrow', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(''));

    expect(find.text('暂无公告'), findsOneWidget);
    expect(find.byTooltip('展开公告'), findsNothing);
  });

  testWidgets('changing the announcement resets the expanded state', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_longText));
    await tester.tap(find.byTooltip('展开公告'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起公告'), findsOneWidget);

    await tester.pumpWidget(_wrap('$_longText\n第十三行公告'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('展开公告'), findsOneWidget);
    expect(_textWidget(tester, '$_longText\n第十三行公告'.trim()).maxLines, 10);
  });
}
