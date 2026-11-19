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

/// v13.17 — DIRECT STREAM (the user's order, 2026-11-19:
/// «خلي الكلمة والاية والصفحة خليها دغري يجيبها من النت»).
///
/// v13.16 FAILED on page 128 (Tunaiji): the whole-page preload
/// spun for 14+ minutes with no sound and no error, because the
/// Dart downloads crawl on the user's phone. The download-first
/// gate is gone for the word / ayah / page scopes: they stream
/// DIRECTLY from the internet through the native player, and the
/// local file is used ONLY when it is already on disk and valid
/// (v13.16 validation still deletes an invalid file on the spot).
/// The surah scope is the exception — it still downloads first
/// (the user's order: «خلي الصورة اذا بدنا نحملها»).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  Future<(AudioDownloadService, Directory, List<String>)> buildService(
      http.Client Function(List<String> requested) clientFactory) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('v1317-stream');
    addTearDown(() => tempDir.delete(recursive: true));
    final requested = <String>[];
    final service = AudioDownloadService(
      client: clientFactory(requested),
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
    );
    await service.init();
    addTearDown(service.dispose);
    return (service, tempDir, requested);
  }

  File ayahFile(Directory tempDir, int surah, int ayah) => File(
      '${tempDir.path}/${reciters[0].everyayah}/'
      '${ayahFileName(surah, ayah)}.mp3');

  Future<void> seedFile(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  group('page / ayah / word stream directly (v13.17)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.movePositionAfter = Duration.zero;
      fake.resetCounts();
    });

    test('page scope with an EMPTY cache streams the first ayah '
        'at once — zero foreground downloads (Husary page 2)',
        () async {
      final (service, tempDir, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      await controller.playPages(2, 2);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(controller.currentAyah, (2, 1));
      // The first ayah streamed from SurahPedia — the native
      // player's setUrl, not a Dart download.
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
      ]);
      // The played ayah was NEVER Dart-downloaded in the
      // foreground: no request for its file at all.
      expect(requested.any((u) => u.contains('002001')), isFalse);
      // And nothing was cached for it — it streamed, it did not
      // download.
      expect(service.localAyahFile(reciters[0], 2, 1), isNull);
      // The background prefetch still warms the NEXT ayah while
      // the page plays (its request appears after the play
      // started, and only for 2:2 — never for the played ayah).
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requested.any((u) => u.contains('002002')), isTrue);
      expect(tempDir.existsSync(), isTrue);
    });

    test('ayah scope with an EMPTY cache: zero Dart requests, '
        'streams at once', () async {
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      await controller.playAyah(2, 33);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002033.mp3',
      ]);
      // No prefetch exists for a one-ayah queue, so the request
      // log is the whole foreground story: nothing downloaded.
      expect(requested, isEmpty);
    });

    test('word scope with an EMPTY cache: the wbw file streams '
        'directly, no Dart download', () async {
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);

      await controller.playWord(2, 33, 1);

      expect(controller.lastError, isNull);
      expect(controller.wordUsesWbw, isTrue);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Word_by-Word/2/002033001.mp3',
      ]);
      expect(requested, isEmpty);
    });

    test('a valid cached ayah still plays from disk, zero stream '
        'requests', () async {
      final (service, tempDir, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes(fakeMp3Bytes(), 200);
              }));
      final seeded = fakeMp3Bytes(fill: 7);
      await seedFile(ayahFile(tempDir, 2, 1), seeded);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      await controller.playAyah(2, 1);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      // The player loaded the LOCAL file, not a stream URL.
      expect(fake.loadCount, 1);
      expect(fake.loadUris.last.endsWith('002001.mp3'), isTrue);
      expect(fake.loadUris.last.startsWith('http'), isFalse);
      expect(requested, isEmpty,
          reason: 'no download and no stream: the file was on disk');
      expect(await ayahFile(tempDir, 2, 1).readAsBytes(), seeded);
    });

    test('a valid cached first ayah plays from disk on the page '
        'scope too', () async {
      final (service, tempDir, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes(fakeMp3Bytes(), 200);
              }));
      await seedFile(ayahFile(tempDir, 2, 1), fakeMp3Bytes(fill: 7));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      await controller.playPages(2, 2);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris.last.endsWith('002001.mp3'), isTrue);
      expect(fake.loadUris.last.startsWith('http'), isFalse);
      expect(requested.any((u) => u.contains('002001')), isFalse);
      // Let the next-ayah prefetch settle before teardown deletes
      // the temp dir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('surah scope UNCHANGED: still downloads first and plays '
        'the local file', () async {
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes(fakeMp3Bytes(fill: 1), 200);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      await controller.playSurah(2);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      // The foreground Dart download DID happen for the surah
      // scope — SurahPedia served the file first.
      expect(requested, contains(
          'https://resources.surahpedia.com/Husary/002001.mp3'));
      // ...and the player loaded the LOCAL file, not a stream.
      expect(fake.loadUris.last.endsWith('002001.mp3'), isTrue);
      expect(fake.loadUris.last.startsWith('http'), isFalse);
      expect(service.localAyahFile(reciters[0], 2, 1), isNotNull);
      // Let the next-ayah prefetch settle before teardown deletes
      // the temp dir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('an invalid cached file is deleted and the ayah streams '
        '(v13.16 validation still enforced on the instant check)',
        () async {
      final (service, tempDir, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final poisoned = ayahFile(tempDir, 2, 1);
      await seedFile(poisoned, []);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      await controller.playAyah(2, 1);

      // The 0-byte file is gone — the instant check deleted it
      // instead of trusting it — and the ayah streamed.
      expect(await poisoned.exists(), isFalse);
      expect(service.localAyahFile(reciters[0], 2, 1), isNull);
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
      ]);
      expect(requested, isEmpty);
    });
    test('a slow stream still plays — the position first moves '
        'after 15 s (weakest net: past the old 6 s limit, inside '
        'the new 30 s window)', () async {
      // The fake stream is slow-but-progressing: nothing moves
      // for 15 s, then the position advances. Under the old 6 s
      // position wait this failed over to the next host and
      // reported an error; under the 30 s stall window it plays.
      fake.movePositionAfter = const Duration(seconds: 15);
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 12; // خليفة الطنيجي

      final started = DateTime.now();
      await controller.playAyah(2, 255);
      final elapsed = DateTime.now().difference(started);

      // It really did wait for the slow stream (not fail fast).
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 15)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      // No failover: the first host (SurahPedia) was never
      // abandoned for the next host in the chain.
      expect(fake.loadCount, 1);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Khalefa_Al-Tunaiji/002255.mp3',
      ]);
      expect(requested, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
