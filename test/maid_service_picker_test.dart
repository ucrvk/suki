import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/utils/maid_services.dart';
import 'package:suki/widgets/maid_service_picker.dart';

class _Host extends StatefulWidget {
  const _Host({required this.options, this.initial = const <String>{}});

  final MaidServiceOptions options;
  final Set<String> initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Set<String> selected = Set<String>.of(widget.initial);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MaidServicePicker(
            options: widget.options,
            selected: selected,
            onChanged: (next) {
              setState(() => selected = next);
            },
          ),
        ),
      ),
    );
  }
}

MaidServiceOptions _options({required int maxPick}) {
  return MaidServiceOptions(
    enabled: true,
    options: const ['UNO', '象棋', '台球'],
    maxPick: maxPick,
  );
}

void main() {
  testWidgets('renders the title, hint, count and every option', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(options: _options(maxPick: 2)));

    expect(find.text('玩什么'), findsOneWidget);
    expect(find.text('可多选，最多 2 项'), findsOneWidget);
    expect(find.text('已选 0/2'), findsOneWidget);
    for (final option in ['UNO', '象棋', '台球']) {
      expect(find.byKey(Key('maid-service-$option')), findsOneWidget);
    }
  });

  testWidgets('selected options only change color without a checkmark', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(options: _options(maxPick: 2)));
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('maid-service-UNO')))
          .showCheckmark,
      isFalse,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_Host(options: _options(maxPick: 1)));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('maid-service-UNO')))
          .showCheckmark,
      isFalse,
    );
  });

  testWidgets('disables unselected chips once the limit is reached', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(options: _options(maxPick: 2)));

    await tester.tap(find.byKey(const Key('maid-service-UNO')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('maid-service-象棋')));
    await tester.pump();

    expect(find.text('已选 2/2'), findsOneWidget);
    final selectedFinder = find.byKey(const Key('maid-service-UNO'));
    final selectedChip = tester.widget<FilterChip>(selectedFinder);
    final scheme = Theme.of(tester.element(selectedFinder)).colorScheme;
    expect(selectedChip.selectedColor, scheme.primary);
    expect(selectedChip.labelStyle?.color, scheme.onPrimary);
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('maid-service-台球')))
          .onSelected,
      isNull,
    );

    // 取消一项后，第三项重新可选。
    await tester.tap(find.byKey(const Key('maid-service-UNO')));
    await tester.pump();

    expect(find.text('已选 1/2'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.byKey(const Key('maid-service-台球')))
          .onSelected,
      isNotNull,
    );
  });

  testWidgets('single choice mode replaces the previous selection', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(options: _options(maxPick: 1)));

    expect(find.text('单选'), findsOneWidget);

    await tester.tap(find.byKey(const Key('maid-service-UNO')));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('maid-service-UNO')))
          .selected,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('maid-service-象棋')));
    await tester.pump();

    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('maid-service-UNO')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('maid-service-象棋')))
          .selected,
      isTrue,
    );
  });

  testWidgets('tapping the selected chip clears it', (tester) async {
    await tester.pumpWidget(
      _Host(options: _options(maxPick: 2), initial: const {'UNO'}),
    );

    await tester.tap(find.byKey(const Key('maid-service-UNO')));
    await tester.pump();

    expect(find.text('已选 0/2'), findsOneWidget);
  });

  testWidgets('unlimited mode does not disable any chip', (tester) async {
    await tester.pumpWidget(_Host(options: _options(maxPick: 3)));

    expect(find.text('可多选'), findsOneWidget);

    for (final option in ['UNO', '象棋', '台球']) {
      await tester.tap(find.byKey(Key('maid-service-$option')));
      await tester.pump();
    }

    expect(find.text('已选 3'), findsOneWidget);
  });
}
