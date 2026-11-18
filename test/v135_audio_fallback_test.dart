import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';
import 'zip_fixture.dart';

/// v13.5 audio fallbacks, order updated in v13.6 and v13.7.
///
/// Word audio: SurahPedia FIRST (resources.surahpedia.com — Wahy's
/// host, byte-identical files), then the Quran.com wbw hosts.
/// Ayah audio (v13.7 order): the per-ayah file over the www host
/// (`http://www.everyayah.com/...`, Wahy's address — the one that
/// opens from the user's Syrian network) goes FIRST, so playback
/// starts in seconds; the per-surah ZIP is the fallback (and the
/// explicit bulk download), and the bare-HTTPS per-ayah file is
/// the last resort. No real HTTP is made: MockClient serves
/// in-memory ZIPs built by test/zip_fixture.dart, and the fake
/// just_audio platform stands in for playback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  group('wbw SurahPedia fallback (v13.5)', () {
    late Directory tempDir;
    late AudioDownloadService service;
    var serviceCreated = false;

    Future<AudioDownloadService> buildService(http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v135-wbw');
      final s = AudioDownloadService(
        client: client,
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await s.init();
      serviceCreated = true;
      return s;
    }

    tearDown(() async {
      // The URL-pattern test creates no service/temp dir.
      if (!serviceCreated) return;
      service.dispose();
      await tempDir.delete(recursive: true);
      serviceCreated = false;
    });

    test('wbwWordUrlSurahPedia builds the slash-separated pattern', () {
      // Wahy's exact pattern (verified live 2026-11-17: its API
      // redirects to these files, byte-identical to the Quran.com
      // wbw files — 003007015 speaks الَّذِينَ on both hosts).
      expect(wbwWordUrlSurahPedia(3, 7, 15),
          'https://resources.surahpedia.com/Word_by-Word/3/003007015.mp3');
      expect(wbwWordUrlSurahPedia(1, 2, 4),
          'https://resources.surahpedia.com/Word_by-Word/1/001002004.mp3');
    });

    test('SurahPedia first (v13.6): word caches on the first attempt, '
        'no Quran.com host is hit', () async {
      final requested = <String>[];
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'resources.surahpedia.com') {
          return http.Response.bytes([5, 5, 5], 200);
        }
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheWbwFile(3, 7, 15);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [5, 5, 5]);
      expect(requested, [
        'https://resources.surahpedia.com/Word_by-Word/3/003007015.mp3',
      ]);
      // Second call replays from disk: no further request.
      final second = await service.cacheWbwFile(3, 7, 15);
      expect(second?.path, file.path);
      expect(requested.length, 1, reason: 'no second download');
    });

    test('all three wbw hosts fail → null, no file left behind',
        () async {
      service = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheWbwFile(3, 7, 15);
      expect(file, isNull);
      expect(service.localWbwFile(3, 7, 15), isNull);
    });
  });

  group('ayah surah ZIP (v13.5)', () {
    late Directory tempDir;
    late AudioDownloadService service;
    var serviceCreated = false;

    Future<AudioDownloadService> buildService(http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v135-zip');
      final s = AudioDownloadService(
        client: client,
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await s.init();
      serviceCreated = true;
      return s;
    }

    tearDown(() async {
      // The URL-builder test creates no service/temp dir.
      if (!serviceCreated) return;
      service.dispose();
      await tempDir.delete(recursive: true);
      serviceCreated = false;
    });

    test('everyayahSurahZipUrl builds Wahy\'s exact address', () {
      expect(everyayahSurahZipUrl(reciters[12], 1),
          'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/zips/001.zip');
      expect(everyayahSurahZipUrl(reciters[1], 2),
          'http://www.everyayah.com/data/Alafasy_64kbps/zips/002.zip');
    });

    test('ZIP download → unzip → play: Tunaiji 1:1 and 1:7', () async {
      final requested = <String>[];
      // Stored entries, like the real everyayah ZIPs (verified live
      // 2026-11-17: the real Tunaiji 001.zip stores all 7 MP3s).
      // Distinct bytes per ayah, so the test proves the RIGHT file
      // is served for each ayah.
      final zipBytes = buildSurahZip(
        {for (var a = 1; a <= 7; a++) '00100$a.mp3': [a]},
        stored: true,
      );
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes(zipBytes, 200);
        }
        // v13.7: the www per-ayah attempt goes first and 404s here,
        // so the ZIP path runs.
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([9, 9], 200);
      }));
      final tunaiji = reciters[12];

      final first = await service.cacheAyahFile(tunaiji, 1, 1);
      expect(first, isNotNull);
      expect(await first!.readAsBytes(), [1]);
      // One ZIP request cached the whole surah: the next ayah in
      // the same surah needs no further download.
      final seventh = await service.cacheAyahFile(tunaiji, 1, 7);
      expect(seventh, isNotNull);
      expect(await seventh!.readAsBytes(), [7]);
      expect(requested, [
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/001001.mp3',
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/zips/001.zip',
      ]);
      // The ZIP itself is deleted after extraction — the extracted
      // per-ayah files ARE the cache.
      expect(
          Directory('${tempDir.path}/${tunaiji.everyayah}/zips').exists(),
          completion(isFalse));
      expect(service.localAyahFile(tunaiji, 1, 3), isNotNull);
    });

    test('deflated ZIP entries inflate correctly', () async {
      final zipBytes = buildSurahZip(
        {for (var a = 1; a <= 4; a++) '11200$a.mp3': [a, a, a]},
      );
      service = await buildService(MockClient((request) async {
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes(zipBytes, 200);
        }
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 2);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [2, 2, 2]);
    });

    test('failed www per-ayah and ZIP fall back to the bare per-ayah file',
        () async {
      final requested = <String>[];
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([7, 7], 200);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 2);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [7, 7]);
      expect(requested, [
        'http://www.everyayah.com/data/Husary_64kbps/112002.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/zips/112.zip',
        'https://everyayah.com/data/Husary_64kbps/112002.mp3',
      ]);
    });

    test('ZIP missing the ayah falls back to per-ayah for it', () async {
      final requested = <String>[];
      // The ZIP holds only 001001 — the requested 1:7 is not in it.
      final zipBytes = buildSurahZip(
        {'001001.mp3': [1]},
        stored: true,
      );
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes(zipBytes, 200);
        }
        // v13.7: the www per-ayah attempt goes first and 404s here,
        // so the ZIP path runs.
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([7], 200);
      }));
      final tunaiji = reciters[12];

      final file = await service.cacheAyahFile(tunaiji, 1, 7);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [7]);
      expect(requested, [
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/001007.mp3',
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/zips/001.zip',
        'https://everyayah.com/data/khalefa_al_tunaiji_64kbps/001007.mp3',
      ]);
      // The ZIP's own ayah is on disk too.
      expect(await service.localAyahFile(tunaiji, 1, 1)!.readAsBytes(),
          [1]);
    });

    test('garbage ZIP bytes fall back to per-ayah', () async {
      service = await buildService(MockClient((request) async {
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes([9, 9, 9], 200);
        }
        // v13.7: the www per-ayah attempt goes first and 404s here,
        // so the garbage-ZIP path is exercised.
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([4], 200);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 3);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [4]);
    });

    test('ZIP and per-ayah both fail → null, no file left behind',
        () async {
      service = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 3);
      expect(file, isNull);
      expect(service.localAyahFile(reciters[0], 112, 3), isNull);
    });
  });

  group('controller — ZIP + SurahPedia stream fallbacks (fake platform)',
      () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.resetCounts();
    });

    test('SurahPedia first (v13.6): word plays on the first attempt',
        () async {
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      fake.failLoadSubstrings
          .addAll(['audio.qurancdn.com', 'verses.quran.com']);
      controller.queue = [(3, 7)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 15; // الَّذِينَ — file 015 (v13.4)
      await controller.replayCurrent();

      // SurahPedia answers first, so the Quran.com hosts are never hit.
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Word_by-Word/3/003007015.mp3',
      ]);
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    test('SurahPedia down: word still plays via qurancdn (v13.6 order)',
        () async {
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      fake.failLoadSubstrings.add('resources.surahpedia.com');
      controller.queue = [(3, 7)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 15; // الَّذِينَ — file 015 (v13.4)
      await controller.replayCurrent();

      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Word_by-Word/3/003007015.mp3',
        'https://audio.qurancdn.com/wbw/003_007_015.mp3',
      ]);
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    test('ayah plays from the ZIP-cached local file (Tunaiji 1:1)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir =
          await Directory.systemTemp.createTemp('v135-ctrl-zip');
      addTearDown(() => tempDir.delete(recursive: true));
      final zipBytes = buildSurahZip(
        {for (var a = 1; a <= 7; a++) '00100$a.mp3': [a]},
        stored: true,
      );
      final downloads = AudioDownloadService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('.zip')) {
            return http.Response.bytes(zipBytes, 200);
          }
          return http.Response.bytes([], 404);
        }),
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await downloads.init();
      addTearDown(downloads.dispose);
      final controller = AudioPlayerController(downloads: downloads);
      addTearDown(controller.dispose);
      controller.reciterIndex = 12; // خليفة الطنيجي (default)

      await controller.playAyah(1, 1);

      expect(controller.lastError, isNull);
      expect(fake.loadCount, 1);
      expect(fake.player.playing, isTrue);
      // The ZIP was downloaded and extracted — the ayah is on disk.
      expect(
          downloads.localAyahFile(reciters[12], 1, 1), isNotNull);
      expect(
          await downloads.localAyahFile(reciters[12], 1, 1)!.readAsBytes(),
          [1]);
    });

    test('ZIP fails: ayah still plays via the per-ayah stream', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir =
          await Directory.systemTemp.createTemp('v135-ctrl-stream');
      addTearDown(() => tempDir.delete(recursive: true));
      final downloads = AudioDownloadService(
        client: MockClient((request) async {
          return http.Response.bytes([], 404);
        }),
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await downloads.init();
      addTearDown(downloads.dispose);
      final controller = AudioPlayerController(downloads: downloads);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      await controller.playAyah(2, 33);

      expect(controller.lastError, isNull);
      expect(fake.loadUris,
          ['https://everyayah.com/data/Husary_64kbps/002033.mp3']);
      expect(fake.player.playing, isTrue);
    });
  });
}
