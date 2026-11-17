import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/widgets/mini_audio_bar.dart';

import 'fake_just_audio.dart';

/// v13.1 audio: replay / repeat, plus the word's wbw-first rule.
/// The ayah scope still uses the selected reciter (الطنيجي by
/// default). The word plays ONLY its wbw file (v13.2, bug A): the
/// v13.1 segment subsystem (Husary fallback, paddedWordWindow,
/// wordVoiceReciterIndex) was DELETED — a word that cannot fetch its
/// wbw file reports an error and never plays the ayah file.
/// See test/v132_audio_test.dart for the wbw mapping / fallback tests.
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
  // v13.2: stop() cancels repeat, and _cancelRepeat persists the
  // settings — without this mock the unawaited persist throws a
  // MissingPluginException AFTER a repeat test completes and fails
  // it retroactively (see test/v132_bugs_test.dart for the same).
  SharedPreferences.setMockInitialValues({});

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

    test('word with الطنيجي plays the wbw file FIRST (v13.2)', () async {
      fake.autoFinish = false;
      controller.reciterIndex = 12; // خليفة الطنيجي (default)
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadCount, 1, reason: 'one play attempted');
      expect(fake.loadUris.single,
          'https://audio.qurancdn.com/wbw/002_033_001.mp3',
          reason: 'the wbw file plays first — no segment cut');
      expect(fake.loadUris.single, isNot(contains('khalefa_al_tunaiji')));
      expect(fake.loadUris.single, isNot(contains('Husary')));
      expect(controller.wordUsesWbw, isTrue);
      expect(controller.lastError, isNull);
    });

    test('word with الحصري himself also plays wbw first (v13.2)',
        () async {
      fake.autoFinish = false;
      controller.reciterIndex = 0;
      controller.queue = [(2, 33)];
      controller.queueIndex = 0;
      controller.scope = PlayerScope.word;
      controller.wordIndex = 1;
      await controller.replayCurrent();

      expect(fake.loadCount, 1);
      expect(fake.loadUris.single,
          'https://audio.qurancdn.com/wbw/002_033_001.mp3');
      expect(controller.wordUsesWbw, isTrue);
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
      // The tap replayed word 1 of 2:33 exactly once, from its wbw
      // file (v13.2: wbw first), with no error — and the word did
      // not repeat (repeat is off).
      expect(fake.loadCount, 1);
      expect(fake.loadUris.single,
          'https://audio.qurancdn.com/wbw/002_033_001.mp3');
      expect(controller.wordUsesWbw, isTrue);
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

}
