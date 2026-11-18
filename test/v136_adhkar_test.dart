import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:noor_quran/data/adhkar_data.dart';
import 'package:noor_quran/screens/adhkar_tasbeeh_screen.dart';

/// v13.6 adhkar — source/virtue hidden behind a toggle, auto-advance
/// on completion, and the top-clipping check (first line visible).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The Amiri font is fetched at runtime in the app; never hit the
  // network in tests (see word_card_test.dart).
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpReader(
    WidgetTester tester,
    AdhkarCategory category,
  ) async {
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: AdhkarReaderScreen(category: category)),
    );
    await tester.pumpAndSettle();
  }

  AdhkarCategory eveningCategory() {
    final combined = adhkarCategories.firstWhere(
      (c) => c.title == 'أذكار الصباح والمساء',
    );
    return eveningAdhkar(combined);
  }

  /// The current dhikr page's vertical scroll position — the
  /// Scrollable NEAREST the page's text (not the PageView's).
  ScrollPosition verticalPositionOf(WidgetTester tester, String marker) {
    // .first: textContaining matches the Text AND its inner RichText.
    final element = tester.element(find.textContaining(marker).first);
    final state = Scrollable.of(element);
    return state.position;
  }

  double verticalOffset(WidgetTester tester, String marker) =>
      verticalPositionOf(tester, marker).pixels;

  double verticalMaxExtent(WidgetTester tester, String marker) =>
      verticalPositionOf(tester, marker).maxScrollExtent;

  /// Go from the intro page to the first dhikr of the real evening set.
  Future<void> goToEveningDhikr1(WidgetTester tester) async {
    await pumpReader(tester, eveningCategory());
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.text('الذكر ١ من ٢١'), findsOneWidget);
  }

  group('source/virtue hidden behind a toggle', () {
    testWidgets('hidden by default; toggle shows/hides; page shortens',
        (tester) async {
      await goToEveningDhikr1(tester);

      expect(find.text('المصدر والفضل'), findsOneWidget);
      expect(find.byKey(const ValueKey('sourceToggleButton_0')),
          findsOneWidget);
      // The grey paragraph (source + virtue) is NOT shown.
      expect(find.textContaining('سورة البقرة، الآية'), findsNothing);
      const marker = 'أَعُوذُ بِاللَّهِ مِنَ الشَّيطَانِ';
      final hiddenExtent = verticalMaxExtent(tester, marker);

      // The toggle sits below the fold while the source is hidden
      // (long dhikr) — scroll it into view before tapping. The
      // scrollable must be named: the PageView is a Scrollable too.
      final toggleFinder =
          find.byKey(const ValueKey('sourceToggleButton_0'));
      final verticalScrollable = find.ancestor(
        of: toggleFinder,
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.vertical,
        ),
      );
      await tester.scrollUntilVisible(
        toggleFinder,
        200,
        scrollable: verticalScrollable,
      );
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(find.textContaining('سورة البقرة، الآية'), findsOneWidget);
      expect(find.textContaining('من قالها حين يصبح أُجير'), findsOneWidget);
      // Showing the source lengthens the page.
      expect(verticalMaxExtent(tester, marker), greaterThan(hiddenExtent));

      await tester.scrollUntilVisible(
        toggleFinder,
        200,
        scrollable: verticalScrollable,
      );
      await tester.tap(toggleFinder);
      await tester.pump();
      expect(find.textContaining('سورة البقرة، الآية'), findsNothing);
      expect(verticalMaxExtent(tester, marker), hiddenExtent);
      expect(tester.takeException(), isNull);
    });
  });

  group('auto-advance on completion', () {
    testWidgets('count-1 dhikr completes → next dhikr after ~1s, once',
        (tester) async {
      await goToEveningDhikr1(tester);

      // One tap completes Ayat al-Kursi (count 1).
      await tester.tap(find.textContaining('أَعُوذُ بِاللَّهِ مِنَ الشَّيطَانِ'));
      await tester.pump();
      expect(find.text('✓'), findsOneWidget);

      // Before the second elapses, still on dhikr 1.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('الذكر ١ من ٢١'), findsOneWidget);

      // After ~1s, auto-advanced to dhikr 2 — and no further.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('الذكر ٢ من ٢١'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('الذكر ٢ من ٢١'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('count-3 dhikr: advances only on the 3rd tap; last '
        'dhikr shows the completion message, no advance', (tester) async {
      const cat = AdhkarCategory(
        title: 'فئة اختبار',
        items: [
          DhikrItem(text: 'ذكر أول', count: 3, source: 'مصدر أول'),
          DhikrItem(text: 'ذكر ثان', count: 1, source: 'مصدر ثان'),
          DhikrItem(text: 'ذكر أخير', count: 1, source: 'مصدر أخير'),
        ],
      );
      await pumpReader(tester, cat);
      expect(find.text('الذكر ١ من ٣'), findsOneWidget);

      Future<void> tapDhikr(String text) async {
        await tester.tap(find.text(text));
        await tester.pump();
      }

      await tapDhikr('ذكر أول');
      await tapDhikr('ذكر أول');
      expect(find.text('الذكر ١ من ٣'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('الذكر ١ من ٣'), findsOneWidget,
          reason: 'not complete yet — no advance');

      await tapDhikr('ذكر أول'); // 3rd tap completes it
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('الذكر ٢ من ٣'), findsOneWidget);

      await tester.tap(find.text('ذكر ثان'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('الذكر ٣ من ٣'), findsOneWidget);

      await tester.tap(find.text('ذكر أخير'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('الذكر ٣ من ٣'), findsOneWidget,
          reason: 'last dhikr — no advance past the end');
      expect(find.textContaining('تمت فئة اختبار'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a manual move cancels the pending auto-advance',
        (tester) async {
      const cat = AdhkarCategory(
        title: 'فئة اختبار',
        items: [
          DhikrItem(text: 'ذكر أول', count: 1, source: 'مصدر أول'),
          DhikrItem(text: 'ذكر ثان', count: 1, source: 'مصدر ثان'),
          DhikrItem(text: 'ذكر ثالث', count: 1, source: 'مصدر ثالث'),
        ],
      );
      await pumpReader(tester, cat);

      // Complete dhikr 1 (advance scheduled), then move manually.
      await tester.tap(find.text('ذكر أول'));
      await tester.pump();
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('الذكر ٢ من ٣'), findsOneWidget);

      // The stale timer must NOT push to dhikr 3.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('الذكر ٢ من ٣'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('top clipping (screenshot check)', () {
    testWidgets('dhikr 1 opens at offset 0, first line below the header',
        (tester) async {
      await goToEveningDhikr1(tester);

      expect(verticalOffset(tester, 'أَعُوذُ بِاللَّهِ مِنَ الشَّيطَانِ'), 0);
      final titleRect = tester.getRect(find.text('أذكار المساء'));
      final textRect =
          tester.getRect(find.textContaining('أَعُوذُ بِاللَّهِ'));
      // The first line starts below the navy header — not cut behind it.
      expect(textRect.top, greaterThan(titleRect.bottom));
      // The first words are rendered (the ayah starts here, not mid-way).
      expect(find.textContaining('أَعُوذُ بِاللَّهِ مِنَ الشَّيطَانِ'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('returning to a scrolled dhikr resets it to its first line',
        (tester) async {
      await goToEveningDhikr1(tester);

      // Scroll the page down (as in the screenshot: the top lines
      // slide under the header).
      final marker = 'أَعُوذُ بِاللَّهِ مِنَ الشَّيطَانِ';
      final element = tester.element(find.textContaining(marker).first);
      final scrollState = Scrollable.of(element);
      scrollState.position.jumpTo(300);
      await tester.pump();
      expect(verticalOffset(tester, marker), 300);

      // Go to dhikr 2 and back — dhikr 1 must start at its first line.
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('الذكر ٢ من ٢١'), findsOneWidget);
      await tester.tap(find.text('السابق'));
      await tester.pumpAndSettle();
      expect(find.text('الذكر ١ من ٢١'), findsOneWidget);
      expect(verticalOffset(tester, 'أَعُوذُ بِاللَّهِ مِنَ الشَّيطَانِ'), 0);
      expect(tester.takeException(), isNull);
    });
  });
}
