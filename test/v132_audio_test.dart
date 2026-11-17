import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/data/word_meanings.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';

import 'fake_just_audio.dart';

/// v13.2 audio: the WORD plays FIRST from Quran.com's dedicated
/// per-word recording (wbw) — one fixed teaching voice, complete and
/// clear by construction, exactly like the world apps.
///
/// The mapping is the critical part: the wbw file number is NOT the
/// word position — the wbw set numbers pause marks as positions of
/// their own, and NO rule from our tokens reproduces it (verified
/// against the Quran.com Verses API for all 6,236 ayahs: the
/// pause-mark rule mismatched 5,519 words in 374 ayahs — e.g. 2:81
/// word 1 carries U+06DA in our tokens but the API drops it, while
/// 2:255 word 7 carries the SAME mark and it shifts; the ۞ rub el
/// hizb counts as position 1 but never appears in our tokens). So
/// the mapping is a bundled shift table
/// (`assets/quran_data/word_wbw_shifts.json`, generated from the
/// API's audio_urls by `tool/build_wbw_shifts.py`: 2,705 ayahs,
/// 4,560 shift points, reconstruction 0 mismatches over 77,429
/// words), and the file number is position + #{shifts < position}.
///
/// Fallback chain (v13.2, bug A): wbw (new CDN, then legacy host) →
/// sheet error with retry. There is NO segment/ayah fallback any
/// more — the segment subsystem was deleted: a word tap that cannot
/// fetch its wbw file must NEVER play the ayah file (that was the
/// user's #1 complaint). Playback runs on the fake platform
/// (test/fake_just_audio.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  group('wbwFileNumberFromShifts — bundled shift table', () {
    test('URL builders: new CDN first, legacy host second', () {
      expect(wbwWordUrl(2, 33, 6),
          'https://audio.qurancdn.com/wbw/002_033_006.mp3');
      expect(wbwWordUrlLegacy(2, 33, 6),
          'https://verses.quran.com/wbw/002_033_006.mp3');
      expect(wbwWordUrl(1, 1, 1),
          'https://audio.qurancdn.com/wbw/001_001_001.mp3');
    });

    test('pure function: shift points add one step each, only before',
        () {
      // 2:33 shifts [4]: words 1–4 are files 1–4, word 5 is 6.
      expect(wbwFileNumberFromShifts([4], 1), 1);
      expect(wbwFileNumberFromShifts([4], 4), 4);
      expect(wbwFileNumberFromShifts([4], 5), 6);
      expect(wbwFileNumberFromShifts([4], 22), 23);
      // Leading ۞ (shift 0): even word 1 is shifted.
      expect(wbwFileNumberFromShifts([0], 1), 2);
      expect(wbwFileNumberFromShifts([0, 11], 12), 14);
      // No shifts: file number == position.
      expect(wbwFileNumberFromShifts([], 7), 7);
    });

    test('bundled table: 2:33 shifts [4] (the ۖ after word 4)',
        () async {
      expect(await wbwShiftsForAyah(2, 33), [4]);
      expect(wbwFileNumberFromShifts([4], 5), 6,
          reason: 'word 5 of 2:33 is file 006, not 005');
    });

    test('bundled table: 2:255 shifts (8 skips) match the API',
        () async {
      final shifts = await wbwShiftsForAyah(2, 255);
      expect(shifts, [7, 12, 19, 26, 32, 40, 44, 47]);
      final skipped = {8, 14, 22, 30, 37, 46, 51, 55};
      final expected = [
        for (var n = 1; n <= 58; n++) if (!skipped.contains(n)) n,
      ];
      final actual = [
        for (var w = 1; w <= 50; w++)
          wbwFileNumberFromShifts(shifts, w),
      ];
      expect(actual, expected);
    });

    test('bundled table: leading ۞ and the counter-examples', () async {
      // 2:26 starts a hizb: the ۞ is position 1, word 1 is file 002.
      final shifts26 = await wbwShiftsForAyah(2, 26);
      expect(shifts26.first, 0);
      expect(wbwFileNumberFromShifts(shifts26, 1), 2);
      // 2:81: the ۚ on word 1 does NOT shift (API drops it) — the
      // only shift is after word 10. A token-based rule gets this
      // ayah wrong; the table gets it right.
      expect(await wbwShiftsForAyah(2, 81), [10]);
      expect(wbwFileNumberFromShifts([10], 1), 1);
      expect(wbwFileNumberFromShifts([10], 11), 12);
      // 36:52: the saktah pair adds one step after word 7 (word 7
      // itself is file 007 — duration-verified, see
      // tool/build_wbw_shifts.py).
      expect(await wbwShiftsForAyah(36, 52), [7]);
      expect(wbwFileNumberFromShifts([7], 7), 7);
      expect(wbwFileNumberFromShifts([7], 8), 9);
    });

    test('bundled table: ayahs without shifts return empty', () async {
      for (final (s, a) in [(1, 1), (2, 6), (112, 1)]) {
        final shifts = await wbwShiftsForAyah(s, a);
        expect(shifts, isEmpty);
      }
      final tokens = await QuranWordData.wordsForAyah(1, 1);
      expect(tokens.length, 4);
      for (var w = 1; w <= 4; w++) {
        expect(wbwFileNumberFromShifts([], w), w);
      }
    });
  });

  group('cacheWbwFile host fallback (AudioDownloadService)', () {
    Directory? tempDir;

    Future<AudioDownloadService> makeService(http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('audio-v132-test');
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

    test('new CDN fails → legacy host is tried, file cached', () async {
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'audio.qurancdn.com') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([9, 8, 7], 200);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheWbwFile(2, 33, 6);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [9, 8, 7]);
      expect(requested, [
        'https://audio.qurancdn.com/wbw/002_033_006.mp3',
        'https://verses.quran.com/wbw/002_033_006.mp3',
      ]);
      // Second call replays from disk: no further request.
      final second = await service.cacheWbwFile(2, 33, 6);
      expect(second?.path, file.path);
      expect(requested.length, 2, reason: 'no second download');
    });

    test('both hosts fail → null, no file left behind', () async {
      final service = await makeService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheWbwFile(2, 33, 6);
      expect(file, isNull);
      expect(service.localWbwFile(2, 33, 6), isNull);
    });
  });

  group('controller — wbw first (fake platform)', () {
    late AudioPlayerController controller;

    setUp(() {
      fake.autoFinish = true;
      fake.failLoadSubstrings.clear();
      fake.resetCounts();
      controller = AudioPlayerController();
      addTearDown(controller.dispose);
    });

    Future<void> waitForLoads(int n) async {
      for (var i = 0; i < 40 && fake.loadCount < n; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(fake.loadCount, n);
    }

    Future<void> settle([int ms = 600]) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
    }

    test('word 5 of 2:33 plays wbw file 006, not 005', () async {
      fake.autoFinish = false;
      controller.reciterIndex = 12; // خليفة الطنيجي (default)
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 5; // فَلَمَّآ — after the ۖ on word 4
      await controller.replayCurrent();

      expect(fake.loadCount, 1, reason: 'one play attempted');
      expect(fake.loadUris.single,
          'https://audio.qurancdn.com/wbw/002_033_006.mp3');
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    test('word 1 of 2:33 plays wbw file 001', () async {
      fake.autoFinish = false;
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadUris.single,
          'https://audio.qurancdn.com/wbw/002_033_001.mp3');
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    test('new CDN fails → legacy host plays, still wbw', () async {
      fake.autoFinish = false;
      fake.failLoadSubstrings.add('audio.qurancdn.com');
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadUris, [
        'https://audio.qurancdn.com/wbw/002_033_001.mp3',
        'https://verses.quran.com/wbw/002_033_001.mp3',
      ]);
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    // v13.2 bug A: a word tap plays ONLY its wbw file. When wbw
    // cannot be fetched on either host, the word does NOT fall back
    // to the ayah file (or any segment cut) — it reports an error
    // and the sheet offers a retry. The regression: NO ayah URL is
    // ever loaded for a word play.
    test('wbw fails on both hosts → error, NO ayah file loaded', () async {
      fake.autoFinish = false;
      fake.failLoadSubstrings
          .addAll(['audio.qurancdn.com', 'verses.quran.com']);
      controller.reciterIndex = 12; // خليفة الطنيجي (default)
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadUris, [
        'https://audio.qurancdn.com/wbw/002_033_001.mp3',
        'https://verses.quran.com/wbw/002_033_001.mp3',
      ], reason: 'only the two wbw hosts are attempted');
      expect(fake.loadUris.every((u) => u.contains('/wbw/')), isTrue,
          reason: 'no ayah file, no segment file, nothing else');
      expect(controller.wordUsesWbw, isFalse);
      expect(controller.lastError, isNotNull,
          reason: 'the sheet shows the error with a retry');
    });

    test('wbw fails → sheet error, no silent gap', () async {
      fake.autoFinish = false;
      fake.failLoadSubstrings.addAll([
        'audio.qurancdn.com',
        'verses.quran.com',
      ]);
      controller.reciterIndex = 12;
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(controller.lastError, isNotNull);
      expect(controller.wordUsesWbw, isFalse);
    });

    test('word repeats via wbw exactly repeatCount times', () async {
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 5;
      controller.repeatItem = true;
      controller.repeatCount = 3;
      await controller.replayCurrent();

      await waitForLoads(3);
      expect(controller.wordIndex, 5, reason: 'still the same word');
      expect(
          fake.loadUris.every(
              (u) => u == 'https://audio.qurancdn.com/wbw/002_033_006.mp3'),
          isTrue,
          reason: 'every replay is the same wbw file');
      await settle();
      expect(fake.loadCount, 3,
          reason: 'no 4th play — count reached, stopped');
      expect(controller.lastError, isNull);
    });
  });

  group('player sheet — wbw note (primary voice)', () {
    Future<void> pumpSheet(WidgetTester tester,
        AudioPlayerController controller) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(0.7),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: AudioPlayerSheet(
              controller: controller,
              currentPage: 1,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('wbw note names the fixed teaching voice', (tester) async {
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      controller.wordUsesWbw = true;
      await pumpSheet(tester, controller);

      expect(
        find.text(
          'الكلمة بصوت تعليمي موحّد — تسجيل خاص للكلمة، وليست بصوت القارئ المختار',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('بصوت محمود الحصري'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
