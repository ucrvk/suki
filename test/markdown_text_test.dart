import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:suki/theme/app_colors.dart';
import 'package:suki/widgets/markdown_text.dart';

List<TextSpan> _segments(String text) =>
    boldTextSpan(text).children!.whereType<TextSpan>().toList();

void main() {
  group('boldTextSpan', () {
    test('splits plain and bold segments', () {
      final segments = _segments('状态**安稳**入睡');
      expect(segments.map((span) => span.text), ['状态', '安稳', '入睡']);
      expect(segments[0].style, isNull);
      expect(segments[1].style?.fontWeight, FontWeight.w700);
      // 加粗段同时带上强调色，仅靠字重不够醒目。
      expect(segments[1].style?.color, AppColors.accent);
      expect(segments[2].style, isNull);
      // 解析后标记被吃掉。
      expect(boldTextSpan('状态**安稳**入睡').toPlainText(), '状态安稳入睡');
    });

    test('handles multiple bold segments', () {
      final segments = _segments('**a**-**b**');
      expect(segments.map((span) => span.text), ['a', '-', 'b']);
      expect(segments[0].style?.fontWeight, FontWeight.w700);
      expect(segments[1].style, isNull);
      expect(segments[2].style?.fontWeight, FontWeight.w700);
    });

    test('keeps an unmatched marker literal', () {
      final segments = _segments('**未闭合');
      expect(segments.map((span) => span.text), ['**未闭合']);
      expect(segments.single.style, isNull);
    });

    test('does not treat single asterisks as bold', () {
      final segments = _segments('*not bold*');
      expect(segments.map((span) => span.text), ['*not bold*']);
      expect(segments.single.style, isNull);
    });

    test('matches a bold span across a newline', () {
      final segments = _segments('**跨\n行**');
      expect(segments.single.text, '跨\n行');
      expect(segments.single.style?.fontWeight, FontWeight.w700);
    });

    test('honours a custom bold style', () {
      final segments = boldTextSpan(
        '**强调**',
        boldStyle: const TextStyle(fontSize: 20),
      ).children!.whereType<TextSpan>().toList();
      expect(segments.single.style?.fontSize, 20);
      expect(segments.single.style?.fontWeight, isNull);
    });

    test('plain text stays a single plain segment', () {
      final segments = _segments('普通文本');
      expect(segments.map((span) => span.text), ['普通文本']);
      expect(segments.single.style, isNull);
      expect(boldTextSpan('普通文本').toPlainText(), '普通文本');
    });
  });

  group('MarkdownText', () {
    testWidgets('renders plain text exactly like Text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MarkdownText('普通文本'))),
      );

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(MarkdownText),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, '普通文本');
      expect(text.textSpan, isNull);
    });

    testWidgets('renders marked text as rich segments without **', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MarkdownText('早 **安** 好'))),
      );

      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(MarkdownText),
          matching: find.byType(Text),
        ),
      );
      expect(text.data, isNull);
      expect(text.textSpan!.toPlainText(), '早 安 好');
      final bold = (text.textSpan! as TextSpan).children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.text == '安');
      expect(bold.style?.fontWeight, FontWeight.w700);
      expect(bold.style?.color, AppColors.accent);
    });
  });
}
