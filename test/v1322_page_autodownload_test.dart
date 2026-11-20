import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';
import 'fake_mp3.dart';
import 'zip_fixture.dart';

/// v13.22 — SURAHAPP-STYLE PAGE PLAYBACK.
///
/// The user ordered (2026-11-20, «نفس طريقة صورة»): tapping play
/// on a page downloads that page's surah FIRST, then plays it
/// locally — exactly like SurahApp. Streaming failed on his phone
/// for four versions (v13.16–v13.19: still slow BETWEEN ayahs),
/// while he measured a SurahApp surah download at 3–5 s on his
/// slow internet. This supersedes the v13.12/v13.17 order ("no
/// whole-surah ZIP in the playback path") FOR THE PAGE SCOPE ONLY:
/// the word and single-ayah scopes still stream directly, and
/// the surah scope was already download-first.
///
/// The contract, proved here with a fake native player
/// (fake_just_audio) and a MockClient (no real HTTP):
/// 1. A page whose surah is not downloaded triggers
///    [AudioDownloadService.downloadSurahs] for that surah, and
///    playback then reads the LOCAL files (file:// loads, no
///    stream at all).
/// 2. A surah already on disk triggers NO download at all — the
///    page plays locally at once.
/// 3. A failed download falls back to the existing streaming
///    path, so the page still plays.
/// 4. A page spanning two surahs downloads BOTH of them.
/// 5. When a download for the same surah is already running,
///    the play JOINS it — the surah ZIP is fetched exactly once,
///    never duplicated.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  Future<(AudioDownloadService, Directory, List<String>)> buildService(
      http.Client Function(List<String> requested) clientFactory) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('v1322-page-dl');
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

  AudioPlayerController buildController(
      AudioDownloadService service, int reciterIndex) {
    final controller = AudioPlayerController(downloads: service);
    addTearDown(controller.dispose);
    controller.reciterIndex = reciterIndex;
    return controller;
  }

  /// Real ZIP bytes for one surah: every ayah as a valid fake MP3
  /// (stored, like the real everyayah ZIPs).
  List<int> surahZipBytes(int surah) => buildSurahZip(
        {
          for (var a = 1; a <= quran.getVerseCount(surah); a++)
            '${ayahFileName(surah, a)}.mp3': fakeMp3Bytes(),
        },
        stored: true,
      );

  /// MockClient that serves surah ZIPs and per-ayah files.
  /// [zipDelay] holds each ZIP response back that long, so a
  /// download is still in flight when a second caller joins it.
  MockClient servingClient(List<String> requested, {Duration? zipDelay}) =>
      MockClient((request) async {
        requested.add(request.url.toString());
        final url = request.url.toString();
        if (url.contains('/zips/')) {
          if (zipDelay != null) {
            await Future<void>.delayed(zipDelay);
          }
          final name = request.url.pathSegments.last; // 'NNN.zip'
          final surah = int.parse(name.substring(0, 3));
          return http.Response.bytes(surahZipBytes(surah), 200);
        }
        if (url.endsWith('.mp3')) {
          return http.Response.bytes(fakeMp3Bytes(), 200);
        }
        return http.Response.bytes([], 404);
      });

  /// The page's own ayah files, seeded straight onto disk as valid
  /// MP3s (the way a previous download or prefetch would leave
  /// them) — the surah itself is NOT marked downloaded.
  Future<void> seedPageAyahs(Directory tempDir, int page) async {
    final dir = Directory('${tempDir.path}/${reciters[0].everyayah}');
    await dir.create(recursive: true);
    for (final ayah in ayahsOfPages(page, page)) {
      await File(
              '${dir.path}/${ayahFileName(ayah.$1, ayah.$2)}.mp3')
          .writeAsBytes(fakeMp3Bytes());
    }
  }

  /// Let the background prefetch settle before teardown deletes
  /// the temp dir (same habit as the v13.14–v13.19 tests).
  Future<void> settle() async =>
      await Future<void>.delayed(const Duration(milliseconds: 200));

  group('page playback auto-downloads its surah (v13.22)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.movePositionAfter = Duration.zero;
      fake.firstDataDelayBySubstring.clear();
      fake.neverBufferSubstrings.clear();
      fake.bufferedStep = Duration.zero;
      fake.fakeDuration = const Duration(seconds: 60);
      fake.freezeAfterPlay = Duration.zero;
      fake.freezeSubstrings.clear();
      fake.resetCounts();
    });

    test('(1) page 604: surah not downloaded → the surahs '
        'download, then playback reads local files', () async {
      final (service, _, requested) =
          await buildService((r) => servingClient(r));
      final controller = buildController(service, 0); // الحصري

      await controller.playPages(604, 604);

      // The three surahs of page 604 were downloaded first.
      final zipUrls =
          requested.where((u) => u.endsWith('.zip')).toSet();
      expect(zipUrls, {
        everyayahSurahZipUrl(reciters[0], 112),
        everyayahSurahZipUrl(reciters[0], 113),
        everyayahSurahZipUrl(reciters[0], 114),
      });
      expect(service.isSurahDownloaded(0, 112), isTrue);
      expect(service.isSurahDownloaded(0, 113), isTrue);
      expect(service.isSurahDownloaded(0, 114), isTrue);
      // And the page played from disk — no stream at all.
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris, isNotEmpty);
      expect(fake.loadUris.first, startsWith('file://'));
      expect(fake.loadUris.any((u) => u.startsWith('http')), isFalse);
      await settle();
    });

    test('(2) surah already on disk → no download call, the page '
        'plays locally at once', () async {
      final (service, tempDir, requested) =
          await buildService((r) => servingClient(r));
      await seedPageAyahs(tempDir, 604);
      final controller = buildController(service, 0); // الحصري

      await controller.playPages(604, 604);

      // Nothing was fetched at all — no ZIP, no per-ayah file.
      expect(requested, isEmpty);
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris.first, startsWith('file://'));
      expect(fake.loadUris.any((u) => u.startsWith('http')), isFalse);
      await settle();
    });

    test('(3) download fails → the page still plays via the '
        'streaming fallback', () async {
      final (service, _, requested) = await buildService(
          (r) => MockClient((request) async {
                r.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = buildController(service, 0); // الحصري

      await controller.playPages(604, 604);

      // The surah download WAS attempted first (v13.22), then
      // failed — and the page still played.
      expect(requested.any((u) => u.contains('/zips/')), isTrue);
      expect(service.activeJob?.status, DownloadStatus.failed);
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris.first,
          'https://resources.surahpedia.com/Husary/112001.mp3');
      await settle();
    });

    test('(4) page 440 spans two surahs → BOTH are downloaded',
        () async {
      // Page 440: surahs 35 + 36 (verified by the scratch check).
      expect(
          ayahsOfPages(440, 440).map((a) => a.$1).toSet(), {35, 36});
      final (service, _, requested) =
          await buildService((r) => servingClient(r));
      final controller = buildController(service, 0); // الحصري

      await controller.playPages(440, 440);

      final zipUrls =
          requested.where((u) => u.endsWith('.zip')).toSet();
      expect(zipUrls, {
        everyayahSurahZipUrl(reciters[0], 35),
        everyayahSurahZipUrl(reciters[0], 36),
      });
      expect(service.isSurahDownloaded(0, 35), isTrue);
      expect(service.isSurahDownloaded(0, 36), isTrue);
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris.first, startsWith('file://'));
      await settle();
    });

    test('(5) a download already running for the same surahs is '
        'joined, never duplicated', () async {
      final (service, _, requested) = await buildService(
          (r) => servingClient(r, zipDelay: const Duration(
            milliseconds: 800,
          )));
      final controller = buildController(service, 0); // الحصري

      // A manual «تحميل التلاوات» download of the page's surahs
      // starts first (the ZIPs are held back 800 ms each, so the
      // job is still running when playPages runs).
      expect(await service.downloadSurahs(0, [112, 113, 114]), isTrue);
      expect(service.isDownloading, isTrue);

      await controller.playPages(604, 604);

      // Each surah ZIP was fetched exactly ONCE — the play joined
      // the running job instead of starting its own.
      final zipUrls = requested.where((u) => u.endsWith('.zip'));
      expect(zipUrls.length, 3);
      expect(zipUrls.toSet(), {
        everyayahSurahZipUrl(reciters[0], 112),
        everyayahSurahZipUrl(reciters[0], 113),
        everyayahSurahZipUrl(reciters[0], 114),
      });
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris.first, startsWith('file://'));
      await settle();
    });
  });
}
