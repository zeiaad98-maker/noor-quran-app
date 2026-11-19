import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';
import 'fake_mp3.dart';

/// v13.18 — SILENT PLAYING (v13.17 failed on the user's phone,
/// page 257, Tunaiji: the sheet showed PAUSE — playing state —
/// with no sound and the highlight stuck on ayah 11).
///
/// Root cause, proven reading just_audio 0.9.46: `position` is
/// EXTRAPOLATED from wall-clock time while `playing && ready`,
/// and `positionStream` emits those extrapolated values on a
/// timer — so the old position-only `_waitForPositionBeyond`
/// passed with ZERO audio data actually decoded: `_loadAndPlay`
/// returned true while ExoPlayer had buffered nothing. No sound,
/// no completion, no error, failover never ran.
///
/// Fix 1: the wait now requires REAL `bufferedPosition` movement
/// (fed straight from the platform's playback events, never
/// extrapolated). Fix 2: a completion watchdog advances the
/// playback when an item reaches its duration but the platform
/// never emits `completed`. Fix 3 (slow-host switch): a host with
/// no buffered data at all within ~2 s is abandoned at once for
/// the next host — the user's phone waited the full 30 s stall
/// window on SurahPedia for EVERY ayah (~30 s pause between
/// ayahs); the last host keeps the full 30 s backstop. HARD
/// REQUIREMENT (his words, 2026-11-19: «لازم ثانية او ثانيتين
/// يكون جاهز — يا ثانية يا ثانيتين»): first audio within 1–2 s
/// per ayah; the background prefetch must keep the next ayah
/// cached so ayahs 2..N start instantly from disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  Future<(AudioDownloadService, Directory, List<String>)> buildService(
      http.Client Function(List<String> requested) clientFactory) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('v1318-silent');
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

  group('silent playing is detected, not faked (v13.18)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.movePositionAfter = Duration.zero;
      fake.firstDataDelayBySubstring.clear();
      fake.neverBufferSubstrings.clear();
      fake.bufferedStep = Duration.zero;
      fake.fakeDuration = const Duration(seconds: 60);
      fake.resetCounts();
    });

    test('a stream whose position extrapolates but whose '
        'bufferedPosition NEVER moves is a stall: the host is '
        'abandoned and the next host plays', () async {
      // SurahPedia (first host) never buffers: just_audio still
      // reports `playing` and extrapolates the position on its
      // own — the old code accepted that as a play. The new code
      // must detect the silence, abandon the host at the
      // first-data deadline, and play from the next host.
      fake.neverBufferSubstrings.add('surahpedia');
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      // Shrink the slow-host window so the test runs fast (the
      // production default is 8 s).
      controller.firstDataTimeout = const Duration(seconds: 1);

      final started = DateTime.now();
      await controller.playAyah(2, 1);
      final elapsed = DateTime.now().difference(started);

      // It really waited the switch window (not fail-fast) and
      // did NOT burn the full 30 s stall window on the silent
      // host.
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(elapsed, lessThan(const Duration(seconds: 8)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      // Failover happened: the silent host was tried AND
      // abandoned, the next host played.
      expect(fake.loadCount, 2);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
      ]);
      expect(requested, isEmpty);
    });

    test('a stream whose bufferedPosition advances (however '
        'slowly) plays with no failover', () async {
      // First data arrives after 1 s — inside the 2 s slow-host
      // window — so the host is kept and the ayah plays from it.
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(seconds: 1);
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      final started = DateTime.now();
      await controller.playAyah(2, 1);
      final elapsed = DateTime.now().difference(started);

      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadCount, 1);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
      ]);
      expect(requested, isEmpty);
    });

    test('a trickling stream never fails for being slow: small '
        'buffered advances re-arm the stall window', () async {
      // The stall window is shrunk to 2 s for the test. Buffered
      // data arrives in 50 ms steps every 1.5 s — each step
      // re-arms the window — and passes the 100 ms target only on
      // the third step (~4.5 s). Without re-arming, the 2 s stall
      // timer would have failed it at 2 s and failed over.
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(milliseconds: 1500);
      fake.bufferedStep = const Duration(milliseconds: 50);
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      controller.positionStallTimeout = const Duration(seconds: 2);

      final started = DateTime.now();
      await controller.playAyah(2, 1);
      final elapsed = DateTime.now().difference(started);

      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 4)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadCount, 1);
      expect(requested, isEmpty);
    });

    test('a local file still plays at once (fully buffered at '
        'load)', () async {
      final (service, tempDir, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes(fakeMp3Bytes(), 200);
              }));
      await seedFile(ayahFile(tempDir, 2, 1), fakeMp3Bytes(fill: 7));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      final started = DateTime.now();
      await controller.playAyah(2, 1);
      final elapsed = DateTime.now().difference(started);

      // No waiting for data: the file was fully buffered the
      // moment it loaded.
      expect(elapsed, lessThan(const Duration(seconds: 2)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadCount, 1);
      expect(fake.loadUris.last.endsWith('002001.mp3'), isTrue);
      expect(fake.loadUris.last.startsWith('http'), isFalse);
      expect(requested, isEmpty);
    });

    test('slow-host switch: a host with first data after 20 s is '
        'abandoned after ~2 s for the next host (first data in '
        '2 s) — audio within ~5 s total', () async {
      // The user's phone waited ~30 s per ayah on SurahPedia.
      // Now the silent host is abandoned at the 2 s switch and
      // the next host plays: ~4 s total instead of ~30 s+.
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(seconds: 20);
      fake.firstDataDelayBySubstring['everyayah.com'] =
          const Duration(seconds: 2);
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      final started = DateTime.now();
      await controller.playAyah(2, 1);
      final elapsed = DateTime.now().difference(started);

      // It waited the ~2 s switch window, then the fast host's
      // ~2 s — well under the old ~30 s per ayah.
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 3)));
      expect(elapsed, lessThan(const Duration(seconds: 8)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadCount, 2);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
      ]);
      expect(requested, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('completion watchdog: a streamed ayah that plays to its '
        'duration without ever emitting completed still advances '
        'to the next ayah', () async {
      // autoFinish is off, so the fake NEVER emits `completed` —
      // the only way the playback advances is the watchdog: the
      // position reaches the (short, 3 s) duration, the 2 s grace
      // runs out, and _onItemFinished advances the queue.
      fake.fakeDuration = const Duration(seconds: 3);
      final (service, _, _) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      // Shrink the grace so the test runs fast (the production
      // default is 5 s).
      controller.advanceWatchdogGrace = const Duration(seconds: 2);

      final started = DateTime.now();
      await controller.playPages(2, 2);

      // Poll until the watchdog advances the queue (or time out).
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (controller.currentAyah != (2, 2) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final elapsed = DateTime.now().difference(started);

      // It took the watchdog's time (~3 s to reach the duration
      // + 2 s grace), not an instant `completed`.
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 4)));
      expect(controller.currentAyah, (2, 2));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      // `requested` is NOT asserted empty here: playPages
      // prefetches the NEXT ayah in the background (cacheAyahFile
      // → the mock, 404), so it legitimately holds the 002002
      // and 002003 URLs. The prefetch never affects playback.
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('last-host backstop: a slow LAST host still plays — '
        'first data after 5 s, inside the 30 s stall window', () async {
      // Every earlier host fails to load, so the chain reaches
      // the last host (bare everyayah). It gets NO slow-host
      // switch — only the full 30 s stall window — so its first
      // data after 5 s still plays: the weakest-net backstop.
      // A 5 s first-data arrival on a NON-last host would be
      // abandoned at 2 s (see the slow-host switch test).
      fake.failLoadSubstrings.addAll([
        'surahpedia',
        'www.everyayah',
        'islamic.network',
        'mirrors.quranicaudio',
        'huggingface',
      ]);
      fake.firstDataDelayBySubstring['everyayah.com'] =
          const Duration(seconds: 5);
      final (service, _, requested) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      final started = DateTime.now();
      await controller.playAyah(2, 1);
      final elapsed = DateTime.now().difference(started);

      // It really waited for the slow last host (not fail-fast),
      // and it played: the 30 s backstop, not the 2 s switch.
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 5)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadCount, 6);
      expect(fake.loadUris.last,
          'https://everyayah.com/data/Husary_64kbps/002001.mp3');
      expect(requested, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('prefetch keeps one ayah ahead: a slow (~10 KB/s) '
        'download of the next ayah finishes before the current '
        'ayah ends, and the next ayah plays from disk', () async {
      // Ayah 1 streams (fake, instant) while the background
      // prefetch downloads ayah 2 at ~10 KB/s — a 20 KB file
      // takes ~2 s. The current ayah is 3 s long and the
      // watchdog advances it ~2 s after its end (~5 s total),
      // so the next ayah is cached well before the current one
      // ends — and plays from the local file with zero stream
      // delay.
      fake.fakeDuration = const Duration(seconds: 3);
      final slowBytes = fakeMp3Bytes(size: 20480, fill: 7);
      final (service, tempDir, requested) =
          await buildService((requested) => MockClient.streaming(
                (request, _) async {
                  requested.add(request.url.toString());
                  Stream<List<int>> chunks() async* {
                    const chunk = 1024;
                    for (var i = 0; i < slowBytes.length; i += chunk) {
                      yield slowBytes.sublist(
                          i, math.min(i + chunk, slowBytes.length));
                      await Future<void>.delayed(
                          const Duration(milliseconds: 100));
                    }
                  }
                  return http.StreamedResponse(chunks(), 200,
                      contentLength: slowBytes.length);
                },
              ));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      controller.advanceWatchdogGrace = const Duration(seconds: 2);

      await controller.playPages(2, 2);
      final nextFile = ayahFile(tempDir, 2, 2);

      // Poll until the prefetched file is complete (the download
      // renames atomically, so existsSync() means the whole file
      // is there) — and prove it happened BEFORE the current
      // ayah ended.
      final cacheDeadline =
          DateTime.now().add(const Duration(seconds: 10));
      while (!nextFile.existsSync() &&
          DateTime.now().isBefore(cacheDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(nextFile.existsSync(), isTrue,
          reason: 'the next ayah was prefetched');
      expect(await nextFile.readAsBytes(), slowBytes);
      expect(controller.currentAyah, (2, 1),
          reason: 'cached before the current ayah ended');

      // Now let the watchdog advance the queue and prove the
      // next ayah plays from the local file, not the stream.
      final advanceDeadline =
          DateTime.now().add(const Duration(seconds: 10));
      while (controller.currentAyah != (2, 2) &&
          DateTime.now().isBefore(advanceDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(controller.currentAyah, (2, 2));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(
          fake.loadUris.any((u) =>
              u.endsWith('002002.mp3') && !u.startsWith('http')),
          isTrue,
          reason: 'ayah 2 loaded from the prefetched local file');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('watchdog defaults: 2 s first-data switch, 30 s stall, '
        '5 s watchdog grace', () async {
      final (service, _, _) =
          await buildService((requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);

      expect(controller.firstDataTimeout, const Duration(seconds: 2));
      expect(controller.positionStallTimeout,
          const Duration(seconds: 30));
      expect(controller.advanceWatchdogGrace, const Duration(seconds: 5));
    });
  });
}
