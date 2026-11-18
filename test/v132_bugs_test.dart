import 'package:flutter/gestures.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/data/word_meanings.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';
import 'package:noor_quran/widgets/noor_qcf_page.dart';
import 'package:noor_quran/widgets/word_card.dart';

import 'fake_just_audio.dart';

/// v13.2 bug fixes — regression tests for the five user-reported bugs
/// (plus the best-apps arrangement, rules 1–6):
///
/// * Bug 1 — ayahs get MIXED UP: the stale-finish race (an old file
///   completing during a new load advanced the NEW queue) and the
///   4 merged-ayah word mappings (QCF display words vs audio words).
/// * Bug 2 — download arrow spins FOREVER: stop-during-load and the
///   60 s total budget (the spinner must always clear).
/// * Bug A — word tap plays the WHOLE AYAH: covered in
///   test/v132_audio_test.dart (wbw only, no ayah file ever loaded).
/// * Bug B — repeat does NOT work / does NOT stop: setRepeatCount
///   enables repeat, manual next cancels it, settings persist, and
///   the remaining-plays line shows in the sheet + mini bar.
/// * Bug C — NO highlighting during playback: the QCF page colours
///   the playing ayah (tint) and word (strong tint + word colour).
/// * UX D — no visible way to hear an AYAH: the word card's
///   "استمع للآية" button and long-press on a word (plays its ayah).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();
  // The controller persists repeat/speed via SharedPreferences on
  // every toggle — plain test()s have no method-channel mock for it
  // unless this is set (otherwise the unawaited persist throws a
  // MissingPluginException AFTER the test body completes and fails
  // the test retroactively). The persistence test below resets it
  // to {} for its own clean slate.
  SharedPreferences.setMockInitialValues({});

  Future<void> settle([int ms = 300]) async {
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  group('audioPositionForQcfWord — the 4 merged ayahs (bug 1)', () {
    test('2:181: words 3+4 share audio position 3, word 5 is 4', () {
      expect(audioPositionForQcfWord(2, 181, 1), 1);
      expect(audioPositionForQcfWord(2, 181, 2), 2);
      expect(audioPositionForQcfWord(2, 181, 3), 3);
      expect(audioPositionForQcfWord(2, 181, 4), 3,
          reason: 'بَعۡدَ مَا is two display words, one audio word');
      expect(audioPositionForQcfWord(2, 181, 5), 4);
      expect(audioPositionForQcfWord(2, 181, 14), 13);
    });

    test('37:130: words 3+4 share audio position 3', () {
      expect(audioPositionForQcfWord(37, 130, 1), 1);
      expect(audioPositionForQcfWord(37, 130, 2), 2);
      expect(audioPositionForQcfWord(37, 130, 3), 3);
      expect(audioPositionForQcfWord(37, 130, 4), 3,
          reason: 'إِلۡ يَاسِينَ is two display words, one audio word');
    });

    test('8:6 and 13:37: same merge shape', () {
      expect(audioPositionForQcfWord(8, 6, 4), 4);
      expect(audioPositionForQcfWord(8, 6, 5), 4);
      expect(audioPositionForQcfWord(8, 6, 6), 5);
      expect(audioPositionForQcfWord(13, 37, 8), 8);
      expect(audioPositionForQcfWord(13, 37, 9), 8);
      expect(audioPositionForQcfWord(13, 37, 10), 9);
    });

    test('any other ayah: identity (2:33, 2:255, 1:1)', () {
      for (final (s, a, w) in [(2, 33, 7), (2, 255, 27), (1, 1, 4)]) {
        expect(audioPositionForQcfWord(s, a, w), w);
      }
    });
  });

  group('QCF word count vs token count — full sweep (bug 1)', () {
    test('QCF == tokens everywhere EXCEPT the 4 merged ayahs (+1)',
        () async {
      final mismatches = <String>[];
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= quran.getVerseCount(s); a++) {
          final qcf = buildQcfWordMap(s, a).wordCount;
          final tokens = (await QuranWordData.wordsForAyah(s, a)).length;
          if (qcf != tokens) mismatches.add('$s:$a QCF=$qcf tokens=$tokens');
        }
      }
      expect(
        mismatches,
        ['2:181 QCF=14 tokens=13', '8:6 QCF=12 tokens=11',
         '13:37 QCF=20 tokens=19', '37:130 QCF=4 tokens=3'],
        reason: 'exactly the 4 merged ayahs differ, each by one word',
      );
    });
  });

  group('stale finish + stop during load (bugs 1+2)', () {
    late AudioPlayerController controller;

    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.loadDelay = Duration.zero;
      fake.resetCounts();
      controller = AudioPlayerController();
      addTearDown(controller.dispose);
    });

    test('stale completed during a new load does NOT advance the queue',
        () async {
      controller.reciterIndex = 12;
      await controller.playPages(1, 1); // 1:1 playing, queue 1:1..1:7
      expect(controller.currentAyah, (1, 1));
      expect(controller.isPlaying, isTrue);

      // The next play's load is slow (weak internet): the old file
      // "completes" while the new ayah is still downloading.
      fake.loadDelay = const Duration(milliseconds: 400);
      final playFuture = controller.playAyah(1, 3);
      await settle(100); // mid-load: the new item has NOT started
      expect(controller.isLoading, isTrue);
      fake.player.emitCompleted(); // stale finish from the old file
      await settle(100); // let the stale finish propagate
      await playFuture; // the new ayah's load finishes
      await settle(200);

      expect(controller.currentAyah, (1, 3),
          reason: 'the new ayah plays — the stale finish did not '
              'advance past it or stop it');
      expect(controller.queueIndex, 0);
      expect(controller.isPlaying, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.lastError, isNull);
    });

    test('stop() during a load clears the spinner and plays nothing',
        () async {
      controller.reciterIndex = 12;
      fake.loadDelay = const Duration(milliseconds: 600);
      final playFuture = controller.playAyah(2, 33);
      await settle(100);
      expect(controller.isLoading, isTrue,
          reason: 'the load is in flight');

      await controller.stop();
      expect(controller.isLoading, isFalse,
          reason: 'stop() clears the spinner itself');
      expect(controller.isPlaying, isFalse);

      await playFuture; // the abandoned load bails silently
      await settle(800); // past the delayed load
      expect(controller.isPlaying, isFalse,
          reason: 'no ghost audio after stop');
      expect(controller.isLoading, isFalse);
      expect(controller.lastError, isNull);
    });

    // v13.3 (FIX A): the wall-clock budget is DELETED — a slow
    // download must still complete (stall timeout only, no time
    // limit). A 2 s load that used to trip the 300 ms budget now
    // plays through, with no error and no spinner left behind.
    test('a slow load completes — no wall-clock budget any more',
        () async {
      controller.reciterIndex = 12;
      fake.loadDelay = const Duration(seconds: 2);

      final playFuture = controller.playAyah(2, 33);
      await settle(800); // past the old 300 ms budget
      expect(controller.isLoading, isTrue,
          reason: 'still loading — nothing times out on a clock');
      expect(controller.lastError, isNull);

      await playFuture;
      expect(controller.isPlaying, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.lastError, isNull);
    });
  });

  group('repeat via the real controller path (bug B)', () {
    late AudioPlayerController controller;

    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.loadDelay = Duration.zero;
      fake.resetCounts();
      controller = AudioPlayerController();
      addTearDown(controller.dispose);
    });

    test('setRepeatCount enables repeat; count 1 turns it off', () {
      controller.setRepeatCount(3);
      expect(controller.repeatItem, isTrue,
          reason: 'picking a count IS asking to repeat');
      expect(controller.repeatCount, 3);
      controller.setRepeatCount(1);
      expect(controller.repeatItem, isFalse,
          reason: 'count 1 = play once = repeat off');
      expect(controller.repeatCount, 1);
    });

    test('manual next() cancels repeat immediately', () async {
      controller.setRepeatCount(3);
      controller.toggleRepeatScope();
      await controller.playPages(1, 1);
      expect(controller.repeatItem, isTrue);
      expect(controller.repeatScope, isTrue);

      await controller.next();
      expect(controller.repeatItem, isFalse);
      expect(controller.repeatScope, isFalse,
          reason: 'a manual tap cancels repeat at once');
      expect(controller.currentAyah, (1, 2),
          reason: 'next still moves to the following ayah');
    });

    test('repeat settings survive a new controller (SharedPreferences)',
        () async {
      SharedPreferences.setMockInitialValues({});
      controller.setRepeatCount(5);
      controller.toggleRepeatScope();
      await controller.setSpeed(1.25);
      await settle(300); // let the unawaited persists land

      final restored = AudioPlayerController();
      addTearDown(restored.dispose);
      await restored.restorePlaybackSettings();
      expect(restored.repeatItem, isTrue);
      expect(restored.repeatCount, 5);
      expect(restored.repeatScope, isTrue);
      expect(restored.speed, 1.25);
    });

    test('repeatRemaining counts the play in progress', () async {
      controller.setRepeatCount(3);
      await controller.playWord(2, 33, 1);
      await settle(200);
      expect(controller.isPlaying, isTrue);
      expect(controller.repeatRemaining, 3,
          reason: '3 plays left counting the one in progress');
    });
  });

  group('player sheet + mini bar — remaining-plays line (bug B)', () {
    Future<AudioPlayerController> playingController(
        WidgetTester tester) async {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.loadDelay = Duration.zero;
      fake.resetCounts();
      final c = AudioPlayerController();
      addTearDown(c.dispose);
      c.setRepeatCount(3);
      // Real async inside a widget test needs runAsync: the test
      // zone uses fake async, so a bare Future.delayed never fires
      // (this hung the test run). playWord itself is microtask-based
      // on the fake, but the playerState event needs a real window.
      await tester.runAsync(() => c.playWord(2, 33, 1));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(c.isPlaying, isTrue);
      return c;
    }

    Future<void> pumpSheet(
        WidgetTester tester, AudioPlayerController c) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(0.7),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: AudioPlayerSheet(controller: c, currentPage: 1),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('sheet shows "متبقٍ 3 مرات" while repeating',
        (tester) async {
      final c = await playingController(tester);
      await pumpSheet(tester, c);
      expect(find.text('التكرار: متبقٍ 3 مرات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sheet hides the line once the sequence stops',
        (tester) async {
      final c = await playingController(tester);
      // stop() runs just_audio's platform-activation machinery, which
      // awaits stream events — like playWord above, it needs runAsync
      // in the widget-test fake-async zone (a bare await hangs).
      await tester.runAsync(() => c.stop());
      await tester.pump();
      await pumpSheet(tester, c);
      expect(find.textContaining('متبقٍ'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('word card — استمع للآية button (UX D)', () {
    Future<void> warmUntilLoaded(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
        if (i >= 4 &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      // The word card is a bottom sheet: its slide-in animation only
      // advances on pumped fake time (v13.6) — settle it so the bar
      // is on-screen before tapping.
      await tester.pumpAndSettle();
    }

    testWidgets('the ayah button calls onPlayAyah and closes the card',
        (tester) async {
      final playedAyahs = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showWordCard(
                  context: context,
                  surah: 3,
                  verse: 7,
                  wordIndex: 7,
                  audioController: AudioPlayerController(),
                  onPlayWord: (_) {},
                  onRepeatWord: (_) {},
                  onPlayAyah: () => playedAyahs.add((3, 7)),
                  onContinueFromAyah: () {},
                  onGoToLastReading: () {},
                  onOpenNotes: () {},
                  onOpenTafsir: () {},
                  onOpenReciterPicker: () {},
                  onOpenPlaybackSettings: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await warmUntilLoaded(tester);

      expect(find.text('الآية'), findsOneWidget,
          reason: 'the ayah-listen action is visible from any word tap');
      await tester.tap(find.byKey(const ValueKey('playAyahButton')));
      // The sheet pops with an exit animation — settle it before
      // asserting it is gone (v13.6: the card is a bottom sheet).
      await tester.pumpAndSettle();

      expect(playedAyahs, [(3, 7)]);
      expect(find.byType(WordCard), findsNothing,
          reason: 'the card closes so the mini bar is visible');
      expect(tester.takeException(), isNull);
    });
  });

  group('QCF playback highlight + long-press (bugs C + UX D)', () {
    // The reader's light theme, with a header stand-in: the package
    // header contains an InkWell, which cannot find a Material
    // ancestor inside a WidgetSpan placeholder in debug tests.
    QcfThemeData testTheme() => QcfThemeData(
          pageBackgroundColor: const Color(0xFFFAF6EE),
          verseTextColor: const Color(0xFF1A1A1A),
          verseNumberColor: const Color(0xFF8A723D),
          basmalaColor: const Color(0xFF1A1A1A),
          headerTextColor: const Color(0xFF1A1A1A),
          verseHeight: 2.1,
          customHeaderBuilder: (_) => Container(
            width: double.infinity,
            height: 39,
            color: const Color(0xFFFAF6EE),
          ),
        );

    Future<void> pumpPage(
      WidgetTester tester, {
      int? playingSurah,
      int? playingVerse,
      int? playingWordIndex,
      bool playingActive = false,
      void Function(int, int, int)? onWordTap,
      void Function(int, int, int)? onWordLongPress,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            minTextAdapt: true,
            builder: (_, __) => Scaffold(
              body: NoorQcfPage(
                pageNumber: 1,
                theme: testTheme(),
                playingSurah: playingSurah,
                playingVerse: playingVerse,
                playingWordIndex: playingWordIndex,
                playingActive: playingActive,
                onWordTap: onWordTap,
                onWordLongPress: onWordLongPress,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    List<TextSpan> allSpans(WidgetTester tester) {
      final out = <TextSpan>[];
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          out.add(s);
          s.children?.forEach(walk);
        }
      }

      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        walk(rt.text);
      }
      return out;
    }

    testWidgets('playing ayah tinted, playing word stronger + coloured',
        (tester) async {
      // Fatiha 1:1 has 4 words: word 0 is the playing word, the
      // other 3 carry the ayah tint.
      await pumpPage(tester,
          playingSurah: 1,
          playingVerse: 1,
          playingWordIndex: 0,
          playingActive: true);
      final spans = allSpans(tester);
      final wordBg = const Color(0xFFFFD54D).withValues(alpha: 0.75);
      final ayahBg = const Color(0xFFFFE082).withValues(alpha: 0.45);
      final wordSpans = spans
          .where((s) => s.style?.backgroundColor == wordBg)
          .toList();
      final ayahSpans = spans
          .where((s) => s.style?.backgroundColor == ayahBg)
          .toList();
      expect(wordSpans.length, 1,
          reason: 'exactly one span is the playing word');
      expect(wordSpans.single.style?.color, const Color(0xFF7A4A00));
      expect(ayahSpans.length, 3,
          reason: 'the other 3 words of the ayah carry the tint');
      expect(tester.takeException(), isNull);
    });

    testWidgets('highlight clears when not playing', (tester) async {
      await pumpPage(tester,
          playingSurah: 1,
          playingVerse: 1,
          playingWordIndex: 0,
          playingActive: false);
      final spans = allSpans(tester);
      final wordBg = const Color(0xFFFFD54D).withValues(alpha: 0.75);
      final ayahBg = const Color(0xFFFFE082).withValues(alpha: 0.45);
      expect(
          spans.where((s) =>
              s.style?.backgroundColor == wordBg ||
              s.style?.backgroundColor == ayahBg),
          isEmpty,
          reason: 'stop / pause clears both the ayah tint and the word');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ayah scope (no word) tints the whole ayah', (tester) async {
      await pumpPage(tester,
          playingSurah: 1, playingVerse: 2, playingActive: true);
      final spans = allSpans(tester);
      final ayahBg = const Color(0xFFFFE082).withValues(alpha: 0.45);
      expect(spans.where((s) => s.style?.backgroundColor == ayahBg).length,
          4,
          reason: '1:2 has 4 words, all tinted, none word-coloured');
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap = word, long-press = its ayah (separate gestures)',
        (tester) async {
      final tapped = <(int, int, int)>[];
      final longPressed = <(int, int, int)>[];
      await pumpPage(tester,
          onWordTap: (s, v, w) => tapped.add((s, v, w)),
          onWordLongPress: (s, v, w) => longPressed.add((s, v, w)));
      final spans = allSpans(tester);

      // The first tap span with text is word 0 of 1:1.
      final tapSpan = spans.firstWhere((s) =>
          s.text != null &&
          s.text!.isNotEmpty &&
          s.recognizer is TapGestureRecognizer);
      (tapSpan.recognizer as TapGestureRecognizer).onTap!();
      expect(tapped, [(1, 1, 0)]);

      // The outer long-press span wraps the word span (no text of
      // its own, children hold the word).
      final lpSpan = spans.firstWhere(
          (s) => s.recognizer is LongPressGestureRecognizer);
      (lpSpan.recognizer as LongPressGestureRecognizer).onLongPress!();
      expect(longPressed, [(1, 1, 0)]);
      expect(tester.takeException(), isNull);
    });
  });
}
