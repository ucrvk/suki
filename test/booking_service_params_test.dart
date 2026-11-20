import 'package:flutter_test/flutter_test.dart';
import 'package:suki/services/booking_service.dart';

void main() {
  group('BookingService.buildAddReservationParams', () {
    test('includes the selected services', () {
      final params = BookingService.buildAddReservationParams(
        maidVrcid: 'maid_1794157654445',
        maidName: 'Fufu',
        guestUsername: 'wenwen12305',
        guestUserId: '052554e2-b3c9-40d9-a947-9c1da6f2a63d',
        timeSlot: '21:30-22:30',
        time: '2026/11/20 16:54:08',
        createdAt: 1795164848767,
        withFriend: false,
        friendVrcid: '   ',
        services: const ['UNO', '象棋', '一起看电影'],
      );

      expect(params['p_services'], ['UNO', '象棋', '一起看电影']);
      expect(params['p_friend_vrcid'], '');
      expect(params['p_with_friend'], isFalse);
      expect(params['p_maid_vrcid'], 'maid_1794157654445');
    });

    test('sends an empty list when nothing is selected', () {
      final params = BookingService.buildAddReservationParams(
        maidVrcid: 'maid_1',
        maidName: 'Fufu',
        guestUsername: 'wenwen',
        guestUserId: 'user',
        timeSlot: '21:30-22:30',
        time: '2026/11/20 16:54:08',
        createdAt: 1,
        withFriend: true,
        friendVrcid: ' vrchatter ',
        services: const [],
      );

      expect(params['p_services'], isEmpty);
      expect(params['p_friend_vrcid'], 'vrchatter');
      expect(params['p_with_friend'], isTrue);
    });

    test('trims and drops blank service entries', () {
      final params = BookingService.buildAddReservationParams(
        maidVrcid: 'maid_1',
        maidName: 'Fufu',
        guestUsername: 'wenwen',
        guestUserId: 'user',
        timeSlot: '21:30-22:30',
        time: '2026/11/20 16:54:08',
        createdAt: 1,
        withFriend: false,
        friendVrcid: '',
        services: const [' UNO ', '', '   ', '象棋'],
      );

      expect(params['p_services'], ['UNO', '象棋']);
    });
  });
}
