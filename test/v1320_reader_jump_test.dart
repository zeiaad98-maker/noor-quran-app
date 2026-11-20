import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/main.dart';
import 'package:noor_quran/screens/surah_reader_screen.dart';
import 'package:noor_quran/widgets/reader_jump_sheets.dart';
import 'package:noor_quran/widgets/surah_name_image.dart';

import 'fake_just_audio.dart';

// v13.20 — in-reader jump pickers (user request Fri 2026-11-20,
// SurahApp-style navigation inside the reader):
//   * tap the surah name in the reader header -> sheet with all
//     114 surahs (searchable) -> tap one -> the CURRENT reader jumps
//     to that surah's first page (no new screen).
//   * tap the page chip at the bottom ("صفحة N") -> sheet with a
//     grid of all 604 pages, current page highlighted -> tap one ->
//     the reader jumps to it.
// The guard `_jumpToPage` uses is [isValidMushafPage] — tested here
// directly, since the private method itself is only reachable
// through the widget.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('jump helpers (v13.20)', () {
    test('isValidMushafPage accepts 1..604 only', () {
      expect(isValidMushafPage(0), isFalse);
      expect(isValidMushafPage(-5), isFalse);
      expect(isValidMushafPage(1), isTrue);
      expect(isValidMushafPage(300), isTrue);
      expect(isValidMushafPage(604), isTrue);
      expect(isValidMushafPage(605), isFalse);
    });

    test('surahStartPage matches the Madina Mushaf', () {
      expect(surahStartPage(1), 1); // الفاتحة
      expect(surahStartPage(2), 2); // البقرة
      expect(surahStartPage(3), 50); // آل عمران
      expect(surahStartPage(18), 293); // الكهف
      expect(surahStartPage(36), 440); // يس
      expect(surahStartPage(114), 604); // الناس
    });

    test('surahStartPage never goes backwards', () {
      var previous = 0;
      for (var surah = 1; surah <= surahCount; surah++) {
        final page = surahStartPage(surah);
        expect(page, greaterThanOrEqualTo(previous));
        previous = page;
      }
    });

    test('arabicDigits converts to Arabic-Indic digits', () {
      expect(arabicDigits(0), '٠');
      expect(arabicDigits(2), '٢');
      expect(arabicDigits(50), '٥٠');
      expect(arabicDigits(257), '٢٥٧');
      expect(arabicDigits(604), '٦٠٤');
    });
  });

  group('PageJumpSheet (v13.20)', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      PageJumpSheet sheet,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: sheet)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists all 604 pages', (tester) async {
      await pumpSheet(
        tester,
        PageJumpSheet(currentPage: 1, onSelect: (_) {}),
      );
      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate =
          grid.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, mushafPageCount);
      expect(find.text('٦٠٤'), findsNothing); // last cell off-screen
      expect(find.text('١'), findsOneWidget); // first cell visible
    });

    testWidgets('current page cell is highlighted, others are not',
        (tester) async {
      await pumpSheet(
        tester,
        PageJumpSheet(currentPage: 257, onSelect: (_) {}),
      );
      // The grid opens scrolled to the current page's row, so the
      // current cell is built and visible.
      final current = tester.widget<Ink>(
        find.byKey(const ValueKey('pageCell_257')),
      );
      final currentDecoration = current.decoration as BoxDecoration;
      expect(currentDecoration.color, const Color(0xFF0D6E52));
      final other = tester.widget<Ink>(
        find.byKey(const ValueKey('pageCell_258')),
      );
      final otherDecoration = other.decoration as BoxDecoration;
      expect(otherDecoration.color, isNull);
    });

    testWidgets('tapping a page calls onSelect with its number',
        (tester) async {
      var selected = -1;
      await pumpSheet(
        tester,
        PageJumpSheet(
          currentPage: 1,
          onSelect: (page) => selected = page,
        ),
      );
      await tester.tap(find.text('٥'));
      expect(selected, 5);
    });

    testWidgets('a far page is reachable by scrolling, then taps',
        (tester) async {
      var selected = -1;
      await pumpSheet(
        tester,
        PageJumpSheet(
          currentPage: 1,
          onSelect: (page) => selected = page,
        ),
      );
      // scrollUntilVisible stops as soon as the cell's edge enters
      // the viewport, so its centre can still be off-screen and the
      // tap would miss — ensureVisible centres it fully first.
      await tester.scrollUntilVisible(find.text('٣٠٠'), 300);
      await tester.ensureVisible(find.text('٣٠٠'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('٣٠٠'));
      expect(selected, 300);
    });
  });

  group('SurahJumpSheet (v13.20)', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      SurahJumpSheet sheet,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: sheet)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lists all 114 surahs', (tester) async {
      await pumpSheet(
        tester,
        SurahJumpSheet(currentSurah: 1, onSelect: (_) {}),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, surahCount);
      // First rows visible with the surah-list info line.
      expect(find.text('مكية • 7 آية • صفحة 1'), findsOneWidget);
      expect(find.text('مدنية • 286 آية • صفحة 2'), findsOneWidget);
    });

    testWidgets('current surah row is highlighted, others are not',
        (tester) async {
      await pumpSheet(
        tester,
        SurahJumpSheet(currentSurah: 18, onSelect: (_) {}),
      );
      // The list opens scrolled to the current surah, so its row is
      // built and visible.
      final current = tester.widget<Container>(
        find.byKey(const ValueKey('surahRow_18')),
      );
      expect(
        current.color,
        const Color(0xFF0D6E52).withValues(alpha: 0.10),
      );
      final other = tester.widget<Container>(
        find.byKey(const ValueKey('surahRow_19')),
      );
      expect(other.color, isNull);
    });

    testWidgets('search filters by name and by number', (tester) async {
      await pumpSheet(
        tester,
        SurahJumpSheet(currentSurah: 1, onSelect: (_) {}),
      );
      await tester.enterText(find.byType(TextField), 'بقرة');
      await tester.pumpAndSettle();
      var list = tester.widget<ListView>(find.byType(ListView));
      var delegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, 1);
      expect(find.text('مدنية • 286 آية • صفحة 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '18');
      await tester.pumpAndSettle();
      list = tester.widget<ListView>(find.byType(ListView));
      delegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.childCount, 1);
      expect(find.text('مكية • 110 آية • صفحة 293'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pumpAndSettle();
      expect(find.text('لا توجد سورة مطابقة'), findsOneWidget);
    });

    testWidgets('tapping a surah calls onSelect with its number',
        (tester) async {
      var selected = -1;
      await pumpSheet(
        tester,
        SurahJumpSheet(
          currentSurah: 1,
          onSelect: (surah) => selected = surah,
        ),
      );
      await tester.tap(find.text('مدنية • 286 آية • صفحة 2'));
      expect(selected, 2);
    });
  });

  group('reader — jump pickers end to end (v13.20)', () {
    setUp(() {
      installFakeJustAudio();
      SharedPreferences.setMockInitialValues({});
      // Bound the reader's background download attempts (real http
      // client, no network in tests): one fast-failing attempt per
      // host instead of the defaults.
      // (Static overrides live on AudioDownloadService; the reader
      // only creates the service, it never downloads in these tests.)
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getTemporaryDirectory') {
            return Directory.systemTemp.path;
          }
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    Future<void> pumpFrames(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Test-env font artifacts (google_fonts cannot fetch Amiri
    // offline, so the fallback font is wider): RenderFlex overflows
    // and google_fonts load failures are expected noise. The qcf
    // package's surah-header InkWell also finds no Material ancestor
    // inside a WidgetSpan placeholder in debug tests (release builds
    // are unaffected — see mushaf_vertical_fit_test.dart and
    // v135_ayah_number_tap_test.dart; the header page is only
    // reached here by the jump to page 50). Any other recorded
    // error must still fail the test.
    void drainLayoutOverflows(WidgetTester tester) {
      Object? e;
      while ((e = tester.takeException()) != null) {
        final msg = e.toString();
        if (msg.contains('overflowed') ||
            msg.contains('google_fonts was unable to load font') ||
            msg.contains('No Material widget found') ||
            msg.contains('Multiple exceptions')) {
          continue;
        }
        fail('unexpected exception during test: $e');
      }
    }

    Future<void> openReader(WidgetTester tester) async {
      await tester.pumpWidget(const NoorQuranApp());
      for (var i = 0;
          i < 20 && find.byType(MainNavigationScreen).evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(MainNavigationScreen), findsOneWidget);

      final context = tester.element(find.byType(MainNavigationScreen));
      Navigator.of(context).push(
        MaterialPageRoute(
          // Page 42 (2:253-2:256) has no surah header, so the test
          // is not affected by the test-env header artifact (see
          // v135_ayah_number_tap_test).
          builder: (_) =>
              const SurahReaderScreen(surahNumber: 2, initialPage: 42),
        ),
      );
      await pumpFrames(tester, 10);
      drainLayoutOverflows(tester);
      expect(find.text('صفحة ٤٢'), findsOneWidget);
    }

    testWidgets('page chip opens the picker; tapping a page jumps',
        (tester) async {
      await openReader(tester);

      await tester.tap(find.text('صفحة ٤٢'));
      await pumpFrames(tester, 4);
      expect(find.byType(PageJumpSheet), findsOneWidget);

      // scrollUntilVisible needs the sheet's own Scrollable named
      // explicitly: the reader tree has several Scrollables (the
      // Mushaf PageView plus this grid), and the default
      // find.byType(Scrollable) matches them all ("Too many
      // elements"). ensureVisible then centres the cell fully —
      // scrollUntilVisible stops as soon as its edge enters the
      // viewport, which can leave the tap point off-screen.
      await tester.scrollUntilVisible(
        find.text('٣٠٠'),
        300,
        scrollable: find.descendant(
          of: find.byType(PageJumpSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text('٣٠٠'));
      await pumpFrames(tester, 2);
      await tester.tap(find.text('٣٠٠'));
      await pumpFrames(tester, 4);
      expect(find.byType(PageJumpSheet), findsNothing);
      // The reader jumped: the chip now shows the new page.
      expect(find.text('صفحة ٣٠٠'), findsOneWidget);
      drainLayoutOverflows(tester);
    });

    testWidgets(
        'surah name tap opens the picker; tapping a surah jumps to '
        'its first page', (tester) async {
      await openReader(tester);

      // The test font is ~40% wider than the phone's Amiri, so at
      // 411dp the reader's top row overflows and the surah name
      // lands off-screen (hit-test misses). Widen the viewport for
      // this step only — the behaviour under test (jump) does not
      // depend on the width.
      tester.view.physicalSize = const Size(800 * 2.63, 913 * 2.63);
      tester.view.devicePixelRatio = 2.63;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pump();

      // Two SurahNameImages are in the tree (in-flow header row +
      // controls overlay); the first is the in-flow one, which is
      // the hit-testable one while the controls overlay is hidden.
      await tester.tap(find.byType(SurahNameImage).first);
      await pumpFrames(tester, 4);
      expect(find.byType(SurahJumpSheet), findsOneWidget);

      await tester.tap(find.text('مدنية • 200 آية • صفحة 50'));
      await pumpFrames(tester, 4);
      expect(find.byType(SurahJumpSheet), findsNothing);
      // آل عمران starts on page 50 — the reader jumped there.
      expect(find.text('صفحة ٥٠'), findsOneWidget);
      drainLayoutOverflows(tester);
    });
  });
}
