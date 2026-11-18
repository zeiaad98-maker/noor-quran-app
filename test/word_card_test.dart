import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/tafsir_downloads.dart';
import 'package:noor_quran/data/word_meanings.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';
import 'package:noor_quran/widgets/ayah_action_sheet.dart';
import 'package:noor_quran/widgets/word_card.dart';

/// v12 word card + tafsir card + chip fix, pinned at a 411dp-wide
/// screen (the user's phone width).
///
/// The v10/v11 tabbed popup is GONE: tap a word → one small card
/// (word + meaning, toolbar swaps المعنى/صرف/إعراب INSIDE the card);
/// tap the verse-end number ۝ → the tafsir card. No tabs anywhere.
///
/// Real audio playback is NOT tested here: just_audio needs a real
/// device/platform channel. Everything around it is pinned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Amiri font is fetched at runtime in the app; in tests there
  // is no font-server guarantee — a failed fetch surfaces as a test
  // exception in whichever test runs next (flaky). Never hit the
  // network here; the fallback font is fine for layout assertions.
  GoogleFonts.config.allowRuntimeFetching = false;

  /// 411dp logical width, the user's phone.
  void set411(WidgetTester tester) {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The card's RenderBox must sit fully inside the 411dp screen.
  void expectFullyVisible(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(0.0),
        reason: '$finder cut off at the left edge');
    expect(rect.right, lessThanOrEqualTo(411.0),
        reason: '$finder cut off at the right edge');
  }

  /// The card loads its data from rootBundle in initState. Those
  /// loads only complete when a pump follows a real-async window:
  /// alternate short real-async windows with pumps until the
  /// spinner is gone (same pattern as the old popup tests).
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

  group('sarf parsing (pure)', () {
    test('3:7 word 8 مُّحْكَمَاتٌ: root/type/plural/singular', () {
      const desc =
          'اسم مفعول مرفوع، جمع مؤنث، نعت، نكرة، الجذر (حكم)، الوزن (أَفْعَلَ)';
      final f = parseSarf(desc, 'مُّحْكَمَاتٌ');
      expect(f.root, 'حكم');
      expect(f.type, 'اسم مفعول مرفوع');
      expect(f.plural, 'جمع مؤنث سالم');
      expect(f.singular, 'مُّحْكَمَة');
      expect(f.fullDesc, desc);
    });

    test('broken plural: no singular is guessed', () {
      final f = parseSarf('اسم مرفوع، جمع تكسير، الجذر (كتب)', 'كُتُبٌ');
      expect(f.root, 'كتب');
      expect(f.plural, 'جمع تكسير');
      expect(f.singular, isNull);
    });

    test('no plural, no root: حرف جر', () {
      final f = parseSarf('حرف جر', 'عَلَيْكَ');
      expect(f.root, isNull);
      expect(f.type, 'حرف جر');
      expect(f.plural, isNull);
      expect(f.singular, isNull);
    });

    test('QCF spelling derives the same singular (مُّحۡكَمَٰتٌ)', () {
      const desc =
          'اسم مفعول مرفوع، جمع مؤنث، نعت، نكرة، الجذر (حكم)، الوزن (أَفْعَلَ)';
      final f = parseSarf(desc, 'مُّحۡكَمَٰتٌ');
      expect(f.plural, 'جمع مؤنث سالم');
      // The singular keeps the QCF word's own diacritic order
      // (damma/shadda order differs from the morphology spelling),
      // so compare normalized: محكمة.
      expect(f.singular, isNotNull);
      expect(QuranWordData.normalizeArabic(f.singular!), 'محكمه');
    });

    test('masculine sound plural derives the singular', () {
      final f = parseSarf('اسم مرفوع، جمع مذكر، الجذر (سلم)', 'مُسْلِمُونَ');
      expect(f.plural, 'جمع مذكر سالم');
      expect(f.singular, 'مُسْلِم');
    });

    test('arabicIndic digits', () {
      expect(arabicIndic(8), '٨');
      expect(arabicIndic(46), '٤٦');
      expect(arabicIndic(114), '١١٤');
    });
  });

  group('word card at 411dp — Wahy style (v13.6)', () {
    late List<int> playedWords;
    late List<int> repeatedWords;
    late List<(int, int)> playedAyahs;
    late List<(int, int)> continuedAyahs;
    late int lastReadingTaps;
    late int notesTaps;
    late int tafsirTaps;
    late int reciterPickerTaps;
    late int playbackSettingsTaps;

    setUp(() {
      playedWords = <int>[];
      repeatedWords = <int>[];
      playedAyahs = <(int, int)>[];
      continuedAyahs = <(int, int)>[];
      lastReadingTaps = 0;
      notesTaps = 0;
      tafsirTaps = 0;
      reciterPickerTaps = 0;
      playbackSettingsTaps = 0;
    });

    Future<void> openCard(
      WidgetTester tester, {
      int surah = 3,
      int verse = 7,
      int wordIndex = 7,
    }) async {
      // The card loads bookmark/note marks from prefs.
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
                  audioController: AudioPlayerController(),
                  onPlayWord: playedWords.add,
                  onRepeatWord: repeatedWords.add,
                  onPlayAyah: () => playedAyahs.add((surah, verse)),
                  onContinueFromAyah: () =>
                      continuedAyahs.add((surah, verse)),
                  onGoToLastReading: () => lastReadingTaps++,
                  onOpenNotes: () => notesTaps++,
                  onOpenTafsir: () => tafsirTaps++,
                  onOpenReciterPicker: () => reciterPickerTaps++,
                  onOpenPlaybackSettings: () => playbackSettingsTaps++,
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

    testWidgets('Wahy layout: ayah header (blue word) + 4 tabs + buttons',
        (tester) async {
      set411(tester);
      await openCard(tester);

      expectFullyVisible(tester, find.byType(WordCard));
      // Ayah header: the whole 3:7, the tapped word in blue. (The
      // header also holds the medallion's own RichText, so match the
      // ayah RichText by its content, not by type alone; compare
      // normalized — the header's QCF spelling and the reader's word
      // can differ in diacritic order.)
      final headerRich = find.descendant(
        of: find.byKey(const ValueKey('ayahHeader')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text is TextSpan &&
              (w.text as TextSpan).children?.any((s) =>
                      s is TextSpan &&
                      s.text != null &&
                      QuranWordData.normalizeArabic(s.text!) ==
                          QuranWordData.normalizeArabic('مُّحۡكَمَٰتٌ') &&
                      s.style?.color == const Color(0xFF2E7FD1)) ==
                  true,
        ),
      );
      expect(headerRich, findsOneWidget);
      // The verse-number medallion (٧) — the header's only Text.
      final medallion = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('ayahHeader')),
        matching: find.byType(Text),
      ));
      expect(medallion.data, '٧');
      // Meaning visible at once (v13.5 bug: it hid behind the audio
      // spinner) — the مخلوف gloss for «آيَاتٌ مُّحْكَمَاتٌ».
      expect(find.textContaining('واضحات لا احتمال فيها ولا اشباه'),
          findsOneWidget);
      // The 4 tabs.
      for (final label in ['المعنى', 'التصريف', 'الإعراب', 'القراءات']) {
        expect(find.text(label), findsOneWidget);
      }
      // Right column + rows below: every button present.
      for (final key in [
        'playWordButton',
        'repeatWordButton',
        'wordDetailsButton',
        'wordSettingsButton',
        'bookmarkButton',
        'lastReadingButton',
        'notesButton',
        'tafsirButton',
        'playAyahButton',
        'continueButton',
        'reciterButton',
        'playbackSettingsButton',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      // Reciter pill shows the current reciter (default الحصري here).
      expect(find.text('محمود الحصري'), findsOneWidget);
      // NO old layout: no toolbar labels, no counter, no mode pill.
      for (final label in ['استمع', 'فاصل', 'تلوين', 'تعليقات', 'المزيد']) {
        expect(find.text(label), findsNothing);
      }
      expect(find.textContaining('الكلمة ٨ من'), findsNothing);
      expect(find.byKey(const ValueKey('modePill')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tabs switch: التصريف fields, الإعراب morph + note, '
        'القراءات honest empty for 3:7', (tester) async {
      set411(tester);
      await openCard(tester);

      await tester.tap(find.byKey(const ValueKey('tabSarf')));
      await tester.pump();
      expect(find.text('حكم'), findsOneWidget);
      expect(find.textContaining('جمع مؤنث سالم'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tabIrab')));
      await tester.pump();
      expect(
        find.text(
            'اسم مفعول مرفوع، جمع مؤنث، نعت، نكرة، الجذر (حكم)، الوزن (أَفْعَلَ)'),
        findsOneWidget,
      );
      expect(find.textContaining('الإعراب هنا مبسّط'), findsOneWidget);

      // 3:7 has no qiraat variant in the bundled data — the tab says
      // so honestly instead of inventing one.
      await tester.tap(find.byKey(const ValueKey('tabQiraat')));
      await tester.pump();
      expect(find.textContaining('لا توجد قراءات مختلفة لهذه الآية'),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tabMeaning')));
      await tester.pump();
      expect(find.textContaining('واضحات لا احتمال فيها ولا اشباه'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('القراءات tab: 1:4 shows مَالِكِ / مَلِكِ with readers',
        (tester) async {
      set411(tester);
      await openCard(tester, surah: 1, verse: 4, wordIndex: 0);

      await tester.tap(find.byKey(const ValueKey('tabQiraat')));
      await tester.pump();
      expect(find.textContaining('مَالِكِ'), findsOneWidget);
      expect(find.textContaining('مَلِكِ'), findsOneWidget);
      expect(find.textContaining('قراءة المصحف'), findsOneWidget);
      expect(find.textContaining('ابن عامر'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every button calls its function (no dead buttons)',
        (tester) async {
      set411(tester);
      await openCard(tester);

      // Green ▶ plays the word and keeps the card open.
      await tester.tap(find.byKey(const ValueKey('playWordButton')));
      await tester.pump();
      expect(playedWords, [7]);
      expect(find.byType(WordCard), findsOneWidget);

      // Circled ▶ repeats the word.
      await tester.tap(find.byKey(const ValueKey('repeatWordButton')));
      await tester.pump();
      expect(repeatedWords, [7]);

      // Magnifier opens the word-details sheet; a tap above the
      // sheet dismisses it.
      await tester.tap(find.byKey(const ValueKey('wordDetailsButton')));
      await tester.pumpAndSettle();
      expect(find.text('المعجم (مفردات الراغب)'), findsOneWidget);
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();
      expect(find.text('المعجم (مفردات الراغب)'), findsNothing);
      expect(find.byType(WordCard), findsOneWidget);

      // Gear opens the word-settings sheet.
      await tester.tap(find.byKey(const ValueKey('wordSettingsButton')));
      await tester.pumpAndSettle();
      expect(find.text('إعدادات الكلمة'), findsOneWidget);
      expect(find.text('تشغيل صوت الكلمة تلقائياً عند الضغط عليها'),
          findsOneWidget);
      await tester.tapAt(const Offset(200, 50));
      await tester.pumpAndSettle();
      expect(find.byType(WordCard), findsOneWidget);

      // Bookmark toggles (the ayah was not bookmarked).
      await tester.tap(find.byKey(const ValueKey('bookmarkButton')));
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('bookmarkButton')),
          matching: find.byIcon(Icons.bookmark),
        ),
        findsOneWidget,
      );

      // The closing buttons each fire their callback and close the
      // card. The card is already open after the bookmark tap, so
      // the first closer taps it directly; later ones reopen it.
      Future<void> tapCloser(String key) async {
        if (find.byType(WordCard).evaluate().isEmpty) {
          await openCard(tester);
        }
        // The ملاحظة/تفاسير row sits at the bottom of the scrollable
        // middle: with a long meaning it is just below the fold until
        // scrolled (same as in the real app) — scroll it into view.
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          100,
        );
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(find.byType(WordCard), findsNothing);
      }

      await tapCloser('playAyahButton');
      expect(playedAyahs, [(3, 7)]);

      await tapCloser('continueButton');
      expect(continuedAyahs, [(3, 7)]);

      await tapCloser('lastReadingButton');
      expect(lastReadingTaps, 1);

      await tapCloser('notesButton');
      expect(notesTaps, 1);

      await tapCloser('tafsirButton');
      expect(tafsirTaps, 1);

      await tapCloser('reciterButton');
      expect(reciterPickerTaps, 1);

      await tapCloser('playbackSettingsButton');
      expect(playbackSettingsTaps, 1);

      expect(tester.takeException(), isNull);
    });
  });

  group('tafsir card + selector', () {
    late TafsirService service;
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('tafsir-test');
      service = TafsirService(
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await service.init();
    });

    tearDown(() async {
      service.dispose();
      await tempDir.delete(recursive: true);
    });

    Future<void> openCard(
      WidgetTester tester, {
      int surah = 3,
      int verse = 7,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showTafsirCard(
                  context: context,
                  surah: surah,
                  verse: verse,
                  tafsirService: service,
                  onPlayAyah: () {},
                  onOpenNotes: () {},
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

    testWidgets('3:7: ayah in cream box + التفسير الميسر verbatim',
        (tester) async {
      set411(tester);
      await openCard(tester);

      expectFullyVisible(tester, find.byType(TafsirCard));
      expect(find.text(quran.getVerse(3, 7)), findsOneWidget);
      expect(
        find.textContaining('هو وحده الذي أنزل عليك القرآن'),
        findsOneWidget,
      );
      expect(find.text('التفسير الميسر'), findsOneWidget);
      expect(find.text('استمع للآية'), findsOneWidget);
      expect(find.text('ملاحظاتي'), findsOneWidget);
      // 3:7 has no asbab entry — no section shown (not invented).
      expect(find.text('أسباب النزول'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2:89: أسباب النزول section appears when present',
        (tester) async {
      set411(tester);
      await openCard(tester, surah: 2, verse: 89);

      expect(find.text('أسباب النزول'), findsOneWidget);
      expect(find.textContaining('عن ابن عباس'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'selector: 6 rows, الميسر مثبّت, السعدي + السراج تحميل, '
        'الجلالين + الطبري + ابن كثير غير متوفر بعد (v12)',
        (tester) async {
      set411(tester);
      await openCard(tester);

      await tester.tap(find.text('التفسير الميسر'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      for (final name in [
        'التفسير الميسر',
        'تفسير الجلالين',
        'تفسير السعدي',
        'السراج المنير',
        'تفسير الطبري',
        'تفسير ابن كثير',
      ]) {
        expect(find.text(name), findsWidgets);
      }
      expect(find.text('مثبّت ✓'), findsOneWidget);
      // Only the two tafsirs extracted for v12 offer تحميل.
      expect(find.text('تحميل'), findsNWidgets(2));
      // The three deferred to v13 say so honestly, with no button.
      expect(find.text('غير متوفر بعد'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('ayah-sheet chips use true word indices (v12 fix)', () {
    test('2:181: map has 14 true words, morphology only 13 entries',
        () async {
      expect(buildQcfWordMap(2, 181).wordCount, 14);
      expect((await QuranWordData.wordsForAyah(2, 181)).length, 13);
      // The merged entry is بَعۡدَ مَا; the true words split it.
      final words =
          buildQcfWordMap(2, 181).words.map((w) => w.text).toList();
      expect(words[2], 'بَعۡدَ');
      expect(words[3], 'مَا');
    });

    test('37:130: map has 4 true words, morphology 3 entries', () async {
      expect(buildQcfWordMap(37, 130).wordCount, 4);
      expect((await QuranWordData.wordsForAyah(37, 130)).length, 3);
    });

    testWidgets('2:181 chips: 14 separate chips, بَعۡدَ and مَا apart',
        (tester) async {
      set411(tester);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AyahActionSheet(
                surahNumber: 2,
                verseNumber: 181,
                pageNumber: 27,
                onPlayAyah: () {},
                onPlayWord: (_) {},
                onOpenNotesScreen: () {},
                onNoteChanged: () {},
              ),
            ),
          ),
        ),
      );
      await warmUntilLoaded(tester);

      // The sheet has other OutlinedButtons (note editor) — count
      // only the word chips, which live in the Wrap.
      final chips = find.descendant(
        of: find.byType(Wrap),
        matching: find.byType(OutlinedButton),
      );
      expect(chips, findsNWidgets(14));
      expect(find.text('بَعۡدَ'), findsOneWidget);
      expect(find.text('مَا'), findsOneWidget);
      expect(find.text('بَعۡدَ مَا'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('full audio sheet loading state', () {
    testWidgets('play button never disabled while loading', (tester) async {
      set411(tester);
      final controller = AudioPlayerController();
      controller.isLoading = true;

      // The test font renders every Arabic glyph at full em width,
      // so the sheet's text rows (page pickers, repeat pill) measure
      // ~40% wider than in the real Amiri font and would overflow
      // at 411dp — on the user's phone they fit (see his v10 sheet
      // screenshot). Scale text to ~real widths so this test pins
      // the loading-state wiring, not the test font.
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

      expect(find.text('جارٍ التحميل…'), findsOneWidget);
      final playButton = tester.widget<ElevatedButton>(
        find.descendant(
          of: find.byTooltip('تشغيل'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(playButton.onPressed, isNotNull);
      expect(
        playButton.style?.backgroundColor?.resolve({}),
        const Color(0xFF0D6E52),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
