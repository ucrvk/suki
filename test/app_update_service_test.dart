import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:suki/services/app_update_service.dart';

void main() {
  group('AppVersion.parse', () {
    test('accepts stable versions with or without the v prefix', () {
      expect(AppVersion.parse('v3.0.1')!.parts, [3, 0, 1]);
      expect(AppVersion.parse('3.0.1')!.parts, [3, 0, 1]);
      expect(AppVersion.parse('1.1.3+1')!.parts, [1, 1, 3, 1]);
      expect(AppVersion.parse(' v2.0 ')!.parts, [2, 0]);
    });

    test('ignores rc / alpha and every other suffix', () {
      for (final tag in const [
        'v3.0.0-rc.1',
        'v3.0.0-rc.2',
        'v1.2.3-rc1',
        'v3.0.0-alpha.1',
        'v2.0.0-beta.3',
        'v3.0.0-rc.1+1',
        'v3.0.0+1-rc',
        'release-3.0.0',
        'v',
        '',
      ]) {
        expect(AppVersion.parse(tag), isNull, reason: tag);
      }
    });

    test('compares numeric segments from left to right', () {
      int compare(String a, String b) =>
          AppVersion.parse(a)!.compareTo(AppVersion.parse(b)!);

      expect(compare('3.0.2', 'v3.0.1'), 1);
      expect(compare('3.0.1', '3.0.1'), 0);
      expect(compare('3.0', '3.0.1'), -1);
      expect(compare('3.1', '3.0.9'), 1);
      // build 号参与比较，缺省按 0 处理。
      expect(compare('3.0.1+2', '3.0.1+1'), 1);
      expect(compare('3.0.1+1', '3.0.1'), 1);
    });
  });

  group('AppUpdateService.check', () {
    for (final scenario in [
      (
        ['v3.9.0', 'v20.0.0', 'v2.0.4', 'v2.0.10', 'v2.1.0-rc.1'],
        '2.0.3+1',
        'v2.0.10',
        true,
      ),
      (['v3.0.2', 'v2.0.3'], '2.0.3+1', 'v2.0.3', false),
      (['v2.0.4+1'], '2.0.4+1', 'v2.0.4+1', false),
      (['v2.0.4+2'], '2.0.4+1', 'v2.0.4+2', true),
      (['v3.0.2', 'v2.1.0-beta', 'release-2.2.0'], '2.0.3+1', null, false),
    ]) {
      test('2.x selection: $scenario', () async {
        final info = await AppUpdateService(
          remote: _FakeRemote(scenario.$1),
          currentVersion: () async => scenario.$2,
        ).check();
        expect(info.latestTag, scenario.$3);
        expect(info.hasUpdate, scenario.$4);
        expect(
          info.releaseUri?.toString(),
          scenario.$4
              ? 'https://github.com/ucrvk/suki/releases/tag/${scenario.$3}'
              : null,
        );
      });
    }
    test(
      'rejects an unknown current version rather than claiming up to date',
      () async {
        for (final current in ['unknown', '3.0.0']) {
          await expectLater(
            AppUpdateService(
              remote: _FakeRemote(['v2.0.4']),
              currentVersion: () async => current,
            ).check(),
            throwsA(isA<AppUpdateException>()),
          );
        }
      },
    );
    test('propagates network failure', () async {
      await expectLater(
        AppUpdateService(
          remote: _FailingRemote(),
          currentVersion: () async => '2.0.3',
        ).check(),
        throwsA(isA<AppUpdateException>()),
      );
    });
  });

  group('GitHubTagRemote', () {
    test('finds 2.x updates beyond the first page of newer tags', () async {
      var requests = 0;
      final remote = GitHubTagRemote(
        client: MockClient((request) async {
          requests++;
          if (requests == 1) {
            return http.Response(
              jsonEncode(List.generate(100, (i) => {'name': 'v3.0.$i'})),
              200,
            );
          }
          expect(request.url.queryParameters['page'], '2');
          return http.Response(
            jsonEncode([
              {'name': 'v2.0.4'},
            ]),
            200,
          );
        }),
      );
      final info = await AppUpdateService(
        remote: remote,
        currentVersion: () async => '2.0.3+1',
      ).check();
      expect(info.latestTag, 'v2.0.4');
      expect(info.hasUpdate, isTrue);
      expect(requests, 2);
    });
    test('rejects an invalid GitHub response', () async {
      final remote = GitHubTagRemote(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        remote.fetchTagNames(),
        throwsA(isA<AppUpdateException>()),
      );
    });
    test('reads the tag names from the GitHub payload', () async {
      final remote = GitHubTagRemote(
        client: MockClient((request) async {
          expect(request.url.path, '/repos/ucrvk/suki/tags');
          expect(request.url.queryParameters['per_page'], '100');
          return http.Response(
            jsonEncode([
              {'name': 'v3.0.1'},
              {'name': 'v3.0.0'},
              {'commit': 'ignored'},
            ]),
            200,
          );
        }),
      );

      expect(await remote.fetchTagNames(), ['v3.0.1', 'v3.0.0']);
    });

    test('throws when GitHub answers with an error status', () async {
      final remote = GitHubTagRemote(
        client: MockClient((_) async => http.Response('rate limited', 403)),
      );

      await expectLater(
        remote.fetchTagNames(),
        throwsA(isA<AppUpdateException>()),
      );
    });
  });
}

class _FakeRemote implements AppUpdateRemote {
  _FakeRemote(this.tags);

  final List<String> tags;

  @override
  Future<List<String>> fetchTagNames() async => tags;
}

class _FailingRemote implements AppUpdateRemote {
  @override
  Future<List<String>> fetchTagNames() async =>
      throw const AppUpdateException('network unavailable');
}
