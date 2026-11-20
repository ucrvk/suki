import 'package:flutter_test/flutter_test.dart';
import 'package:suki/utils/maid_services.dart';

void main() {
  group('MaidServiceOptions.fromMaid', () {
    test('hides when serviceOptions is missing', () {
      final options = MaidServiceOptions.fromMaid({'name': 'Fufu'});

      expect(options.isSelectable, isFalse);
      expect(options.options, isEmpty);
      expect(options.maxPick, 0);
    });

    test('hides when serviceOptions is empty', () {
      final options = MaidServiceOptions.fromMaid({'serviceOptions': []});

      expect(options.isSelectable, isFalse);
    });

    test('hides when explicitly disabled', () {
      final options = MaidServiceOptions.fromMaid({
        'servicesEnabled': false,
        'serviceOptions': ['UNO'],
      });

      expect(options.isSelectable, isFalse);
    });

    test('shows when servicesEnabled is missing but options exist', () {
      final options = MaidServiceOptions.fromMaid({
        'serviceOptions': ['UNO'],
      });

      expect(options.isSelectable, isTrue);
    });

    test('trims, drops empty values and dedupes', () {
      final options = MaidServiceOptions.fromMaid({
        'serviceOptions': [' UNO ', '', 'UNO', '象棋', '  象棋'],
      });

      expect(options.options, ['UNO', '象棋']);
    });

    test('missing serviceMaxPick means unlimited', () {
      final options = MaidServiceOptions.fromMaid({
        'serviceOptions': ['UNO', '象棋', '台球'],
      });

      expect(options.maxPick, 3);
      expect(options.hasLimit, isFalse);
      expect(options.isSingleChoice, isFalse);
    });

    test('zero or negative serviceMaxPick means unlimited', () {
      for (final value in [0, -1]) {
        final options = MaidServiceOptions.fromMaid({
          'serviceOptions': ['UNO', '象棋'],
          'serviceMaxPick': value,
        });

        expect(options.maxPick, 2);
        expect(options.hasLimit, isFalse);
      }
    });

    test('clamps serviceMaxPick to the option count', () {
      final options = MaidServiceOptions.fromMaid({
        'serviceOptions': ['UNO', '象棋'],
        'serviceMaxPick': 4,
      });

      expect(options.maxPick, 2);
      expect(options.hasLimit, isFalse);
    });

    test('single choice when maxPick is 1', () {
      final options = MaidServiceOptions.fromMaid({
        'serviceOptions': ['UNO', '象棋'],
        'serviceMaxPick': 1,
      });

      expect(options.isSingleChoice, isTrue);
      expect(options.hasLimit, isTrue);
    });

    test('sanitizeSelection keeps option order and drops unknown values', () {
      final options = MaidServiceOptions.fromMaid({
        'serviceOptions': ['UNO', '象棋', '台球'],
      });

      final selected = options.sanitizeSelection({'台球', '不存在', 'UNO'});

      expect(selected.toList(), ['UNO', '台球']);
    });
  });
}
