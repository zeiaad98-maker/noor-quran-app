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

/// v13.5 audio fallbacks, order updated in v13.6, v13.7 and v13.11.
///
/// Word audio: SurahPedia FIRST (resources.surahpedia.com — Wahy's
/// host, byte-identical files), then the Quran.com wbw hosts.
/// Ayah audio (v13.11 order): the per-ayah file over the www host
/// (`http://www.everyayah.com/...`, Wahy's address — the one that
/// opens from the user's Syrian network) goes FIRST, so playback
/// starts in seconds; then islamic.network per-ayah (a DIFFERENT
/// host, only for reciters with a content-verified edition); then
/// the bare-HTTPS per-ayah file; then the per-surah ZIP (same host,
/// caches the surah offline); and one last bare retry if the ZIP
/// extracted but lacks the ayah. No real HTTP is made: MockClient
/// serves in-memory ZIPs built by test/zip_fixture.dart, and the
/// fake just_audio platform stands in for playback.
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

    /// Wait (real async) until the service has no running job.
    Future<void> waitForIdle(AudioDownloadService s) async {
      for (var i = 0; i < 200; i++) {
        if (!s.isDownloading) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('download did not finish in time');
    }

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
        return http.Response.bytes([], 404);
      }));
      final tunaiji = reciters[12];

      // v13.12 (user's correction): the ZIP lives ONLY in the
      // explicit bulk download the user starts himself from
      // «تحميل التلاوات» — playback never requests it.
      expect(await service.downloadSurahs(12, [1]), isTrue);
      await waitForIdle(service);

      final job = service.activeJob!;
      expect(job.status, DownloadStatus.done);
      expect(service.isSurahDownloaded(12, 1), isTrue);
      // One ZIP request cached the whole surah.
      expect(requested, [everyayahSurahZipUrl(tunaiji, 1)]);
      for (var a = 1; a <= 7; a++) {
        final cached = service.localAyahFile(tunaiji, 1, a);
        expect(cached, isNotNull, reason: 'ayah 1:$a cached');
        expect(await cached!.readAsBytes(), [a]);
      }
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

      // v13.12: the ZIP is bulk-download only — surah 112 has
      // 4 ayahs, the ZIP holds all 4, deflated.
      expect(await service.downloadSurahs(0, [112]), isTrue);
      await waitForIdle(service);

      expect(service.activeJob!.status, DownloadStatus.done);
      final file = service.localAyahFile(reciters[0], 112, 2);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [2, 2, 2]);
    });

    test('failed SurahPedia, www per-ayah and islamic.network fall '
        'back to the bare per-ayah file (v13.13 order)', () async {
      final requested = <String>[];
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'resources.surahpedia.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'cdn.islamic.network') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        // v13.12: Husary's alternate hosts (mirror + Maqra) 404
        // here too — they sit between islamic.network and bare
        // in the chain, so the bare file is what serves it.
        if (request.url.host == 'mirrors.quranicaudio.com' ||
            request.url.host == 'huggingface.co') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([7, 7], 200);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 2);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [7, 7]);
      // No ZIP request: the bare file served the ayah first.
      expect(requested, [
        'https://resources.surahpedia.com/Husary/112002.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/112002.mp3',
        'https://cdn.islamic.network/quran/audio/64/ar.husary/6223.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/112002.mp3',
        'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/112002.mp3',
        'https://everyayah.com/data/Husary_64kbps/112002.mp3',
      ]);
    });

    test('ZIP missing the ayah falls back to per-ayah for it', () async {
      AudioDownloadService.fetchAttempts = 1;
      addTearDown(() => AudioDownloadService.fetchAttempts = 1);
      final requested = <String>[];
      // The ZIP holds only 001001 — the other 6 ayahs are not in it.
      final zipBytes = buildSurahZip(
        {'001001.mp3': [1]},
        stored: true,
      );
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes(zipBytes, 200);
        }
        // The bulk job fills the missing ayahs with [_downloadOne],
        // which fetches the bare per-ayah file — one small file per
        // missing ayah, distinct bytes each.
        if (request.url.host == 'everyayah.com') {
          final name = request.url.pathSegments.last;
          final ayah = int.parse(name.substring(3, 6));
          return http.Response.bytes([ayah], 200);
        }
        return http.Response.bytes([], 404);
      }));
      final tunaiji = reciters[12];

      // v13.12: the ZIP is bulk-download only.
      expect(await service.downloadSurahs(12, [1]), isTrue);
      await waitForIdle(service);

      expect(service.activeJob!.status, DownloadStatus.done);
      expect(service.isSurahDownloaded(12, 1), isTrue);
      expect(requested, [
        everyayahSurahZipUrl(tunaiji, 1),
        for (var a = 2; a <= 7; a++)
          'https://everyayah.com/data/khalefa_al_tunaiji_64kbps/00100$a.mp3',
      ]);
      // All 7 ayahs cached: the ZIP's own ayah plus the per-ayah
      // fill-ins.
      for (var a = 1; a <= 7; a++) {
        final cached = service.localAyahFile(tunaiji, 1, a);
        expect(cached, isNotNull, reason: 'ayah 1:$a cached');
        expect(await cached!.readAsBytes(), [a]);
      }
    });

    test('garbage ZIP bytes are never requested in playback; '
        'per-ayah serves it', () async {
      service = await buildService(MockClient((request) async {
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes([9, 9, 9], 200);
        }
        // v13.12: playback never requests the ZIP — the www
        // per-ayah file serves the ayah, so the garbage ZIP is
        // never even downloaded.
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([4], 200);
        }
        return http.Response.bytes([4], 200);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 3);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [4]);
    });

    test('per-ayah hosts all fail → null, no file left behind',
        () async {
      service = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 3);
      expect(file, isNull);
      expect(service.localAyahFile(reciters[0], 112, 3), isNull);
    });
  });

  group('controller — bulk download + SurahPedia stream fallbacks '
      '(fake platform)', () {
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

    test('ayah plays from the bulk-downloaded local file '
        '(Tunaiji 1:1)', () async {
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

      // v13.12: the ZIP is bulk-download only — seed the cache
      // with the explicit download the user starts himself, then
      // the ayah plays from the local file.
      expect(await downloads.downloadSurahs(12, [1]), isTrue);
      for (var i = 0; i < 200; i++) {
        if (!downloads.isDownloading) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(downloads.isDownloading, isFalse);
      expect(downloads.activeJob!.status, DownloadStatus.done);

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

    test('cache fails: ayah still plays via the per-ayah stream',
        () async {
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
      // v13.13: the stream tries SurahPedia FIRST now (the www
      // file is second) — the cache failed, so the SurahPedia
      // file is what plays.
      expect(fake.loadUris,
          ['https://resources.surahpedia.com/Husary/002033.mp3']);
      expect(fake.player.playing, isTrue);
    });
  });
}
