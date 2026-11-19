import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';

import 'fake_just_audio.dart';
import 'fake_mp3.dart';

/// v13.2 audio: the WORD plays FIRST from Quran.com's dedicated
/// per-word recording (wbw) — one fixed teaching voice, complete and
/// clear by construction, exactly like the world apps.
///
/// v13.4 — THE MAPPING: the wbw file number IS the word position
/// (1-based, among the ayah's audio words). Pause marks do NOT
/// count as positions. v13.2/13.3 believed the opposite — the
/// Quran.com API's audio_url field counts pause marks, and a
/// bundled shift table reproduced the API faithfully (0 mismatches
/// over 77,429 words). That verification was the mistake: it
/// verified file NUMBERS against the API, never the files' spoken
/// CONTENT. Transcription of the real files (2026-11-17, two ASR
/// models, 39 words over 20 surahs) proved the FILES are numbered
/// by word position only — e.g. 3:7 word 15 الَّذِينَ is file 015
/// (the API claims 016, and 016 speaks فِي). The API field is
/// wrong relative to its own files, so the shift table (and its
/// generator) were deleted; there is no table any more.
///
/// Fallback chain (v13.2, bug A; v13.5 adds SurahPedia as the third
/// wbw host): wbw (new CDN, then legacy host, then SurahPedia) →
/// sheet error with retry. There is NO segment/ayah fallback any
/// more — the segment subsystem was deleted: a word tap that cannot
/// fetch its wbw file must NEVER play the ayah file (that was the
/// user's #1 complaint). Playback runs on the fake platform
/// (test/fake_just_audio.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  group('wbw file number IS the word position (v13.4)', () {
    test('URL builders: new CDN first, legacy host second', () {
      expect(wbwWordUrl(2, 33, 6),
          'https://audio.qurancdn.com/wbw/002_033_006.mp3');
      expect(wbwWordUrlLegacy(2, 33, 6),
          'https://verses.quran.com/wbw/002_033_006.mp3');
      expect(wbwWordUrl(1, 1, 1),
          'https://audio.qurancdn.com/wbw/001_001_001.mp3');
    });

    test('file number == audio position, even after pause marks', () {
      // The cases that were WRONG under the shift table (v13.2/13.3):
      // 3:7 word 15 الَّذِينَ is file 015 (the API claims 016, and
      // 016 speaks فِي); 2:255 word 48 is file 048 (API: 056);
      // 2:26 word 1 is file 001 (API: 002); 2:81 word 11 is file
      // 011 (API: 012). Proven by transcription of the real files
      // (2026-11-17, two ASR models, 39 words over 20 surahs).
      expect(wbwWordUrl(3, 7, 15),
          'https://audio.qurancdn.com/wbw/003_007_015.mp3');
      expect(wbwWordUrl(2, 255, 48),
          'https://audio.qurancdn.com/wbw/002_255_048.mp3');
      expect(wbwWordUrl(2, 26, 1),
          'https://audio.qurancdn.com/wbw/002_026_001.mp3');
      expect(wbwWordUrl(2, 81, 11),
          'https://audio.qurancdn.com/wbw/002_081_011.mp3');
      // Merged ayahs: the AUDIO position (not the display index)
      // is the file number — 2:181 display 5 -> audio 4 -> 004.
      expect(audioPositionForQcfWord(2, 181, 5), 4);
      expect(wbwWordUrl(2, 181, audioPositionForQcfWord(2, 181, 5)),
          'https://audio.qurancdn.com/wbw/002_181_004.mp3');
      expect(wbwWordUrl(37, 130, audioPositionForQcfWord(37, 130, 4)),
          'https://audio.qurancdn.com/wbw/037_130_003.mp3');
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

    test('SurahPedia is tried first (v13.6): word caches on the first attempt',
        () async {
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'audio.qurancdn.com') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes(fakeMp3Bytes(), 200);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheWbwFile(2, 33, 6);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes());
      expect(requested, [
        'https://resources.surahpedia.com/Word_by-Word/2/002033006.mp3',
      ]);
      // Second call replays from disk: no further request.
      final second = await service.cacheWbwFile(2, 33, 6);
      expect(second?.path, file.path);
      expect(requested.length, 1, reason: 'no second download');
    });

    test('all three hosts fail → null, no file left behind', () async {
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

    test('word 5 of 2:33 plays wbw file 005 (v13.4)', () async {
      fake.autoFinish = false;
      controller.reciterIndex = 12; // خليفة الطنيجي (default)
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 5; // فَلَمَّآ — after the ۖ on word 4
      await controller.replayCurrent();

      expect(fake.loadCount, 1, reason: 'one play attempted');
      expect(fake.loadUris.single,
          // v13.6: SurahPedia is tried first.
          'https://resources.surahpedia.com/Word_by-Word/2/002033005.mp3');
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
          // v13.6: SurahPedia is tried first.
          'https://resources.surahpedia.com/Word_by-Word/2/002033001.mp3');
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    // v13.6: SurahPedia is tried FIRST — when it is down, the new
    // CDN is next and the word still plays from its wbw file.
    test('SurahPedia down → new CDN plays, still wbw', () async {
      fake.autoFinish = false;
      fake.failLoadSubstrings.add('resources.surahpedia.com');
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Word_by-Word/2/002033001.mp3',
        'https://audio.qurancdn.com/wbw/002_033_001.mp3',
      ]);
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    // v13.2 bug A: a word tap plays ONLY its wbw file. When wbw
    // cannot be fetched on any host, the word does NOT fall back
    // to the ayah file (or any segment cut) — it reports an error
    // and the sheet offers a retry. The regression: NO ayah URL is
    // ever loaded for a word play.
    test('wbw fails on all three hosts → error, NO ayah file loaded',
        () async {
      fake.autoFinish = false;
      fake.failLoadSubstrings.addAll([
        'audio.qurancdn.com',
        'verses.quran.com',
        'resources.surahpedia.com',
      ]);
      controller.reciterIndex = 12; // خليفة الطنيجي (default)
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadUris, [
        // v13.6 order: SurahPedia first, then the Quran.com hosts.
        'https://resources.surahpedia.com/Word_by-Word/2/002033001.mp3',
        'https://audio.qurancdn.com/wbw/002_033_001.mp3',
        'https://verses.quran.com/wbw/002_033_001.mp3',
      ], reason: 'only the three wbw hosts are attempted');
      expect(
          fake.loadUris.every((u) =>
              u.contains('/wbw/') || u.contains('Word_by-Word')),
          isTrue,
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
        'resources.surahpedia.com',
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
          fake.loadUris.every((u) =>
              u ==
              'https://resources.surahpedia.com/Word_by-Word/2/002033005.mp3'),
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
