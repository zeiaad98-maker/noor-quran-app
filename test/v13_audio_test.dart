import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/widgets/noor_qcf_page.dart';

/// v13 audio (the user's top priority): pronunciation must be clear,
/// pure and complete — for the WORD and the AYAH.
///
/// * Segments: Quran.com returns STRING numbers for some recitations
///   (Sudais, verified live 2026-11-17) — the parser must coerce them
///   instead of throwing and silently falling back to the wbw voice.
/// * Word window: the last word of an ayah gets a longer end padding
///   (its decay runs past the segment end; verified on Husary 2:33).
/// * Default reciter: خليفة الطنيجي, with migration of the old
///   default (0 = الحصري).
/// * Cache-on-play: ayah and wbw files are downloaded once and played
///   from disk after that — no streaming stutter on a weak connection.
/// * Zoom: the Mushaf caps at 0.98 (see noor_qcf_page).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseWordSegments', () {
    test('string numbers (Sudais 2:33, real API shape) parse correctly', () {
      final segments = parseWordSegments({
        'audio': {
          'segments': [
            ['0', '1', '50', '570'],
            ['1', '2', '580', '1200'],
            ['2', '3', '1210', '2400'],
          ],
        },
      });
      expect(segments, isNotNull);
      expect(segments!.length, 3);
      expect(segments.first.startMs, 50);
      expect(segments.first.endMs, 570);
      expect(segments.last.startMs, 1210);
      expect(segments.last.endMs, 2400);
    });

    test('int numbers (Husary 2:33, real API shape) still parse', () {
      final segments = parseWordSegments({
        'audio': {
          'segments': [
            [0, 1, 850, 1760],
            [1, 2, 1770, 5010],
          ],
        },
      });
      expect(segments, isNotNull);
      expect(segments!.length, 2);
      expect(segments.first.startMs, 850);
      expect(segments.last.endMs, 5010);
    });

    test(
        'a malformed entry never crashes: it is skipped, the list '
        'stays contiguous from word 0', () {
      final segments = parseWordSegments({
        'audio': {
          'segments': [
            [0, 1, 850, 1760],
            ['x', 'y', 'z', 'w'],
          ],
        },
      });
      // The bad entry is skipped; the remaining list is contiguous
      // from word 0, so word 1 still plays in the reciter's voice
      // and later words fall back to wbw (guarded by the length
      // check in the controller).
      expect(segments, isNotNull);
      expect(segments!.length, 1);
      expect(segments.first.startMs, 850);
    });

    test('a malformed FIRST entry degrades to null (wbw fallback)', () {
      final segments = parseWordSegments({
        'audio': {
          'segments': [
            ['x', 'y', 'z', 'w'],
            [1, 2, 1770, 5010],
          ],
        },
      });
      // Index 0 is missing, so the list is not contiguous from 0.
      expect(segments, isNull);
    });
  });

  group('paddedWordWindow', () {
    test('last word of an ayah gets the longer end padding', () {
      final (seekTo, end) = AudioPlayerController.paddedWordWindow(
        const WordSegment(44650, 47580),
        isLastWord: true,
      );
      expect(seekTo, const Duration(milliseconds: 44530));
      expect(end, const Duration(milliseconds: 47980));
    });

    test('a middle word keeps the 150 ms end padding', () {
      final (seekTo, end) = AudioPlayerController.paddedWordWindow(
        const WordSegment(850, 1760),
      );
      expect(seekTo, const Duration(milliseconds: 730));
      expect(end, const Duration(milliseconds: 1910));
    });
  });

  group('resolveDefaultReciterIndex', () {
    test('absent or old default migrates to الطنيجي (12)', () {
      expect(resolveDefaultReciterIndex(null), 12);
      expect(resolveDefaultReciterIndex(0), 12);
      expect(reciters[12].name, 'خليفة الطنيجي');
      expect(reciters[12].everyayah, 'khalefa_al_tunaiji_64kbps');
    });

    test('a reciter the user chose himself is kept', () {
      expect(resolveDefaultReciterIndex(5), 5);
      expect(resolveDefaultReciterIndex(12), 12);
    });

    test('out-of-range values clamp to the list', () {
      expect(resolveDefaultReciterIndex(99), reciters.length - 1);
      expect(resolveDefaultReciterIndex(-3), 0);
    });
  });

  group('clampMushafZoom', () {
    test('anything above 0.98 clamps to 0.98', () {
      expect(clampMushafZoom(1.04), 0.98);
      expect(clampMushafZoom(1.08), 0.98);
      expect(clampMushafZoom(1.0), 0.98);
    });

    test('the allowed range 0.92-0.98 passes through', () {
      expect(clampMushafZoom(0.92), 0.92);
      expect(clampMushafZoom(0.96), 0.96);
      expect(clampMushafZoom(0.98), 0.98);
    });

    test('anything below 0.92 clamps to 0.92', () {
      expect(clampMushafZoom(0.5), 0.92);
    });
  });

  group('cache-on-play (AudioDownloadService)', () {
    Directory? tempDir;

    Future<AudioDownloadService> makeService(http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('audio-v13-test');
      final s = AudioDownloadService(
        client: client,
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await s.init();
      return s;
    }

    tearDown(() async {
      final dir = tempDir;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
      tempDir = null;
    });

    test('cacheAyahFile downloads once, replays from disk', () async {
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([9, 8, 7, 6], 200);
      }));
      addTearDown(service.dispose);
      final tunaiji = reciters[12];

      final first = await service.cacheAyahFile(tunaiji, 2, 33);
      expect(first, isNotNull);
      expect(await first!.readAsBytes(), [9, 8, 7, 6]);
      expect(requested, [
        'https://everyayah.com/data/khalefa_al_tunaiji_64kbps/002033.mp3',
      ]);
      // The player sees the same file through the sync accessor.
      expect(service.localAyahFile(tunaiji, 2, 33)?.path, first.path);

      final second = await service.cacheAyahFile(tunaiji, 2, 33);
      expect(second?.path, first.path);
      expect(requested.length, 1, reason: 'no second download');
    });

    test('cacheAyahFile failure leaves no file and returns null', () async {
      final service = await makeService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final file = await service.cacheAyahFile(reciters[12], 2, 33);
      expect(file, isNull);
      expect(service.localAyahFile(reciters[12], 2, 33), isNull);
      // No partial file on disk either.
      final dir = Directory('${tempDir!.path}/${reciters[12].everyayah}');
      expect(await dir.exists(), isFalse);
    });

    test('cacheWbwFile downloads once, replays from disk', () async {
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([1, 2, 3], 200);
      }));
      addTearDown(service.dispose);

      final first = await service.cacheWbwFile(2, 33, 4);
      expect(first, isNotNull);
      expect(await first!.readAsBytes(), [1, 2, 3]);
      expect(requested, [
        'https://verses.quran.com/wbw/002_033_004.mp3',
      ]);
      expect(service.localWbwFile(2, 33, 4)?.path, first.path);

      final second = await service.cacheWbwFile(2, 33, 4);
      expect(second?.path, first.path);
      expect(requested.length, 1, reason: 'no second download');
    });
  });
}
