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

/// v13.19 — MID-AYAH STALL WATCHDOG + FASTEST-HOST MEMORY +
/// PREFETCH THAT KEEPS UP.
///
/// v13.18 failed on the user's phone with «لسه في بطء بطء بطء»:
/// it advances from ayah to ayah, but there is still a delay
/// BETWEEN ayahs — the background prefetch is not keeping up
/// (his agreement, 2026-11-19 ~17:17: while ayah 1 plays, ayah 2
/// must ALREADY be fully ready in memory / cache, so the move is
/// instant — zero delay, not even 1%). Two gaps remain:
///
/// 1. MID-AYAH STALL (the v13.18 open question): a stream can
///    start (real buffered data, the load wait passes) and then
///    freeze mid-item — position AND bufferedPosition frozen
///    below the duration, no `completed` event — and the v13.18
///    completion watchdog only fires at the duration. The
///    playback then sits silent on one ayah forever. Fix: a
///    stall watchdog — neither value advancing for 30 s while
///    playing fails the item over to the NEXT host for the SAME
///    ayah (one pass through the remaining hosts only, then the
///    error is reported).
/// 2. ALL HOSTS SLOW: the 2 s per-host deadline, applied
///    sequentially, wastes 2 s x N before the last host even
///    starts. Fix: remember the host that delivered first
///    buffered data fastest (SharedPreferences, one key) and try
///    it FIRST on the next play — streams and prefetch downloads
///    alike — and prefetch the next TWO ayahs ahead (not one),
///    sequentially, starting the moment playback starts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  Future<(AudioDownloadService, Directory, List<String>)> buildService(
      http.Client Function(List<String> requested) clientFactory) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = await Directory.systemTemp.createTemp('v1319-stall');
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

  AudioPlayerController buildController(
      AudioDownloadService service, int reciterIndex) {
    final controller = AudioPlayerController(downloads: service);
    addTearDown(controller.dispose);
    controller.reciterIndex = reciterIndex;
    return controller;
  }

  group('mid-ayah stall watchdog (v13.19)', () {
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

    test('(a) a stream that plays then freezes mid-ayah fails '
        'over to the next host and the ayah restarts and plays',
        () async {
      // SurahPedia plays (first data at once) then freezes 1 s
      // in: position + buffered stop moving below the duration,
      // no `completed` ever arrives. The stall watchdog (shrunk
      // to 2 s) must fail over to www, restart the SAME ayah
      // there, and play it — not skip the ayah, not sit silent.
      // Only SurahPedia freezes: the failover host plays cleanly.
      fake.freezeAfterPlay = const Duration(seconds: 1);
      fake.freezeSubstrings.add('surahpedia');
      final (service, _, _) = await buildService(
          (requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = buildController(service, 0); // الحصري
      controller.stallWatchdogTimeout = const Duration(seconds: 2);

      final started = DateTime.now();
      await controller.playAyah(2, 1);

      // The failover happens in the background (watchdog timer),
      // after playAyah already returned — poll for it.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (fake.loadCount < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      final elapsed = DateTime.now().difference(started);

      // It waited for the freeze (1 s) + the stall window (2 s),
      // not the full 30 s, and not an instant fail-fast.
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 2)));
      expect(elapsed, lessThan(const Duration(seconds: 10)));
      expect(fake.loadCount, 2);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
      ]);
      // The SAME ayah restarted — it was not skipped.
      expect(controller.currentAyah, (2, 1));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('(b) a slow-but-progressing stream never triggers the '
        'stall watchdog', () async {
      // Buffered data arrives in 50 ms steps every 1.5 s — each
      // step moves the buffered position (and the position
      // extrapolates while ready), so the 2 s stall window never
      // expires, even though the item takes far longer than 2 s
      // to buffer. The watchdog must not fail over a stream that
      // is still moving.
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(milliseconds: 1500);
      fake.bufferedStep = const Duration(milliseconds: 50);
      final (service, _, _) = await buildService(
          (requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = buildController(service, 0); // الحصري
      controller.stallWatchdogTimeout = const Duration(seconds: 2);
      controller.positionStallTimeout = const Duration(seconds: 2);

      await controller.playAyah(2, 1);
      // ~6 s of trickling (several buffered steps in) — still
      // on the first host, no failover, no error.
      await Future<void>.delayed(const Duration(seconds: 6));

      expect(fake.loadCount, 1);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
      ]);
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('(c) the watchdog fires at most once per host: all '
        'hosts stalled → the error is reported, no infinite loop',
        () async {
      // EVERY host freezes 0.5 s into its play. The watchdog
      // must fail over through the whole chain (one pass only)
      // and then report the error — never loop forever, never
      // sit silent.
      fake.freezeAfterPlay = const Duration(milliseconds: 500);
      final (service, _, _) = await buildService(
          (requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = buildController(service, 0); // الحصري
      controller.stallWatchdogTimeout = const Duration(seconds: 2);

      await controller.playAyah(2, 1);

      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (controller.lastError == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      // Each host was tried exactly once — bounded, no loop.
      expect(fake.loadCount, 6);
      expect(controller.lastError, isNotNull);
      // The diagnostic names the mid-ayah stall (first failure
      // wins, so it is the first host's freeze).
      expect(controller.lastDiagnostic, contains('توقف'));
      expect(controller.lastDiagnostic, contains('mid-ayah'));
      // The ayah was never skipped.
      expect(controller.currentAyah, (2, 1));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('fastest-host memory (v13.19)', () {
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

    test('(d) after a play where the second host was fastest, '
        'the next play tries it first', () async {
      // SurahPedia first data at 20 s (abandoned at the 2 s
      // switch), www first data at 1 s → plays from www. The
      // controller remembers www as the fastest host.
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(seconds: 20);
      fake.firstDataDelayBySubstring['everyayah.com'] =
          const Duration(seconds: 1);
      final (service, _, _) = await buildService(
          (requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = buildController(service, 0); // الحصري

      await controller.playAyah(2, 1);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
      ]);
      expect(controller.lastError, isNull);

      // The memory is in place at once (in-memory) and persisted
      // for the next launch (the key name must match the
      // controller's _fastestHostKey).
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fastest_audio_host'), 'www.everyayah.com');

      // A second play (a different ayah) tries www FIRST — no
      // SurahPedia attempt at all.
      fake.resetCounts();
      await controller.playAyah(2, 2);
      expect(fake.loadUris, [
        'http://www.everyayah.com/data/Husary_64kbps/002002.mp3',
      ]);
      expect(controller.lastError, isNull);

      // And a FRESH controller restores the memory from prefs
      // (the service field is cleared first, so only the restore
      // can put www back in front).
      service.fastestHost = null;
      final controller2 = buildController(service, 0);
      await controller2.restorePlaybackSettings();
      fake.resetCounts();
      await controller2.playAyah(2, 3);
      expect(fake.loadUris, [
        'http://www.everyayah.com/data/Husary_64kbps/002003.mp3',
      ]);
      expect(controller2.lastError, isNull);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('(e) a remembered host that goes slow is abandoned at '
        '2 s and the chain continues', () async {
      // Establish the memory (www fast) as in (d).
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(seconds: 20);
      fake.firstDataDelayBySubstring['everyayah.com'] =
          const Duration(seconds: 1);
      final (service, _, _) = await buildService(
          (requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = buildController(service, 0); // الحصري
      await controller.playAyah(2, 1);
      expect(controller.lastError, isNull);

      // Now www goes slow (first data 20 s) and every middle
      // host fails its load at once — but the LAST host (bare)
      // is fast, so the chain reaches it.
      fake.firstDataDelayBySubstring.clear();
      fake.firstDataDelayBySubstring['www.everyayah'] =
          const Duration(seconds: 20);
      fake.failLoadSubstrings.addAll([
        'surahpedia',
        'islamic.network',
        'mirrors.quranicaudio',
        'huggingface',
      ]);
      fake.resetCounts();

      final started = DateTime.now();
      await controller.playAyah(2, 2);
      final elapsed = DateTime.now().difference(started);

      // www (remembered) was tried FIRST and abandoned at ~2 s;
      // the chain continued and the bare host played.
      expect(fake.loadUris.first,
          'http://www.everyayah.com/data/Husary_64kbps/002002.mp3');
      expect(fake.loadUris.last,
          'https://everyayah.com/data/Husary_64kbps/002002.mp3');
      expect(fake.loadCount, 6);
      expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
      expect(elapsed, lessThan(const Duration(seconds: 8)));
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('prefetch that keeps up (v13.19)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.movePositionAfter = Duration.zero;
      fake.firstDataDelayBySubstring.clear();
      fake.neverBufferSubstrings.clear();
      fake.bufferedStep = Duration.zero;
      fake.fakeDuration = const Duration(seconds: 15);
      fake.freezeAfterPlay = Duration.zero;
      fake.freezeSubstrings.clear();
      fake.resetCounts();
    });

    /// A download mock whose first chunk arrives slowly from
    /// SurahPedia (20 s) and fast from everyayah.com (1 s),
    /// then streams ~10 KB/s — the user's network, modelled.
    MockClient downloadClient(
        List<String> requested, List<int> bytes) {
      return MockClient.streaming((request, _) async {
        requested.add(request.url.toString());
        final url = request.url.toString();
        Stream<List<int>> chunks() async* {
          await Future<void>.delayed(url.contains('surahpedia')
              ? const Duration(seconds: 20)
              : const Duration(seconds: 1));
          const chunk = 1024;
          for (var i = 0; i < bytes.length; i += chunk) {
            yield bytes.sublist(i, math.min(i + chunk, bytes.length));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        return http.StreamedResponse(chunks(), 200,
            contentLength: bytes.length);
      });
    }

    test('(f) with a slow first host and a fast second host, '
        'the prefetch of the next ayah uses the fast host and '
        'finishes inside a 15 s ayah — the transition is instant',
        () async {
      // Ayah 1 streams: SurahPedia first data at 20 s
      // (abandoned at the 2 s switch), www first data at 1 s →
      // plays from www at ~3 s and remembers it. The prefetch
      // of ayah 2 must then try www FIRST — not SurahPedia's
      // 20 s first byte — and finish well inside the 15 s ayah.
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(seconds: 20);
      fake.firstDataDelayBySubstring['everyayah.com'] =
          const Duration(seconds: 1);
      final bytes = fakeMp3Bytes(size: 20480, fill: 7);
      final (service, tempDir, requested) =
          await buildService((r) => downloadClient(r, bytes));
      final controller = buildController(service, 0); // الحصري
      controller.advanceWatchdogGrace = const Duration(seconds: 2);

      final started = DateTime.now();
      await controller.playPages(2, 2);
      final nextFile = ayahFile(tempDir, 2, 2);

      // Poll until the prefetched file is complete — and prove
      // it happened BEFORE the current ayah ended.
      final cacheDeadline =
          DateTime.now().add(const Duration(seconds: 12));
      while (!nextFile.existsSync() &&
          DateTime.now().isBefore(cacheDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(nextFile.existsSync(), isTrue,
          reason: 'the next ayah was prefetched inside the ayah');
      expect(await nextFile.readAsBytes(), bytes);
      expect(controller.currentAyah, (2, 1),
          reason: 'cached before the current ayah ended');

      // The prefetch used the fast host — no SurahPedia request
      // for ayah 2 at all.
      final ayah2Requests =
          requested.where((u) => u.contains('002002')).toList();
      expect(ayah2Requests, isNotEmpty);
      expect(ayah2Requests.first, contains('www.everyayah'));
      expect(
          ayah2Requests.any((u) => u.contains('surahpedia')), isFalse);

      // Now let the watchdog advance the queue and prove the
      // transition is instant: ayah 2 loads from the local file,
      // with zero stream delay (no http load for it at all).
      final advanceDeadline =
          DateTime.now().add(const Duration(seconds: 25));
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
      expect(
          fake.loadUris.any((u) =>
              u.endsWith('002002.mp3') && u.startsWith('http')),
          isFalse,
          reason: 'no stream delay on the transition');
      expect(DateTime.now().difference(started),
          lessThan(const Duration(seconds: 30)));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('(g) prefetch depth: while ayah 1 plays, ayahs 2 AND 3 '
        'are both downloaded in the background', () async {
      fake.firstDataDelayBySubstring['surahpedia'] =
          const Duration(seconds: 20);
      fake.firstDataDelayBySubstring['everyayah.com'] =
          const Duration(seconds: 1);
      final bytes = fakeMp3Bytes(size: 20480, fill: 7);
      final (service, tempDir, requested) =
          await buildService((r) => downloadClient(r, bytes));
      final controller = buildController(service, 0); // الحصري
      controller.advanceWatchdogGrace = const Duration(seconds: 2);

      await controller.playPages(2, 2);
      final file2 = ayahFile(tempDir, 2, 2);
      final file3 = ayahFile(tempDir, 2, 3);

      // Poll until BOTH files are complete — and prove both
      // were ready before the current ayah ended.
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      while ((!file2.existsSync() || !file3.existsSync()) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(file2.existsSync(), isTrue, reason: 'ayah 2 prefetched');
      expect(file3.existsSync(), isTrue, reason: 'ayah 3 prefetched');
      expect(await file2.readAsBytes(), bytes);
      expect(await file3.readAsBytes(), bytes);
      expect(controller.currentAyah, (2, 1),
          reason: 'both cached before the current ayah ended');
      expect(requested.any((u) => u.contains('002002')), isTrue);
      expect(requested.any((u) => u.contains('002003')), isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('orderUrlsFastestFirst (v13.19)', () {
    test('moves the remembered host first, keeps the rest in '
        'order', () {
      expect(
        orderUrlsFastestFirst([
          'https://resources.surahpedia.com/Husary/002001.mp3',
          'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
          'https://cdn.islamic.network/quran/audio/64/ar.husary/1.mp3',
          'https://everyayah.com/data/Husary_64kbps/002001.mp3',
        ], 'www.everyayah.com'),
        [
          'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
          'https://resources.surahpedia.com/Husary/002001.mp3',
          'https://cdn.islamic.network/quran/audio/64/ar.husary/1.mp3',
          'https://everyayah.com/data/Husary_64kbps/002001.mp3',
        ],
      );
    });

    test('null / unknown / already-first host leaves the order '
        'unchanged', () {
      const urls = [
        'https://resources.surahpedia.com/Husary/002001.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
      ];
      expect(orderUrlsFastestFirst(urls, null), urls);
      expect(orderUrlsFastestFirst(urls, 'unknown.example.com'), urls);
      expect(
          orderUrlsFastestFirst(urls, 'resources.surahpedia.com'), urls);
    });

    test('the remembered host is only an ordering hint: the '
        '2 s deadline still applies to it', () {
      // Moving www first does not change its deadline — a slow
      // www is still abandoned at the switch (pinned by test
      // (e) above, which plays the chain end to end).
      expect(
        orderUrlsFastestFirst([
          'https://resources.surahpedia.com/Husary/002001.mp3',
          'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
        ], 'www.everyayah.com'),
        [
          'http://www.everyayah.com/data/Husary_64kbps/002001.mp3',
          'https://resources.surahpedia.com/Husary/002001.mp3',
        ],
      );
    });
  });

  group('watchdog defaults (v13.19)', () {
    test('2 s first-data switch, 30 s stall, 5 s watchdog '
        'grace, 30 s mid-ayah stall window', () async {
      final (service, _, _) = await buildService(
          (requested) => MockClient((request) async {
                requested.add(request.url.toString());
                return http.Response.bytes([], 404);
              }));
      final controller = buildController(service, 0);

      expect(controller.firstDataTimeout, const Duration(seconds: 2));
      expect(controller.positionStallTimeout,
          const Duration(seconds: 30));
      expect(controller.advanceWatchdogGrace, const Duration(seconds: 5));
      expect(controller.stallWatchdogTimeout,
          const Duration(seconds: 30));
    });
  });
}
