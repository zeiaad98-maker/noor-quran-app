import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';

/// v13.16 — THE FIX for the poisoned cache.
///
/// Proven by the v13.15 diagnostic screenshot (2026-11-19, 12:50):
/// the sheet showed version 1.0.27 (v13.15 WAS installed), NO
/// download error line, and stream error "play — TimeoutException
/// after 0:00:10.000000" — a timeout from the LOCAL-file branch.
/// A partial/empty/corrupt file left by an old stalled download
/// was trusted by localAyahFile (existsSync only), returned
/// without downloading, and _playCurrent never fell back to
/// streaming when the local file failed to play — so the same
/// error hit the same ayahs across v13.10–v13.15.
///
/// The fix has two layers: (1) a ONE-TIME full purge on the
/// first run of 1.0.28 — the user's order ("احذف لي كل شي
/// خربان... ما بدي شي خربان لقدام") — the whole audio cache goes
/// once, with the downloaded-surahs state cleared with it; (2)
/// permanent per-file validation (size + MP3 magic), so an
/// invalid file is deleted and re-downloaded and a local file
/// that will not play falls back to streaming — nothing broken
/// can ever come back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  Future<(AudioDownloadService, Directory)> buildService(
      http.Client client) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('v1316-cache');
    addTearDown(() => tempDir.delete(recursive: true));
    final service = AudioDownloadService(
      client: client,
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
    );
    await service.init();
    addTearDown(service.dispose);
    return (service, tempDir);
  }

  /// A fake "real" MP3: an ID3 tag (or an MPEG frame sync) padded
  /// with zeros to [size] bytes — what a complete per-ayah file
  /// looks like to the validator.
  List<int> validMp3({bool frameSync = false, int size = 2048}) {
    final head = frameSync
        ? <int>[0xFF, 0xFB, 0xE0, 0x40]
        : <int>[0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21];
    return [...head, ...List<int>.filled(size - head.length, 0)];
  }

  File ayahFile(Directory tempDir, int surah, int ayah) => File(
      '${tempDir.path}/${reciters[0].everyayah}/'
      '${ayahFileName(surah, ayah)}.mp3');

  File wbwFile(Directory tempDir, int surah, int ayah, int fileNumber) =>
      File('${tempDir.path}/wbw/${ayahFileName(surah, ayah)}_'
          '${fileNumber.toString().padLeft(3, '0')}.mp3');

  Future<void> seedFile(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  group('isValidAudioFile (v13.16)', () {
    test('rejects a missing file, an empty file, and a tiny file',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('v1316-val');
      addTearDown(() => tempDir.delete(recursive: true));
      final missing = File('${tempDir.path}/missing.mp3');
      expect(AudioDownloadService.isValidAudioFile(missing), isFalse);

      final empty = File('${tempDir.path}/empty.mp3');
      await empty.writeAsBytes([]);
      expect(AudioDownloadService.isValidAudioFile(empty), isFalse);

      // A real ID3 header — but only 100 bytes: a truncated file
      // is still poison, not a recording.
      final tiny = File('${tempDir.path}/tiny.mp3');
      await tiny.writeAsBytes(validMp3(size: 100));
      expect(AudioDownloadService.isValidAudioFile(tiny), isFalse);
    });

    test('rejects an error page saved as .mp3, even a large one',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('v1316-val');
      addTearDown(() => tempDir.delete(recursive: true));
      final html = File('${tempDir.path}/error.mp3');
      final bytes = [
        ...'<html><head><title>404 Not Found</title></head>'
            .codeUnits,
        ...List<int>.filled(2048, 0x20),
      ];
      await html.writeAsBytes(bytes);
      expect(AudioDownloadService.isValidAudioFile(html), isFalse);
    });

    test('accepts real MP3 headers: ID3 and MPEG frame sync', () async {
      final tempDir = await Directory.systemTemp.createTemp('v1316-val');
      addTearDown(() => tempDir.delete(recursive: true));
      final id3 = File('${tempDir.path}/id3.mp3');
      await id3.writeAsBytes(validMp3());
      expect(AudioDownloadService.isValidAudioFile(id3), isTrue);

      final frame = File('${tempDir.path}/frame.mp3');
      await frame.writeAsBytes(validMp3(frameSync: true));
      expect(AudioDownloadService.isValidAudioFile(frame), isTrue);

      // SurahPedia's real Husary files start FF F3, not FF FB.
      final f3 = File('${tempDir.path}/f3.mp3');
      await f3.writeAsBytes(
          [0xFF, 0xF3, 0x80, 0x64, ...List<int>.filled(2044, 0)]);
      expect(AudioDownloadService.isValidAudioFile(f3), isTrue);
    });
  });

  group('one-time full purge (v13.16)', () {
    test('first init deletes the whole cache and clears the '
        'downloaded-surahs state; second init leaves files alone',
        () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp('v1316-purge');
      addTearDown(() => tempDir.delete(recursive: true));
      final prefs = await SharedPreferences.getInstance();
      // A broken cache, exactly as on the user's phone: a valid
      // file, a garbage file, a manifest, a word file, and a
      // downloaded-surahs state claiming surah 2 is installed.
      final reciterDir =
          Directory('${tempDir.path}/${reciters[0].everyayah}');
      await seedFile(
          File('${reciterDir.path}/002001.mp3'), validMp3());
      await seedFile(File('${reciterDir.path}/002002.mp3'),
          [0x3C, 0x68, 0x74, 0x6D, 0x6C]); // "<html" garbage
      await seedFile(File('${reciterDir.path}/manifest.json'),
          '{"done": true}'.codeUnits);
      await seedFile(
          File('${tempDir.path}/wbw/002001_001.mp3'), validMp3());
      await prefs.setStringList('audio_dl_surahs_0', ['2']);

      final service = AudioDownloadService(
        client: MockClient((_) async => http.Response.bytes([], 404)),
        storageDir: tempDir,
        prefs: prefs,
      );
      await service.init();
      addTearDown(service.dispose);

      // Everything is gone — files, manifests, and the state.
      expect(await reciterDir.exists(), isFalse);
      expect(await Directory('${tempDir.path}/wbw').exists(), isFalse);
      expect(service.downloadedSurahsOf(0), isEmpty);
      expect(prefs.getStringList('audio_dl_surahs_0'), isNull);
      expect(prefs.getBool('audio_cache_purged_v1316'), isTrue);

      // Second init leaves a fresh file and fresh state alone —
      // the purge ran exactly once.
      final fresh = File('${reciterDir.path}/002001.mp3');
      await seedFile(fresh, validMp3());
      await prefs.setStringList('audio_dl_surahs_0', ['2']);
      final service2 = AudioDownloadService(
        client: MockClient((_) async => http.Response.bytes([], 404)),
        storageDir: tempDir,
        prefs: prefs,
      );
      await service2.init();
      addTearDown(service2.dispose);
      expect(await fresh.exists(), isTrue);
      expect(service2.downloadedSurahsOf(0), contains(2));
      expect(prefs.getBool('audio_cache_purged_v1316'), isTrue);
    });
  });

  group('poisoned ayah cache is re-downloaded (v13.16)', () {
    test('a 0-byte cached file is ignored and re-downloaded', () async {
      final requested = <String>[];
      final (service, tempDir) = await buildService(MockClient(
          (request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(validMp3(), 200);
      }));
      await seedFile(ayahFile(tempDir, 2, 1), []);

      final file = await service.cacheAyahFile(reciters[0], 2, 1);

      expect(file, isNotNull);
      expect(await file!.length(), 2048);
      // The first host served it — one request, no chain walk.
      expect(requested, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
      ]);
    });

    test('an HTML error page cached as .mp3 is ignored and '
        're-downloaded', () async {
      final requested = <String>[];
      final (service, tempDir) = await buildService(MockClient(
          (request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(validMp3(), 200);
      }));
      final html = [
        ...'<html><head><title>404 Not Found</title></head>'
            .codeUnits,
        ...List<int>.filled(2048, 0x20),
      ];
      await seedFile(ayahFile(tempDir, 2, 1), html);

      final file = await service.cacheAyahFile(reciters[0], 2, 1);

      expect(file, isNotNull);
      expect(await file!.length(), 2048);
      expect(requested, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
      ]);
    });

    test('a tiny file with a real ID3 header is ignored and '
        're-downloaded', () async {
      final (service, tempDir) = await buildService(MockClient(
          (request) async => http.Response.bytes(validMp3(), 200)));
      await seedFile(ayahFile(tempDir, 2, 1), validMp3(size: 100));

      final file = await service.cacheAyahFile(reciters[0], 2, 1);

      expect(file, isNotNull);
      expect(await file!.length(), 2048);
    });

    test('a valid cached file is used without any network', () async {
      final requested = <String>[];
      final (service, tempDir) = await buildService(MockClient(
          (request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(validMp3(), 200);
      }));
      final seeded = validMp3();
      await seedFile(ayahFile(tempDir, 2, 1), seeded);

      final file = await service.cacheAyahFile(reciters[0], 2, 1);

      expect(file, isNotNull);
      expect(await file!.readAsBytes(), seeded);
      expect(requested, isEmpty);
    });

    test('a frame-sync cached file is used without any network',
        () async {
      final requested = <String>[];
      final (service, tempDir) = await buildService(MockClient(
          (request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(validMp3(), 200);
      }));
      final seeded = validMp3(frameSync: true);
      await seedFile(ayahFile(tempDir, 2, 2), seeded);

      final file = await service.cacheAyahFile(reciters[0], 2, 2);

      expect(file, isNotNull);
      expect(await file!.readAsBytes(), seeded);
      expect(requested, isEmpty);
    });
  });

  group('poisoned wbw cache is re-downloaded (v13.16)', () {
    test('a 0-byte cached word file is ignored and re-downloaded',
        () async {
      final (service, tempDir) = await buildService(MockClient(
          (request) async => http.Response.bytes(validMp3(), 200)));
      await seedFile(wbwFile(tempDir, 2, 1, 1), []);

      final file = await service.cacheWbwFile(2, 1, 1);

      expect(file, isNotNull);
      expect(await file!.length(), 2048);
    });

    test('a valid cached word file is used without any network',
        () async {
      final requested = <String>[];
      final (service, tempDir) = await buildService(MockClient(
          (request) async {
        requested.add(request.url.toString());
        return http.Response.bytes(validMp3(), 200);
      }));
      final seeded = validMp3();
      await seedFile(wbwFile(tempDir, 2, 1, 1), seeded);

      final file = await service.cacheWbwFile(2, 1, 1);

      expect(file, isNotNull);
      expect(await file!.readAsBytes(), seeded);
      expect(requested, isEmpty);
    });
  });

  group('local play failure falls back to streaming (v13.16)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.failPlayCount = 0;
      fake.resetCounts();
    });

    test('a cached file whose play() times out is deleted and '
        'the page streams instead (Husary page 2)', () async {
      final (service, tempDir) = await buildService(MockClient(
          (request) async => http.Response.bytes([], 404)));
      // A file that PASSES validation (real ID3 header, 2 KB)
      // but will not play — the exact poisoned-cache case from
      // the diagnostic screenshot.
      final poisoned = ayahFile(tempDir, 2, 1);
      await seedFile(poisoned, validMp3());
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      fake.failPlayCount = 1; // the local play() hangs once

      await controller.playPages(2, 2);

      // The page PLAYS — through the native stream, not the
      // poisoned file — with no error at all.
      expect(fake.player.playing, isTrue);
      expect(controller.lastError, isNull);
      expect(controller.lastStreamError, isNull);
      expect(controller.lastDiagnostic, isNull);
      // And the poisoned file is gone from the disk.
      expect(await poisoned.exists(), isFalse);
      expect(service.localAyahFile(reciters[0], 2, 1), isNull);
      // The stream really happened: the fake loaded an https URL.
      expect(fake.loadUris.any((u) => u.startsWith('https://')),
          isTrue);
      // Let the next-ayah prefetch settle before teardown deletes
      // the temp dir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('when streaming fails too, the diagnostic names the '
        'bad file and its size', () async {
      final (service, tempDir) = await buildService(MockClient(
          (request) async => http.Response.bytes([], 404)));
      final poisoned = ayahFile(tempDir, 2, 1);
      await seedFile(poisoned, validMp3());
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      fake.failPlayCount = 1; // the local play() hangs once
      // Every stream load fails ('http' matches all six stream
      // URLs — https and the www http host — but not the local
      // file:// URI), so the fallback has nowhere to go.
      fake.failLoadSubstrings.add('http');

      await controller.playPages(2, 2);

      expect(controller.lastError,
          'تعذّر تحميل الصوت — تحقق من الاتصال وحاول مجدداً');
      // The diagnostic keeps the FIRST failure — the poisoned
      // local file, with its size — not a later stream URL.
      expect(controller.lastDiagnostic, isNotNull);
      expect(controller.lastDiagnostic, contains('تشغيل:'));
      expect(controller.lastDiagnostic, contains('2048 bytes'));
      expect(controller.lastDiagnostic, contains('TimeoutException'));
      // The poisoned file is gone even though playback failed.
      expect(await poisoned.exists(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });
}
