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
    test('picks the highest stable tag above the current version', () async {
      final service = AppUpdateService(
        remote: _FakeRemote([
          'v3.0.2',
          'v3.1.0-rc.1',
          'v3.0.0',
          'v3.0.1',
          'v3.1.0-alpha.2',
        ]),
        currentVersion: () async => '3.0.1+1',
      );

      final info = await service.check();

      expect(info.latestTag, 'v3.0.2');
      expect(info.hasUpdate, isTrue);
      expect(
        info.releaseUri.toString(),
        'https://github.com/ucrvk/suki/releases/tag/v3.0.2',
      );
    });

    test('ignores a newer rc or alpha tag', () async {
      final service = AppUpdateService(
        remote: _FakeRemote(['v3.0.1', 'v3.1.0-rc.1', 'v3.1.0-alpha.2']),
        currentVersion: () async => '3.0.1+1',
      );

      final info = await service.check();

      expect(info.latestTag, 'v3.0.1');
      expect(info.hasUpdate, isFalse);
      expect(info.releaseUri, isNull);
    });

    test('reports no update when the versions match', () async {
      final service = AppUpdateService(
        remote: _FakeRemote(['v3.0.1', 'v2.0.0']),
        currentVersion: () async => '3.0.1+1',
      );

      expect((await service.check()).hasUpdate, isFalse);
    });

    test('reports no update when only prereleases exist', () async {
      final service = AppUpdateService(
        remote: _FakeRemote(['v3.0.0-rc.1', 'v3.0.0-alpha.1']),
        currentVersion: () async => '3.0.0+1',
      );

      final info = await service.check();

      expect(info.latestTag, isNull);
      expect(info.hasUpdate, isFalse);
    });

    test('only compares tags on the same major version line', () async {
      // 项目 2.x 与 3.x 并行维护：3.x 客户端不该被 4.x 或 2.x 影响。
      final service = AppUpdateService(
        remote: _FakeRemote(['v4.0.0', 'v3.0.2', 'v2.9.0', 'v2.0.4']),
        currentVersion: () async => '3.0.2+1',
      );

      final info = await service.check();

      expect(info.latestTag, 'v3.0.2');
      expect(info.hasUpdate, isFalse);
    });

    test('finds updates inside the 2.x line', () async {
      final service = AppUpdateService(
        remote: _FakeRemote(['v3.0.2', 'v2.0.3', 'v2.0.4']),
        currentVersion: () async => '2.0.3+1',
      );

      final info = await service.check();

      expect(info.latestTag, 'v2.0.4');
      expect(info.hasUpdate, isTrue);
    });
  });

  group('GitHubTagRemote', () {
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
