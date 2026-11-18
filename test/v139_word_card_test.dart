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
///    shows. v13.9 fixed it with verified glosses from التفسير الميسر
///    in the additions file; v13.11 supersedes that: the Tafsir
///    Center meanings cover EVERY word, so the المعنى tab always
///    shows a real meaning (with the small credit line) and the
///    honest "no meaning" case no longer occurs.
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

  group('meaning glosses from the Tafsir Center (v13.11)', () {
    test('15:11 يَسْتَهْزِئُونَ → يستخفون ويحقرون. (tafsircenter)',
        () async {
      final words = buildQcfWordMap(15, 11).words;
      final idx = words.indexWhere((w) =>
          QuranWordData.normalizeArabic(w.lookupText) == 'يستهزءون');
      expect(idx, isNot(-1));
      final lookup = words[idx].lookupText;
      expect(await QuranWordData.wordGloss(15, 11, lookup),
          'يستخفون ويحقرون.');
      expect(await QuranWordData.glossSourceForWord(15, 11, lookup),
          'tafsircenter');
    });

    test('15:12 كَذَٰلِكَ → أي مثل ذلك. (tafsircenter)', () async {
      final words = buildQcfWordMap(15, 12).words;
      final idx = words.indexWhere((w) =>
          QuranWordData.normalizeArabic(w.lookupText) == 'كذالك');
      expect(idx, isNot(-1));
      final lookup = words[idx].lookupText;
      expect(await QuranWordData.wordGloss(15, 12, lookup),
          'أي مثل ذلك. وذلك: اسم إشارة للمفرد المذكر البعيد.');
      expect(await QuranWordData.glossSourceForWord(15, 12, lookup),
          'tafsircenter');
    });

    test('15:11 وَمَا has a Tafsir Center meaning too', () async {
      final words = buildQcfWordMap(15, 11).words;
      final idx = words.indexWhere(
          (w) => QuranWordData.normalizeArabic(w.lookupText) == 'وما');
      expect(idx, isNot(-1));
      expect(await QuranWordData.glossSourceForWord(
          15, 11, words[idx].lookupText), 'tafsircenter');
      expect(await QuranWordData.wordGloss(15, 11, words[idx].lookupText),
          'ما: نافية غير عاملة.');
    });

    test('3:7 آيَاتٌ in QCF spelling matches the TC entry (v13.11)',
        () async {
      // Regression: the TC asset spells it ءَايَٰتࣱ (hamza+alef,
      // open fathatan U+08F1) while the reader's QCF text spells it
      // آيَاتٌ (madda, closed dammatan) — normalizeArabic must
      // equate the two, or the card shows the old fallback gloss
      // «كلمة من كلمات القرآن الكريم» instead of the TC meaning.
      final words = buildQcfWordMap(3, 7).words;
      final idx = words.indexWhere((w) =>
          QuranWordData.normalizeArabic(w.lookupText) == 'ايات');
      expect(idx, isNot(-1));
      final lookup = words[idx].lookupText;
      expect(await QuranWordData.glossSourceForWord(3, 7, lookup),
          'tafsircenter');
      expect(await QuranWordData.wordGloss(3, 7, lookup),
          'الآية من كتاب الله، هي: طائفةٌ من القرآن يتصل بعضها ببعض إلى انقطاعها، طويلةً كانت أو قصيرة.');
    });
  });

  group('word card — المعنى tab + الصفحة button (v13.9, v13.11)', () {
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
      expect(find.text('يستخفون ويحقرون.'), findsOneWidget);
      // v13.11: the small credit line under a Tafsir Center meaning.
      expect(
          find.text('المصدر: مركز تفسير للدراسات القرآنية — tafsir.net'),
          findsOneWidget);
      // The morphology text must NOT appear in the meaning tab.
      expect(find.textContaining('فعل مضارع مرفوع'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '15:11 وَمَا: المعنى shows a meaning, الإعراب shows the TC i\'rab',
        (tester) async {
      set411(tester);
      final idx = wordIndexOf(15, 11, 'وما');
      expect(idx, isNot(-1));
      await openCard(tester, wordIndex: idx);
      // v13.11: every word has a meaning now — the honest "no
      // meaning" line no longer appears.
      expect(
          find.text('لا يوجد معنى مختصر لهذه الكلمة في المصادر المتوفرة.'),
          findsNothing);
      expect(find.text('ما: نافية غير عاملة.'), findsOneWidget);
      expect(
          find.text('المصدر: مركز تفسير للدراسات القرآنية — tafsir.net'),
          findsOneWidget);
      // The morphology text lives in the الإعراب tab, not here.
      expect(find.text('حرف نفي'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tabIrab')));
      await tester.pumpAndSettle();
      // v13.11: the الإعراب tab shows the Tafsir Center per-word
      // i'rab in full (with the small credit line), not the
      // simplified morphology description.
      expect(find.textContaining('حَرْفُ نَفْيٍ'), findsOneWidget);
      expect(
          find.text('المصدر: مركز تفسير للدراسات القرآنية — tafsir.net'),
          findsOneWidget);
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
