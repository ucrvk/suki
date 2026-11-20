import 'package:flutter_test/flutter_test.dart';
import 'package:suki/utils/reservation_details.dart';

void main() {
  group('ReservationDetails.fromRow', () {
    test('parses reservation fields and services', () {
      final details = ReservationDetails.fromRow({
        'guestUsername': '幕后鸭手',
        'guestUserId': 'user-1',
        'maidName': 'ma_su',
        'maidVrcid': 'maid_1',
        'timeSlot': '22:30-23:30',
        'withFriend': false,
        'createdAt': 1795097151404,
        'friendVrcid': '',
        'services': ['一起看电影', '星空望远镜'],
      });

      expect(details.guest, '幕后鸭手');
      expect(details.guestUserId, 'user-1');
      expect(details.maidName, 'ma_su');
      expect(details.maidVrcid, 'maid_1');
      expect(details.timeSlot, '22:30-23:30');
      expect(details.withFriend, isFalse);
      expect(details.createdAt, 1795097151404);
      expect(details.services, ['一起看电影', '星空望远镜']);
      expect(details.hasDetails, isTrue);
    });

    test('falls back to guest when guestUsername is missing', () {
      final details = ReservationDetails.fromRow({'guest': '幕后鸭手'});

      expect(details.guest, '幕后鸭手');
    });

    test('trims, drops empty values and dedupes services', () {
      final details = ReservationDetails.fromRow({
        'services': [' UNO ', '', 'UNO', '象棋', '  象棋'],
      });

      expect(details.services, ['UNO', '象棋']);
    });

    test('treats friendVrcid as the friend display name', () {
      final details = ReservationDetails.fromRow({
        'withFriend': true,
        'friendVrcid': '小奇kin',
      });

      expect(details.friendName, '小奇kin');
      expect(details.friendDisplay, '小奇kin');
      expect(details.hasDetails, isTrue);
    });

    test('hasDetails is false without friend and services', () {
      final details = ReservationDetails.fromRow({
        'guestUsername': '幕后鸭手',
        'services': <String>[],
      });

      expect(details.hasDetails, isFalse);
    });

    test('hasDetails is true with only services', () {
      final details = ReservationDetails.fromRow({
        'services': ['星空望远镜'],
      });

      expect(details.hasDetails, isTrue);
    });

    test('display fallbacks for missing fields', () {
      final details = ReservationDetails.fromRow({
        'withFriend': true,
        'maidVrcid': 'maid_1',
      });

      expect(details.guestDisplay, '匿名');
      expect(details.maidDisplay, 'maid_1');
      expect(details.friendDisplay, '已带好友');
    });

    test('uses 未命名 when both maid fields are empty', () {
      final details = ReservationDetails.fromRow({});

      expect(details.maidDisplay, '未命名');
      expect(details.friendDisplay, '');
    });
  });
}
