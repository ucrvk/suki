import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/models/booking_script_entry.dart';
import 'package:suki/pages/booking_page.dart';
import 'package:suki/services/booking_config_service.dart';

class _Scripts implements BookingDataSource {
  @override
  Future<List<BookingScriptEntry>> fetchScripts() async => const [
    BookingScriptEntry(
      id: 's1',
      name: '雾雨之城',
      description: 'd',
      imageUrl: '',
      sort: 1,
      tags: [],
    ),
  ];
}

class _Config implements BookingConfigDataSource {
  _Config(this.enabled, {this.throwError = false});
  final bool enabled;
  final bool throwError;
  @override
  Future<bool> fetchBookingEnabled() async {
    if (throwError) throw Exception('offline');
    return enabled;
  }
}

Widget app(bool enabled, {bool throwError = false}) => MaterialApp(
  home: BookingPage(
    dataSource: _Scripts(),
    configDataSource: _Config(enabled, throwError: throwError),
  ),
);

void main() {
  testWidgets('shows banner when disabled', (tester) async {
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking-disabled-banner')), findsOneWidget);
    expect(find.text('预约未开始，当前无法预约'), findsOneWidget);
    expect(find.text('雾雨之城'), findsOneWidget);
  });

  testWidgets('hides banner when enabled', (tester) async {
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking-disabled-banner')), findsNothing);
    expect(find.text('雾雨之城'), findsOneWidget);
  });

  testWidgets('hides banner on config error (fail-open)', (tester) async {
    await tester.pumpWidget(app(true, throwError: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('booking-disabled-banner')), findsNothing);
    expect(find.text('雾雨之城'), findsOneWidget);
  });
}
