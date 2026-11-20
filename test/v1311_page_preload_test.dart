import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';
import 'fake_mp3.dart';

/// v13.11 — whole-page preload + fallback reorder (user orders,
/// 2026-11-18):
/// * v13.17 SUPERSEDES the preload (user order, 2026-11-19:
///   «خلي الكلمة والاية والصفحة خليها دغري يجيبها من النت»):
///   the page streams DIRECTLY from the internet — no preload,
///   no Dart download gate. The service-level [preloadAyahs]
///   and [cacheAyahFile] fallback-order tests below still pin
///   the download service itself; only the playPages group
///   changed to the new behaviour. The old rule (a page plays
///   ONLY after ALL its ayahs are downloaded) spun for 14+
///   minutes on the user's phone with no sound and no error.
/// * v13.14 — the preload is still attempted first, but it no
///   longer GATES playback: when it fails, the page falls through
///   to _playCurrent and streams ayah-by-ayah through the native
///   player (the user's phone fails every Dart download, so the
///   gate meant the page never played at all).
/// * [cacheAyahFile] tries the small files first: www per-ayah,
///   then bare per-ayah, and the whole-surah ZIP LAST (it was
///   second: a failed per-ayah file triggered a whole-surah ZIP
///   download that stalled the page for minutes before the error —
///   the user's "the page takes too long", page 151, 2026-11-18).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  final rifaiIndex = reciters.indexWhere((r) => r.name == 'هاني الرفاعي');

  late Directory tempDir;

  Future<AudioDownloadService> makeService(http.Client client) async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('audio-v1311-test');
    final s = AudioDownloadService(
      client: client,
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
    );
    await s.init();
    return s;
  }

  tearDown(() async {
    AudioDownloadService.fetchAttempts = 2;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('cacheAyahFile fallback order (v13.11)', () {
    test('www fails: bare per-ayah is tried next, ZIP never requested',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 500);
        }
        if (request.url.host == 'everyayah.com') {
          return http.Response.bytes(fakeMp3Bytes(fill: 7), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final rifai = reciters[rifaiIndex];

      final file = await service.cacheAyahFile(rifai, 2, 7);

      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 7));
      expect(requested.any((u) => u.contains('/zips/')), isFalse,
          reason: 'the ZIP must not run before the small bare file');
      expect(
          requested,
          containsAll([
            'http://www.everyayah.com/data/Hani_Rifai_64kbps/002007.mp3',
            'https://everyayah.com/data/Hani_Rifai_64kbps/002007.mp3',
          ]));
    });

    test('www fails: islamic.network serves the same Hani file next',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 500);
        }
        if (request.url.host == 'cdn.islamic.network') {
          // Global ayah 14 = 2:7 (7 ayahs in surah 1 + 7).
          expect(request.url.path, endsWith('/14.mp3'));
          return http.Response.bytes(fakeMp3Bytes(fill: 7), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final rifai = reciters[rifaiIndex];

      final file = await service.cacheAyahFile(rifai, 2, 7);

      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 7));
      expect(requested.any((u) => u.contains('/zips/')), isFalse,
          reason: 'the ZIP must not run before the other small files');
      expect(
          requested.any((u) =>
              u ==
              'https://everyayah.com/data/Hani_Rifai_64kbps/002007.mp3'),
          isFalse,
          reason: 'bare everyayah must not run either — islamic.network'
              ' already served the file');
    });

    test('reciters without a verified edition get null (v13.11)', () {
      final tunaiji = reciters[12];
      expect(tunaiji.name, 'خليفة الطنيجي');
      expect(islamicNetworkUrl(tunaiji, 7, 1), isNull);
      // Editions that exist but are surah-by-surah only (403
      // per-ayah, verified 2026-11-18) — never mapped.
      final tablawi = reciters.firstWhere(
          (r) => r.name == 'محمد الطبلاوي');
      expect(islamicNetworkUrl(tablawi, 7, 1), isNull);
      final dossari =
          reciters.firstWhere((r) => r.name == 'ياسر الدوسري');
      expect(islamicNetworkUrl(dossari, 7, 1), isNull);
      // المنشاوي: the edition is the WRONG recording (murattal
      // under a mujawwad name) — never mapped.
      final minshawi = reciters.firstWhere(
          (r) => r.name == 'محمد صديق المنشاوي');
      expect(islamicNetworkUrl(minshawi, 7, 1), isNull);
      expect(globalAyahNumber(7, 1), 955);
      expect(globalAyahNumber(2, 255), 262);
      expect(islamicNetworkUrl(reciters[rifaiIndex], 7, 1),
          'https://cdn.islamic.network/quran/audio/64/ar.hanirifai/955.mp3');
      // Akhdar's files live on the 32 kbps path (64 403s).
      final akhdar = reciters.firstWhere(
          (r) => r.name == 'إبراهيم الأخضر');
      expect(islamicNetworkUrl(akhdar, 7, 1),
          'https://cdn.islamic.network/quran/audio/32/ar.ibrahimakhbar/955.mp3');
      // العجمي (16th reciter, v13.11): 64 kbps edition.
      expect(reciters.length, 16);
      final ajmi = reciters.firstWhere(
          (r) => r.name == 'أحمد بن علي العجمي');
      expect(islamicNetworkUrl(ajmi, 7, 1),
          'https://cdn.islamic.network/quran/audio/64/ar.ahmedajamy/955.mp3');
      // Group B (verified 2026-11-18, same standard): الحذيفي،
      // الشاطري، سويد، الشريم، السديس.
      final hudhaify = reciters.firstWhere(
          (r) => r.name == 'علي الحذيفي');
      expect(islamicNetworkUrl(hudhaify, 7, 1),
          'https://cdn.islamic.network/quran/audio/64/ar.hudhaify/955.mp3');
      final shaatree = reciters.firstWhere(
          (r) => r.name == 'أبو بكر الشاطري');
      expect(islamicNetworkUrl(shaatree, 7, 1),
          'https://cdn.islamic.network/quran/audio/64/ar.shaatree/955.mp3');
      final sowaid =
          reciters.firstWhere((r) => r.name == 'أيمن سويد');
      expect(islamicNetworkUrl(sowaid, 7, 1),
          'https://cdn.islamic.network/quran/audio/64/ar.aymanswoaid/955.mp3');
      final shuraym = reciters.firstWhere(
          (r) => r.name == 'سعود الشريم');
      expect(islamicNetworkUrl(shuraym, 7, 1),
          'https://cdn.islamic.network/quran/audio/64/ar.saoodshuraym/955.mp3');
      final sudais = reciters.firstWhere(
          (r) => r.name == 'عبد الرحمن السديس');
      expect(islamicNetworkUrl(sudais, 7, 1),
          'https://cdn.islamic.network/quran/audio/64/ar.abdurrahmaansudais/955.mp3');
    });
  });

  group('playPages direct stream (v13.17)', () {
    test('page 3: the first ayah streams at once, no preload', () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        // One small per-ayah file per ayah, distinct bytes each.
        final name = request.url.pathSegments.last;
        final ayah = int.parse(name.substring(3, 6));
        return http.Response.bytes(fakeMp3Bytes(fill: ayah), 200);
      }));
      addTearDown(service.dispose);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = rifaiIndex;
      final pageAyahs = ayahsOfPages(3, 3);
      expect(pageAyahs.length, 11, reason: 'Baqarah 6–16');

      final loadsBefore = fake.loadCount;
      await controller.playPages(3, 3);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(controller.currentAyah, (2, 6));
      // v13.17: NO preload — the first ayah streams from
      // SurahPedia at once, through the native player.
      expect(fake.loadCount, loadsBefore + 1);
      expect(fake.loadUris.last,
          'https://resources.surahpedia.com/Hani_Rifai/002006.mp3');
      // ...and no foreground Dart download ran for it.
      expect(requested.any((u) => u.contains('002006')), isFalse);
      // The background prefetch still warms the NEXT ayah while
      // the page plays (its request appears after the play
      // started, and only for 2:7 — never for the played ayah).
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requested.any((u) => u.contains('002007')), isTrue);
      expect(service.localAyahFile(reciters[rifaiIndex], 2, 7),
          isNotNull);
      expect(service.localAyahFile(reciters[rifaiIndex], 2, 6), isNull,
          reason: 'the played ayah streamed, it did not download');
    });

    test('every host fails: the page still plays via the native '
        'stream (v13.17)', () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 500);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = rifaiIndex;

      final loadsBefore = fake.loadCount;
      await controller.playPages(3, 3);

      // v13.17: no preload at all — the page streams the first
      // ayah through the native player at once (every Dart
      // download failed, so nothing is cached).
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadCount, loadsBefore + 1);
      expect(fake.loadUris.last,
          'https://resources.surahpedia.com/Hani_Rifai/002006.mp3');
      // v13.22 supersedes the v13.17 "no ZIP" part: page playback
      // DOES try the surah ZIP first (the download fails here —
      // www 500s, everything else 404s), then falls back to the
      // native stream, so the page still plays.
      expect(requested.any((u) => u.contains('002006')), isFalse);
      expect(requested.any((u) => u.contains('/zips/')), isTrue,
          reason: 'v13.22: the surah download is attempted first');
    });
  });
}
