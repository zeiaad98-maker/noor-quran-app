import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';
import 'package:noor_quran/widgets/mini_audio_bar.dart';
import 'package:noor_quran/widgets/word_popup.dart';

/// v11 popup + audio-UI fixes, pinned at a 411dp-wide screen
/// (the user's phone width):
/// * the popup is a SMALL compact card — all 4 scope tabs and all 4
///   green action-bar labels fully visible, no overflow;
/// * the counter reads "الكلمة 4 من 46" (the old "4 / 46" rendered
///   as "46 / 4" under RTL bidi);
/// * المعنى shows the morphology fallback ("حرف جر") for عَلَيْكَ
///   in 3:7, which has no غريب القرآن entry — not the old
///   "no special meaning" note;
/// * استماع calls onPlayWord and closes the popup (the reader shows
///   the mini bar instead of the full sheet);
/// * the mini bar shows its controls, a loading label while
///   isLoading, and a green (never grey/disabled) play button;
/// * the full sheet's play button is never disabled while loading
///   and shows "جارٍ التحميل…" underneath.
///
/// Real audio playback is NOT tested here: just_audio needs a real
/// device/platform channel (setUrl/play hit the missing plugin in
/// flutter_test). Everything around it is pinned: the controller
/// methods the buttons call are exercised only where they return
/// without touching the player (empty queue), and the X button is
/// verified through its onClose callback, not through stop().
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 411dp logical width, the user's phone.
  void set411(WidgetTester tester) {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// The popup's RenderBox must sit fully inside the 411dp screen.
  void expectFullyVisible(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    final rect = tester.getRect(finder);
    expect(rect.left, greaterThanOrEqualTo(0.0),
        reason: '$finder cut off at the left edge');
    expect(rect.right, lessThanOrEqualTo(411.0),
        reason: '$finder cut off at the right edge');
  }

  /// Like [expectFullyVisible] but for labels that appear more than
  /// once (e.g. 'أسماء السورة' is both the content-tab chip and the
  /// content heading): every match must be fully visible.
  void expectAllFullyVisible(WidgetTester tester, Finder finder) {
    expect(finder, findsWidgets);
    for (final element in finder.evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(rect.left, greaterThanOrEqualTo(0.0),
          reason: '$finder cut off at the left edge');
      expect(rect.right, lessThanOrEqualTo(411.0),
          reason: '$finder cut off at the right edge');
    }
  }

  group('compact word popup at 411dp (Aal-Imran 3:7, word 4 عَلَيْكَ)',
      () {
    late AudioPlayerController controller;
    late List<int> playedWords;
    late int wordCount;

    setUp(() {
      controller = AudioPlayerController();
      playedWords = <int>[];
      wordCount = buildQcfWordMap(3, 7).wordCount;
    });

    Future<void> openPopup(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showWordPopup(
                  context: context,
                  surah: 3,
                  verse: 7,
                  wordIndex: 3,
                  audioController: controller,
                  isBookmarked: false,
                  onToggleBookmark: () {},
                  onOpenSettings: () {},
                  onPlayWord: playedWords.add,
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
      // The popup loads its data (meanings / tafsir / asbab / surah
      // info) from rootBundle in initState. Those loads are
      // SEQUENTIAL asset reads, and each one only completes when a
      // pump follows a real-async window: a bare pumpAndSettle
      // spins forever on the loading spinner, and warming the
      // caches in runAsync does NOT help either — a future completed
      // in the real zone never fires its callbacks inside the
      // fake-async test zone. So alternate short real-async windows
      // with pumps until the spinner is gone (3 rounds in practice),
      // then settle the dialog animation.
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
        // Minimum 5 rounds: the word loader (4 sequential files) and
        // the sciences loader (3 sequential files) run concurrently,
        // and the word spinner can clear a round or two before the
        // ayah data (_loadAyahData) has finished — breaking early
        // would leave the الصفحة/علوم السورة tabs still loading.
        if (i >= 4 &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('all scope tabs + all action labels fully visible',
        (tester) async {
      set411(tester);
      await openPopup(tester);

      for (final tab in ['الكلمة', 'الآية', 'الصفحة', 'علوم السورة']) {
        expectFullyVisible(tester, find.text(tab));
      }
      for (final action in ['استماع', 'الإعدادات', 'فاصل', 'تعليق']) {
        expectFullyVisible(tester, find.text(action));
      }
      // Content tabs of the default (الكلمة) scope.
      expectFullyVisible(tester, find.text('المعنى'));
      expectFullyVisible(tester, find.text('الإعراب'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('علوم السورة scope: all 6 content tabs visible',
        (tester) async {
      set411(tester);
      await openPopup(tester);

      await tester.tap(find.text('علوم السورة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final tab in [
        'أسماء السورة',
        'نزول السورة',
        'مقاصد السورة',
        'فضائل السورة',
        'عدد آيات السورة',
        'إحصائيات',
      ]) {
        expectAllFullyVisible(tester, find.text(tab));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('counter reads "الكلمة 4 من N", never "4 / N"',
        (tester) async {
      set411(tester);
      await openPopup(tester);

      expect(find.text('الكلمة 4 من $wordCount'), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('المعنى falls back to the morphology description',
        (tester) async {
      set411(tester);
      await openPopup(tester);

      // عَلَيْكَ has no غريب القرآن entry; its morphology is
      // "حرف جر" — that is the body text now, not the old note.
      expect(find.text('حرف جر'), findsOneWidget);
      expect(find.textContaining('ليس لها معنى خاص'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('استماع plays the word and closes the popup',
        (tester) async {
      set411(tester);
      await openPopup(tester);

      await tester.tap(find.text('استماع'));
      await tester.pumpAndSettle();
      expect(playedWords, [3]);
      expect(find.byType(WordPopup), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Bug I: الصفحة scope is أسباب النزول only — no الترجمات',
        (tester) async {
      set411(tester);
      await openPopup(tester);

      await tester.tap(find.text('الصفحة'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // No translation tab, no translation text, no fetch.
      expect(find.text('الترجمات'), findsNothing);
      expect(find.textContaining('Saheeh'), findsNothing);
      expect(find.textContaining('alquran.cloud'), findsNothing);
      // أسباب النزول is the single content tab (label) + its heading.
      expect(find.text('أسباب النزول'), findsNWidgets(2));
      expect(
        find.text('المصدر: صحيح أسباب النزول — إبراهيم محمد العلي.'),
        findsOneWidget,
      );
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
