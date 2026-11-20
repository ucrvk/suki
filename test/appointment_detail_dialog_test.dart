import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suki/utils/reservation_details.dart';
import 'package:suki/widgets/appointment_detail_dialog.dart';

ReservationDetails _details({
  bool withFriend = false,
  String friendName = '',
  List<String> services = const [],
}) {
  return ReservationDetails(
    guest: '幕后鸭手',
    guestUserId: 'user-1',
    maidName: 'ma_su',
    maidVrcid: 'maid_1',
    timeSlot: '22:30-23:30',
    withFriend: withFriend,
    createdAt: 1,
    services: services,
    friendName: friendName,
  );
}

Future<void> _pump(WidgetTester tester, ReservationDetails details) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: AppointmentDetailDialog(details: details)),
    ),
  );
}

void main() {
  testWidgets('shows guest, maid, friend and services', (tester) async {
    await _pump(
      tester,
      _details(
        withFriend: true,
        friendName: '小奇kin',
        services: const ['一起看电影', '星空望远镜'],
      ),
    );

    expect(find.text('预约详情 · 22:30-23:30'), findsOneWidget);
    expect(find.text('预约人'), findsOneWidget);
    expect(find.text('幕后鸭手'), findsOneWidget);
    expect(find.text('预约目标'), findsOneWidget);
    expect(find.text('ma_su'), findsOneWidget);
    expect(find.text('携带好友'), findsOneWidget);
    expect(find.text('小奇kin'), findsOneWidget);
    expect(find.text('玩什么'), findsOneWidget);
    expect(find.text('一起看电影'), findsOneWidget);
    expect(find.text('星空望远镜'), findsOneWidget);
  });

  testWidgets('hides friend and services when not provided', (tester) async {
    await _pump(tester, _details());

    expect(find.text('预约人'), findsOneWidget);
    expect(find.text('预约目标'), findsOneWidget);
    expect(find.text('携带好友'), findsNothing);
    expect(find.text('玩什么'), findsNothing);
  });

  testWidgets('shows a placeholder when the friend name is empty', (
    tester,
  ) async {
    await _pump(tester, _details(withFriend: true));

    expect(find.text('携带好友'), findsOneWidget);
    expect(find.text('已带好友'), findsOneWidget);
  });

  testWidgets('shows only services when the guest comes without a friend', (
    tester,
  ) async {
    await _pump(tester, _details(services: const ['UNO']));

    expect(find.text('携带好友'), findsNothing);
    expect(find.text('玩什么'), findsOneWidget);
    expect(find.text('UNO'), findsOneWidget);
  });
}
