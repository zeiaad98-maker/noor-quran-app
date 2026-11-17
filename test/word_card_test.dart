import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/tafsir_downloads.dart';
import 'package:noor_quran/data/word_meanings.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';
import 'package:noor_quran/widgets/ayah_action_sheet.dart';
import 'package:noor_quran/widgets/mini_audio_bar.dart';
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

  group('word card at 411dp (Aal-Imran 3:7, word 8 مُّحْكَمَاتٌ)', () {
    late List<int> playedWords;

    Future<void> openCard(WidgetTester tester) async {
      playedWords = <int>[];
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
                  onPlayWord: playedWords.add,
                  onPlayAyah: () {},
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

    testWidgets('small card: word + meaning, fits 411dp, Arabic counter',
        (tester) async {
      set411(tester);
      await openCard(tester);

      // The card itself sits fully inside the screen.
      expectFullyVisible(tester, find.byType(WordCard));
      // Word big in green + its real bundled meaning right under it.
      // (The displayed word is the QCF spelling from the page:
      // dagger alef ٰ and ۡ — the same glyphs the Mushaf shows.)
      expect(find.text('مُّحۡكَمَٰتٌ'), findsOneWidget);
      expect(find.textContaining('وَاضِحَاتُ'), findsOneWidget);
      // NO tabs, NO full ayah under the word.
      expect(find.text('الكلمة'), findsNothing);
      expect(find.text('الآية'), findsNothing);
      expect(find.text('علوم السورة'), findsNothing);
      expect(find.text(quran.getVerse(3, 7)), findsNothing);
      // Toolbar + counter (Arabic-Indic digits, never "8 / 46").
      for (final label in ['استمع', 'صرف', 'إعراب']) {
        expectFullyVisible(tester, find.text(label));
      }
      expect(find.text('الكلمة ٨ من ٤٦'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('صرف shows the parsed fields, إعراب the morph text',
        (tester) async {
      set411(tester);
      await openCard(tester);

      await tester.tap(find.text('صرف'));
      await tester.pump();
      expect(find.text('حكم'), findsOneWidget);
      // The singular row shows مُحْكَمَة (diacritic order follows
      // the QCF word, so match on the stable substring).
      expect(find.textContaining('حْكَمَة'), findsOneWidget);
      expect(find.textContaining('جمع مؤنث سالم'), findsOneWidget);

      await tester.tap(find.text('إعراب'));
      await tester.pump();
      expect(
        find.text(
            'اسم مفعول مرفوع، جمع مؤنث، نعت، نكرة، الجذر (حكم)، الوزن (أَفْعَلَ)'),
        findsOneWidget,
      );
      expect(find.textContaining('الإعراب هنا مبسّط'), findsOneWidget);

      // The pill returns to المعنى.
      await tester.tap(find.byKey(const ValueKey('modePill')));
      await tester.pump();
      expect(find.textContaining('وَاضِحَاتُ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('استمع plays the word and closes the card',
        (tester) async {
      set411(tester);
      await openCard(tester);

      await tester.tap(find.text('استمع'));
      await tester.pumpAndSettle();
      expect(playedWords, [7]);
      expect(find.byType(WordCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('prev/next move within the ayah and update the counter',
        (tester) async {
      set411(tester);
      await openCard(tester);

      await tester.tap(find.byTooltip('الكلمة التالية'));
      await warmUntilLoaded(tester);
      expect(find.text('الكلمة ٩ من ٤٦'), findsOneWidget);
      await tester.tap(find.byTooltip('الكلمة السابقة'));
      await warmUntilLoaded(tester);
      expect(find.text('الكلمة ٨ من ٤٦'), findsOneWidget);
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

  group('mini audio bar', () {
    late AudioPlayerController controller;
    late bool closed;

    setUp(() {
      controller = AudioPlayerController();
      closed = false;
    });

    Future<void> pumpBar(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniAudioBar(
              controller: controller,
              onClose: () => closed = true,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('all controls present, no loading label when idle',
        (tester) async {
      set411(tester);
      await pumpBar(tester);

      expect(find.byTooltip('السابق'), findsOneWidget);
      expect(find.byTooltip('التالي'), findsOneWidget);
      expect(find.byTooltip('تكرار العنصر الحالي'), findsOneWidget);
      expect(find.byTooltip('إغلاق وإيقاف الصوت'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.text('جارٍ تحميل الكلمة…'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading: label shown, play button stays green',
        (tester) async {
      set411(tester);
      await pumpBar(tester);

      controller.isLoading = true;
      controller.notifyListeners();
      await tester.pump();

      expect(find.text('جارٍ تحميل الكلمة…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      // A null onPressed would render the button DISABLED (grey) —
      // the v10 bug. It must stay enabled with a green background.
      expect(button.onPressed, isNotNull);
      expect(
        button.style?.backgroundColor?.resolve({}),
        const Color(0xFF0D6E52),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('repeat toggles, X calls onClose', (tester) async {
      set411(tester);
      await pumpBar(tester);

      expect(controller.repeatItem, isFalse);
      await tester.tap(find.byTooltip('تكرار العنصر الحالي'));
      await tester.pump();
      expect(controller.repeatItem, isTrue);

      await tester.tap(find.byTooltip('إغلاق وإيقاف الصوت'));
      await tester.pump();
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('play tap with an empty queue is a safe no-op',
        (tester) async {
      set411(tester);
      await pumpBar(tester);

      // togglePlayPause returns at once with an empty queue — no
      // platform channel is touched, so this runs in flutter_test.
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
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
