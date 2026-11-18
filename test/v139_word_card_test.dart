import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/word_meanings.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';
import 'package:noor_quran/widgets/word_card.dart';

/// v13.9 — the three fixes the user ordered Wed 2026-11-18 after
/// testing v13.8 on his phone:
/// 1. المعنى and الإعراب showed the SAME text (15:11 يَسْتَهْزِئُونَ):
///    no meaning source covered the word, so the gloss fell back to
///    the morphology description — which is also what the الإعراب tab
///    shows. Now the المعنى tab says honestly that no short meaning
///    exists (and points at تفاسير), and the two words get verified
///    glosses from التفسير الميسر in the additions file.
/// 2. The player sheet's scope tabs sat below the playback controls,
///    under the fold — the user could not find the الصفحة tab. Now the
///    tabs are first in the sheet, visible on open.
/// 3. A الصفحة play button in the word card's bottom bar (next to
///    الآية / استمرار): one tap opens the player sheet on the page
///    scope and plays the whole current page. ملاحظة stays — it is the
///    notes entry, not a spare slot.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('meaning glosses from التفسير الميسر additions (v13.9)', () {
    test('15:11 يَسْتَهْزِئُونَ → يسخرون به. (addition, not morphology)',
        () async {
      final words = buildQcfWordMap(15, 11).words;
      final idx = words.indexWhere((w) =>
          QuranWordData.normalizeArabic(w.lookupText) == 'يستهزءون');
      expect(idx, isNot(-1));
      final lookup = words[idx].lookupText;
      expect(await QuranWordData.wordGloss(15, 11, lookup), 'يسخرون به.');
      expect(await QuranWordData.glossSourceForWord(15, 11, lookup),
          'addition');
    });

    test('15:12 كَذَٰلِكَ → مثل ذلك. (addition)', () async {
      final words = buildQcfWordMap(15, 12).words;
      final idx = words.indexWhere((w) =>
          QuranWordData.normalizeArabic(w.lookupText) == 'كذالك');
      expect(idx, isNot(-1));
      final lookup = words[idx].lookupText;
      expect(await QuranWordData.wordGloss(15, 12, lookup), 'مثل ذلك.');
      expect(await QuranWordData.glossSourceForWord(15, 12, lookup),
          'addition');
    });

    test('15:11 وَمَا has no meaning source — morphology only', () async {
      final words = buildQcfWordMap(15, 11).words;
      final idx = words.indexWhere(
          (w) => QuranWordData.normalizeArabic(w.lookupText) == 'وما');
      expect(idx, isNot(-1));
      expect(await QuranWordData.glossSourceForWord(
          15, 11, words[idx].lookupText), 'morph');
    });
  });

  group('word card — honest المعنى tab + الصفحة button (v13.9)', () {
    /// 411dp logical width, the user's phone.
    void set411(WidgetTester tester) {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// Same warm-up as word_card_test: the card loads its data from
    /// rootBundle in initState; alternate real-async windows with
    /// pumps until the spinner is gone.
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
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    late int pageTaps;

    Future<void> openCard(
      WidgetTester tester, {
      int surah = 15,
      int verse = 11,
      int wordIndex = 7,
    }) async {
      pageTaps = 0;
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showWordCard(
                  context: context,
                  surah: surah,
                  verse: verse,
                  wordIndex: wordIndex,
                  pageNumber: 262,
                  audioController: AudioPlayerController(),
                  onPlayWord: (_) {},
                  onRepeatWord: (_) {},
                  onPlayAyah: () {},
                  onPlayPage: () => pageTaps++,
                  onContinueFromAyah: () {},
                  onGoToLastReading: () {},
                  onOpenNotesScreen: () {},
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
    }

    int wordIndexOf(int surah, int verse, String normalized) {
      final words = buildQcfWordMap(surah, verse).words;
      return words.indexWhere(
          (w) => QuranWordData.normalizeArabic(w.lookupText) == normalized);
    }

    testWidgets('15:11 يَسْتَهْزِئُونَ: المعنى shows the verified meaning',
        (tester) async {
      set411(tester);
      final idx = wordIndexOf(15, 11, 'يستهزءون');
      expect(idx, isNot(-1));
      await openCard(tester, wordIndex: idx);
      expect(find.text('يسخرون به.'), findsOneWidget);
      // The morphology text must NOT appear in the meaning tab.
      expect(find.textContaining('فعل مضارع مرفوع'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '15:11 وَمَا: المعنى is honest, الإعراب keeps the morph text',
        (tester) async {
      set411(tester);
      final idx = wordIndexOf(15, 11, 'وما');
      expect(idx, isNot(-1));
      await openCard(tester, wordIndex: idx);
      expect(
          find.text('لا يوجد معنى مختصر لهذه الكلمة في المصادر المتوفرة.'),
          findsOneWidget);
      expect(find.textContaining('تفاسير'), findsWidgets);
      // The morphology text lives in the الإعراب tab, not here.
      expect(find.text('حرف نفي'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tabIrab')));
      await tester.pumpAndSettle();
      expect(find.text('حرف نفي'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('playPageButton fires and closes the card',
        (tester) async {
      set411(tester);
      final idx = wordIndexOf(15, 11, 'يستهزءون');
      expect(idx, isNot(-1));
      await openCard(tester, wordIndex: idx);
      expect(find.byKey(const ValueKey('playPageButton')), findsOneWidget);
      await tester.ensureVisible(
          find.byKey(const ValueKey('playPageButton')));
      await tester.tap(find.byKey(const ValueKey('playPageButton')));
      await tester.pumpAndSettle();
      expect(pageTaps, 1);
      expect(find.byType(WordCard), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('player sheet — scope tabs first (v13.9)', () {
    testWidgets('tabs render above the playback controls',
        (tester) async {
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioPlayerSheet(controller: controller, currentPage: 262),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['الكلمة', 'الآية', 'الصفحة', 'السورة']) {
        expect(find.text(label), findsOneWidget);
      }
      // The tabs sit above the big play button in the top row: their
      // top edge is higher on screen than the play button's top edge.
      // Two play_arrow icons exist in the sheet (top row + scope
      // body); _topRow precedes the body in the tree, so .first is
      // the top-row play button.
      final tabsTop = tester.getTopLeft(find.text('الصفحة')).dy;
      final playTop = tester
          .getTopLeft(find.byIcon(Icons.play_arrow).first)
          .dy;
      expect(tabsTop, lessThan(playTop));
      expect(tester.takeException(), isNull);
    });
  });
}
