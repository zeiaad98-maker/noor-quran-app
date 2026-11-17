import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';
import 'package:noor_quran/widgets/mini_audio_bar.dart';

import 'fake_just_audio.dart';

/// v13.1 audio: the WORD plays in محمود الحصري's voice when the
/// selected reciter has no Quran.com word segments (the user's
/// decision, Tue 2026-11-17) — the ayah scope still uses the
/// selected reciter (الطنيجي by default) — plus replay / repeat.
///
/// Playback runs on the fake platform (test/fake_just_audio.dart):
/// just_audio has no audio platform in flutter_test, so the real
/// player hangs or throws unhandled MissingPluginExceptions there.
/// The fake loads instantly and finishes each item 100 ms after
/// play, so the controller's real finish / repeat dispatch runs end
/// to end. One load per play attempt is counted on the fake, and
/// the load URIs prove WHICH reciter's file played.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  group('wordVoiceReciterIndex (v13.1: word voice = الحصري fallback)', () {
    test('reciters WITHOUT segments fall back to الحصري (0)', () {
      // ماهر المعيقلي (4)، علي الحذيفي (5)، أيمن سويد (7)،
      // إبراهيم الأخضر (11)، خليفة الطنيجي (12)، ياسر الدوسري (14).
      for (final i in [4, 5, 7, 11, 12, 14]) {
        expect(reciters[i].quranComRecitationId, isNull,
            reason: '${reciters[i].name} has no segments');
        expect(wordVoiceReciterIndex(i), 0);
      }
      expect(reciters[12].name, 'خليفة الطنيجي');
    });

    test('reciters WITH segments keep their own voice', () {
      // الحصري (0)، العفاسي (1)، المنشاوي (2)، عبد الباسط (3)،
      // الشاطري (6)، الشريم (8)، السديس (9)، الرفاعي (10)،
      // الطبلاوي (13).
      for (final i in [0, 1, 2, 3, 6, 8, 9, 10, 13]) {
        expect(reciters[i].quranComRecitationId, isNotNull,
            reason: '${reciters[i].name} should have segments');
        expect(wordVoiceReciterIndex(i), i);
      }
    });

    test('out-of-range indices clamp before resolving', () {
      expect(wordVoiceReciterIndex(99), 0); // clamps to 14 → no segments
      expect(wordVoiceReciterIndex(-3), 0); // clamps to 0 → الحصري
    });

    test('the fallback resolves to Husary segments + Husary ayah file',
        () async {
      final wordReciter = reciters[wordVoiceReciterIndex(12)];
      expect(wordReciter.name, 'محمود الحصري');
      expect(
        quranComAyahUrl(wordReciter, 2, 33),
        contains('Husary_64kbps/002033.mp3'),
      );
      // The bundled Husary segments are what the fallback plays
      // from — 2:33 has 22 words, first قال 850–1760 ms.
      final segments = await wordSegmentsFor(wordReciter, 2, 33);
      expect(segments, isNotNull);
      expect(segments!.length, 22);
      expect(segments.first.startMs, 850);
      expect(segments.first.endMs, 1760);
    });
  });

  group('paddedWordWindow — measured against REAL Husary audio', () {
    // Method (2026-11-17): everyayah Husary_64kbps files, decoded
    // to 16 kHz mono, 10 ms RMS frames, speech threshold -40 dBFS
    // (silence floor ~-60 dBFS). All 80 words of 1:1, 2:33, 2:255,
    // 112:1 checked incl. first + last of each ayah: worst start
    // margin +50 ms, worst true end margin +200 ms, no word cut.
    // These tests pin the window arithmetic for the tightest
    // measured cases, so a padding change fails loudly.

    test('2:33 word 5 — tightest start: onset 14260, padded 14230', () {
      // Segment [14350, 15830], 1850 ms of silence before it, so the
      // onset is measurable exactly: 90 ms before the segment start.
      final (seekTo, end) = AudioPlayerController.paddedWordWindow(
        const WordSegment(14350, 15830),
      );
      expect(seekTo, const Duration(milliseconds: 14230));
      expect(end, const Duration(milliseconds: 15980));
      // The measured onset (14260) sits 30 ms inside the window at
      // the strict -46 dBFS threshold, 60 ms at -40 dBFS.
      expect(seekTo.inMilliseconds, lessThan(14260));
    });

    test('2:255 word 27 — tightest start at -40 dBFS: onset 31030', () {
      // Segment [31100, 31680], 650 ms of silence before it.
      final (seekTo, end) = AudioPlayerController.paddedWordWindow(
        const WordSegment(31100, 31680),
      );
      expect(seekTo, const Duration(milliseconds: 30980));
      expect(end, const Duration(milliseconds: 31830));
      expect(seekTo.inMilliseconds, lessThan(31030));
    });

    test('2:255 word 50 — last word: decay ends 59879, padded 60230', () {
      final (seekTo, end) = AudioPlayerController.paddedWordWindow(
        const WordSegment(57710, 59830),
        isLastWord: true,
      );
      expect(seekTo, const Duration(milliseconds: 57590));
      expect(end, const Duration(milliseconds: 60230));
      expect(end.inMilliseconds, greaterThan(59879));
    });

    test('1:1 word 1 — first word of the Mushaf, start clamps at 0', () {
      // Segment [50, 510]: onset 100 ms, padded start 0.
      final (seekTo, end) = AudioPlayerController.paddedWordWindow(
        const WordSegment(50, 510),
      );
      expect(seekTo, Duration.zero);
      expect(end, const Duration(milliseconds: 660));
    });

    test('2:255 word 47 — its tail ends 55299, NOT at the next onset',
        () {
      // The word's own sound is silence from ~55300; the energy at
      // 56230+ is word 48's onset ramp (its segment starts 56300).
      // The padded end (56250) covers the tail with ~950 ms margin.
      final (seekTo, end) = AudioPlayerController.paddedWordWindow(
        const WordSegment(53600, 56100),
      );
      expect(seekTo, const Duration(milliseconds: 53480));
      expect(end, const Duration(milliseconds: 56250));
      expect(end.inMilliseconds, greaterThan(55299));
    });
  });

  group('shouldRepeat — repeat counts 1/3/5/10/continuous', () {
    test('count 3: replays after plays 1 and 2, stops after play 3', () {
      expect(
          AudioPlayerController.shouldRepeat(
              enabled: true, repeatCount: 3, plays: 1),
          isTrue);
      expect(
          AudioPlayerController.shouldRepeat(
              enabled: true, repeatCount: 3, plays: 2),
          isTrue);
      expect(
          AudioPlayerController.shouldRepeat(
              enabled: true, repeatCount: 3, plays: 3),
          isFalse);
    });

    test('counts 5 and 10 follow the same rule', () {
      for (final count in [5, 10]) {
        expect(
            AudioPlayerController.shouldRepeat(
                enabled: true, repeatCount: count, plays: count - 1),
            isTrue);
        expect(
            AudioPlayerController.shouldRepeat(
                enabled: true, repeatCount: count, plays: count),
            isFalse);
      }
    });

    test('count 1 never replays', () {
      expect(
          AudioPlayerController.shouldRepeat(
              enabled: true, repeatCount: 1, plays: 1),
          isFalse);
    });

    test('count 0 (continuous) never stops on its own', () {
      expect(
          AudioPlayerController.shouldRepeat(
              enabled: true, repeatCount: 0, plays: 1000),
          isTrue);
    });

    test('disabled repeat never replays, whatever the count', () {
      expect(
          AudioPlayerController.shouldRepeat(
              enabled: false, repeatCount: 0, plays: 1),
          isFalse);
      expect(
          AudioPlayerController.shouldRepeat(
              enabled: false, repeatCount: 3, plays: 1),
          isFalse);
    });
  });

  group('repeat dispatch (word + ayah scope, fake platform)', () {
    // The fake finishes each item ~100 ms after play, so the
    // controller's real finish path runs. One fake load = one play
    // attempt. Wait until the expected loads appear, then wait
    // longer and assert no further load happened (it stopped).
    late AudioPlayerController controller;

    setUp(() {
      fake.autoFinish = true;
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

    test('word repeats exactly repeatCount times, then stops', () async {
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      controller.repeatItem = true;
      controller.repeatCount = 3;
      await controller.replayCurrent();

      await waitForLoads(3);
      expect(controller.wordIndex, 1, reason: 'still the same word');
      expect(controller.queueIndex, 0, reason: 'did not advance');
      await settle();
      expect(fake.loadCount, 3,
          reason: 'no 4th play — count reached, stopped');
      expect(controller.lastError, isNull);
    });

    test('word with count 1 plays once, then stops', () async {
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      controller.repeatItem = true;
      controller.repeatCount = 1;
      await controller.replayCurrent();

      await waitForLoads(1);
      await settle();
      expect(fake.loadCount, 1, reason: 'count 1 never replays');
    });

    test('word with continuous count keeps replaying', () async {
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      controller.repeatItem = true;
      controller.repeatCount = 0;
      await controller.replayCurrent();

      await waitForLoads(6);
      expect(fake.loadCount, greaterThanOrEqualTo(6));
      // Halt the infinite loop before tearDown disposes the
      // controller, so no replay is in flight afterwards.
      await controller.stop();
    });

    test('ayah scope repeats exactly repeatCount times, then stops',
        () async {
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.ayah;
      controller.repeatItem = true;
      controller.repeatCount = 3;
      await controller.replayCurrent();

      await waitForLoads(3);
      await settle();
      expect(fake.loadCount, 3,
          reason: 'no 4th play — count reached, stopped');
      expect(controller.queueIndex, 0, reason: 'single-ayah queue');
      expect(controller.lastError, isNull);
    });

    test('word with الطنيجي plays the HUSARY file, not wbw', () async {
      fake.autoFinish = false;
      controller.reciterIndex = 12; // خليفة الطنيجي (default)
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadCount, 1, reason: 'one play attempted');
      expect(fake.loadUris.single, contains('Husary_64kbps'),
          reason: 'the Husary ayah file is what plays');
      expect(fake.loadUris.single, isNot(contains('khalefa_al_tunaiji')));
      expect(controller.wordUsesHusaryFallback, isTrue,
          reason: 'Tunaiji has no segments → Husary voice');
      expect(controller.wordUsesWbw, isFalse,
          reason: 'wbw is only the last resort');
      expect(controller.wordSegments?.length, 22,
          reason: 'Husary segments resolved for 2:33');
      expect(controller.lastError, isNull);
    });

    test('word with الحصري himself plays in his own voice', () async {
      fake.autoFinish = false;
      controller.reciterIndex = 0;
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadCount, 1);
      expect(fake.loadUris.single, contains('Husary_64kbps'));
      expect(controller.wordUsesHusaryFallback, isFalse);
      expect(controller.wordUsesWbw, isFalse);
      expect(controller.wordSegments?.length, 22);
      expect(controller.lastError, isNull);
    });

    test('ayah with الطنيجي plays the TUNAIJI file (ayah scope untouched)',
        () async {
      fake.autoFinish = false;
      controller.reciterIndex = 12; // خليفة الطنيجي (default)
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.ayah;
      await controller.replayCurrent();

      expect(fake.loadCount, 1);
      expect(fake.loadUris.single, contains('khalefa_al_tunaiji_64kbps'));
      expect(fake.loadUris.single, isNot(contains('Husary')));
      expect(controller.lastError, isNull);
    });
  });

  group('mini audio bar — replay button', () {
    late AudioPlayerController controller;

    setUp(() {
      fake.autoFinish = true;
      fake.resetCounts();
      controller = AudioPlayerController();
      addTearDown(controller.dispose);
    });

    Future<void> pumpBar(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniAudioBar(
              controller: controller,
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the replay control is present (only new control)',
        (tester) async {
      await pumpBar(tester);

      expect(find.byTooltip('إعادة الكلمة'), findsOneWidget);
      expect(find.byIcon(Icons.replay), findsOneWidget);
      // Everything else is unchanged: repeat-one toggle, prev/next,
      // play, ••• menu, close.
      expect(find.byTooltip('تكرار العنصر الحالي'), findsOneWidget);
      expect(find.byTooltip('السابق'), findsOneWidget);
      expect(find.byTooltip('التالي'), findsOneWidget);
      expect(find.byTooltip('إغلاق وإيقاف الصوت'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('replay tap with an empty queue is a safe no-op',
        (tester) async {
      await pumpBar(tester);

      await tester.tap(find.byTooltip('إعادة الكلمة'));
      await tester.pump();
      expect(controller.isLoading, isFalse);
      expect(controller.lastError, isNull);
      expect(fake.players, isEmpty, reason: 'nothing played');
      expect(tester.takeException(), isNull);
    });

    testWidgets('replay tap restarts the current word', (tester) async {
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await pumpBar(tester);

      await tester.tap(find.byTooltip('إعادة الكلمة'));
      await tester.pump();
      // The replay started: the controller is loading the word.
      expect(controller.isLoading, isTrue);
      // RootBundle loads in tests need real-async windows (same
      // pattern as the word-card tests).
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
        if (!controller.isLoading) break;
      }
      expect(controller.isLoading, isFalse);
      // Let the fake finish the word (100 ms timer, fake time).
      await tester.pump(const Duration(milliseconds: 300));
      // The tap replayed word 1 of 2:33 exactly once, in Husary's
      // voice (default reciter here is الحصري himself), with no
      // error — and the word did not repeat (repeat is off).
      expect(fake.loadCount, 1);
      expect(fake.loadUris.single, contains('Husary_64kbps'));
      expect(controller.wordSegments?.length, 22);
      expect(controller.lastError, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('repeat-one replays the word per the count',
        (tester) async {
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await pumpBar(tester);

      // Turn repeat-one on (default count 3) and replay the word.
      await tester.tap(find.byTooltip('تكرار العنصر الحالي'));
      await tester.pump();
      expect(controller.repeatItem, isTrue);
      await tester.tap(find.byTooltip('إعادة الكلمة'));
      // RootBundle loads need real-async windows; the fake's
      // finish timer runs on fake time, advanced by pumping.
      for (var i = 0; i < 30 && fake.loadCount < 3; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(fake.loadCount, 3, reason: 'word played 3 times');
      expect(controller.wordIndex, 1, reason: 'still the same word');
      await tester.pump(const Duration(milliseconds: 600));
      expect(fake.loadCount, 3,
          reason: 'no 4th play — count reached, stopped');
      expect(controller.lastError, isNull);
      expect(tester.takeException(), isNull);
      // Halt anything still in flight before tearDown disposes the
      // controller (a replay load racing with dispose surfaces as
      // an unhandled error after the test).
      // stop() hangs when awaited directly in the widget-test
      // (fakeAsync) zone — run it in real async instead.
      await tester.runAsync(() => controller.stop());
    });
  });

  group('player sheet — Husary fallback note', () {
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

    testWidgets('Husary fallback note shows, wbw note does not',
        (tester) async {
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      controller.wordUsesHusaryFallback = true;
      controller.wordUsesWbw = false;
      await pumpSheet(tester, controller);

      expect(
        find.text(
          'الكلمة بصوت محمود الحصري — القارئ المختار ليس له مقاطع كلمة-بكلمة خاصة به',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('بصوت موحّد'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wbw note still shows for the last-resort case',
        (tester) async {
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      controller.wordUsesHusaryFallback = false;
      controller.wordUsesWbw = true;
      await pumpSheet(tester, controller);

      expect(find.textContaining('بصوت موحّد'), findsOneWidget);
      expect(find.textContaining('بصوت محمود الحصري'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
