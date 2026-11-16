import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/screens/surah_list_screen.dart';
import 'package:noor_quran/widgets/surah_name_image.dart';

/// Bug F: the surah-name calligraphy in the list was "VERY tiny"
/// (height 30 on a canvas that is mostly transparent padding — the
/// ink itself was only ~13dp tall). The fix crops the padding and
/// goes as big as the row allows (height 108, ink up to ~69dp).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('surah names are maximal: cropped, height 108, no overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SurahListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No overflow anywhere in the list.
    expect(tester.takeException(), isNull);

    // Every row uses the big cropped name.
    final names = tester.widgetList<SurahNameImage>(
      find.byType(SurahNameImage),
    );
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(name.height, 108);
      expect(name.cropPadding, isTrue);
    }

    // The cropped widget itself: 108 * 0.72 ≈ 78dp tall (was 30).
    final firstRect = tester.getRect(find.byType(SurahNameImage).first);
    expect(firstRect.height, closeTo(77.8, 1.0));
    expect(firstRect.left, greaterThanOrEqualTo(0.0));
    expect(firstRect.right, lessThanOrEqualTo(411.0));

    // Row furniture still visible: number circle, info line, chevron.
    expect(find.text('مكية • 7 آية • صفحة 1'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('surah list names — golden (read by eye at 411dp)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(411, 914);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        // RTL like the real app, so the rows lay out as the user sees
        // them (number circle right, chevron left).
        locale: const Locale('ar', 'SA'),
        supportedLocales: const [Locale('ar', 'SA')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: SurahListScreen()),
      ),
    );
    // The name images load from the asset bundle asynchronously
    // (same fake-async platform delivery as the popup data): give
    // them several real-async windows + pumps, or the golden
    // captures blank image slots.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SurahListScreen),
      matchesGoldenFile('goldens/surah_list_names.png'),
    );
  });
}
