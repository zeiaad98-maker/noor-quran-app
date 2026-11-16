import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/screens/adhkar_tasbeeh_screen.dart';

/// Bug G: on the Tasbeeh screen the target-pills row (33/99/100/500/
/// 1000) was clipped behind the bottom nav — only the tops of the
/// pills showed, their numbers hidden — and the vibration row was
/// entirely below the fold. The screen is a fixed-height Column
/// with Spacers inside the tabbed Scaffold (AppBar + Adhkar TabBar
/// + Material 3 NavigationBar), so on a 411×919 phone the content
/// is taller than the space above the bottom nav.
///
/// The harness below reproduces the REAL chrome: AppBar + the
/// Adhkar TabBar (via AdhkarTasbeehScreen, tab 1 = المسبحة) +
/// NavigationBar, with the phone's status-bar / gesture-bar insets
/// (viewPadding top 24 / bottom 28).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpRealChrome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(411, 919);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewPadding =
        const FakeViewPadding(top: 24.0, bottom: 28.0);
    tester.view.padding = const FakeViewPadding(top: 24.0, bottom: 28.0);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetPadding);

    await tester.pumpWidget(
      MaterialApp(
        // Same localizations as the real app (lib/main.dart): the
        // material_ui TabBar requires MaterialLocalizations, and
        // flutter/material's default MaterialApp does not provide
        // material_ui's flavor — without these the TabBar throws
        // and the layout cascade hides the real overflow.
        locale: const Locale('ar', 'SA'),
        supportedLocales: const [Locale('ar', 'SA')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          appBar: AppBar(title: const Text('الأذكار والتسبيح')),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 2,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined), label: 'الرئيسية'),
              NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined), label: 'المصحف'),
              NavigationDestination(
                  icon: Icon(Icons.favorite_border), label: 'الأذكار'),
              NavigationDestination(
                  icon: Icon(Icons.search_outlined), label: 'بحث'),
            ],
          ),
          body: const AdhkarTasbeehScreen(initialTab: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A widget is fully visible only if its whole rect sits inside
  /// the screen AND above the bottom navigation bar.
  void expectFullyVisibleAboveNav(WidgetTester tester, Finder finder) {
    expect(finder, findsOneWidget);
    final rect = tester.getRect(finder);
    final navRect = tester.getRect(find.byType(NavigationBar));
    expect(rect.top, greaterThanOrEqualTo(0.0),
        reason: '$finder cut off at the top');
    expect(rect.bottom, lessThanOrEqualTo(navRect.top),
        reason: '$finder hidden behind the bottom nav '
            '(bottom ${rect.bottom}, nav top ${navRect.top})');
    expect(rect.left, greaterThanOrEqualTo(0.0));
    expect(rect.right, lessThanOrEqualTo(411.0));
  }

  testWidgets(
      'tasbeeh: total, target pills with numbers and vibration row '
      'fully visible above the bottom nav at 411x919', (tester) async {
    await pumpRealChrome(tester);

    // No overflow (the old Column + Spacers overflowed).
    expect(tester.takeException(), isNull);

    // The total line and every target pill — NUMBERS included.
    expectFullyVisibleAboveNav(tester, find.text('المجموع الكلي: 0'));
    for (final pill in ['33', '99', '100', '500', '1000']) {
      expectFullyVisibleAboveNav(tester, find.text(pill));
    }
    // The vibration row at the very bottom must be visible too.
    expectFullyVisibleAboveNav(tester, find.text('اهتزاز عند العد'));
    // The tap circle and its counter are still there.
    expect(find.text('0'), findsWidgets);
    expect(find.text('الهدف: 100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
