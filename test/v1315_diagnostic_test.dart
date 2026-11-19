import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';

/// v13.15 (DIAGNOSTIC): the app must SHOW the real error.
///
/// Five versions (v13.10–v13.14) failed on the user's phone with
/// the same generic «تعذّر تحميل الصوت» and no visible cause:
/// the download service returned null/false and the player
/// returned false, and every real exception was thrown away.
/// This test proves the diagnostic fields capture the failure:
/// the download service records host + exception, the controller
/// records URL + exception, and _reportError composes both under
/// the approved generic Arabic line.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  Future<AudioDownloadService> buildService(http.Client client) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('v1315-diag');
    addTearDown(() => tempDir.delete(recursive: true));
    final service = AudioDownloadService(
      client: client,
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
    );
    await service.init();
    addTearDown(service.dispose);
    return service;
  }

  group('download service records the real failure (v13.15)', () {
    test('404 on every host: lastDownloadError names the host and '
        'the HTTP code', () async {
      final service = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheAyahFile(reciters[0], 2, 1);

      expect(file, isNull);
      // The chain ends at the bare host, so the last failure is
      // its 404 — host AND code, not a silent null.
      expect(service.lastDownloadError, isNotNull);
      expect(service.lastDownloadError, contains('everyayah.com'));
      expect(service.lastDownloadError, contains('HTTP 404'));
    });

    test('throwing client: lastDownloadError names the host and '
        'the exception type', () async {
      final service = await buildService(MockClient((request) async {
        throw http.ClientException('Connection failed', request.url);
      }));

      final file = await service.cacheAyahFile(reciters[0], 2, 1);

      expect(file, isNull);
      expect(service.lastDownloadError, isNotNull);
      expect(service.lastDownloadError, contains('everyayah.com'));
      expect(service.lastDownloadError, contains('ClientException'));
    });

    test('preload still missing: lastDownloadError is set', () async {
      final service = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));

      final ok = await service.preloadAyahs(reciters[0], [(2, 1), (2, 2)]);

      expect(ok, isFalse);
      expect(service.lastDownloadError, isNotNull);
      expect(service.lastDownloadError, contains('HTTP 404'));
    });
  });

  group('controller records the stream failure (v13.15)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.resetCounts();
    });

    test('downloads AND native loads fail: the sheet error keeps '
        'the generic line AND the diagnostic detail (Husary page 2)',
        () async {
      final downloads = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      final controller = AudioPlayerController(downloads: downloads);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري — the user's failing case
      // The native player fails every stream URL, like the Dart
      // downloads already did.
      fake.failLoadSubstrings.add('mp3');

      await controller.playPages(2, 2);

      // The approved generic line is UNCHANGED.
      expect(controller.lastError,
          'تعذّر تحميل الصوت — تحقق من الاتصال وحاول مجدداً');
      // The stream error names the URL that failed.
      expect(controller.lastStreamError, isNotNull);
      expect(controller.lastStreamError, contains('002001.mp3'));
      // v13.17: the page streams DIRECTLY — no foreground Dart
      // download ran, so the diagnostic shows ONLY the stream
      // stage, never a download stage.
      expect(controller.lastDiagnostic, isNotNull);
      expect(controller.lastDiagnostic, contains('تشغيل:'));
      expect(controller.lastDiagnostic, isNot(contains('تنزيل:')));

      // Retry with the native player working: the page plays and
      // the diagnosis clears — no stale error survives a success.
      fake.failLoadSubstrings.clear();
      await controller.retryLastError();
      expect(controller.lastError, isNull);
      expect(controller.lastStreamError, isNull);
      expect(controller.lastDiagnostic, isNull);
      expect(fake.player.playing, isTrue);
      // Let the next-ayah prefetch settle before teardown deletes
      // the temp dir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('surah scope: the download DOES run first, so the '
        'diagnostic shows BOTH stages when it fails too', () async {
      final downloads = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      final controller = AudioPlayerController(downloads: downloads);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      fake.failLoadSubstrings.add('mp3');

      await controller.playSurah(2);

      expect(controller.lastError,
          'تعذّر تحميل الصوت — تحقق من الاتصال وحاول مجدداً');
      expect(controller.lastStreamError, isNotNull);
      expect(controller.lastStreamError, contains('002001.mp3'));
      // The surah scope downloads first (v13.17 keeps it), so
      // the Dart 404 IS recorded and the diagnostic shows both
      // stages: the native-player (stream) failure AND the Dart
      // (download) failure.
      expect(controller.lastDiagnostic, isNotNull);
      expect(controller.lastDiagnostic, contains('تشغيل:'));
      expect(controller.lastDiagnostic, contains('تنزيل:'));
      expect(controller.lastDiagnostic, contains('HTTP 404'));

      // Retry with the native player working: the surah plays and
      // the diagnosis clears.
      fake.failLoadSubstrings.clear();
      await controller.retryLastError();
      expect(controller.lastError, isNull);
      expect(controller.lastStreamError, isNull);
      expect(controller.lastDiagnostic, isNull);
      expect(fake.player.playing, isTrue);
      // Let the next-ayah prefetch settle before teardown deletes
      // the temp dir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });

  group('diagnostic fast failure (v13.15, TEMPORARY)', () {
    test('stall timeout is 30s and two attempts per URL', () {
      // v13.16: the diagnostic values are REVERTED — a failing
      // download must NOT surface fast any more; the user's rule
      // is that audio downloads at any speed, even the slowest.
      expect(AudioDownloadService.stallTimeout,
          const Duration(seconds: 30));
      expect(AudioDownloadService.fetchAttempts, 2);
    });
  });
}
