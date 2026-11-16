import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

import 'package:noor_quran/widgets/noor_qcf_page.dart';

bool _noScale() => false;

/// Reader theme used by the app (light), plus a header stand-in.
///
/// The package header contains an InkWell, which cannot find a Material
/// ancestor inside a WidgetSpan placeholder in debug tests
/// (debugCheckHasMaterial; release builds are unaffected, which is why
/// the app works on the phone). This box replicates the real header's
/// layout role exactly: full-width, ~39px tall (mainframe.png 2000x208
/// at width 372), i.e. one line in the page flow.
QcfThemeData _testTheme() => QcfThemeData(
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

/// Pumps the REAL fixed page widget and counts its laid-out text lines:
/// a correct page has exactly 15 lines (no wraps, no merges).
///
/// Measurement: re-layout the pumped paragraph's span with a fresh
/// TextPainter, feeding it the REAL placeholder dimensions read from the
/// rendered paragraph (WidgetSpans need explicit dimensions).
Future<int> _countPageLines(
    WidgetTester tester, int page, double pageWidth, double sp) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ScreenUtilInit(
        designSize: const Size(390, 844),
        enableScaleText: _noScale,
        minTextAdapt: true,
        builder: (_, __) => Scaffold(
          body: NoorQcfPage(
            pageNumber: page,
            sp: sp,
            theme: _testTheme(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  RichText? longestWidget;
  for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
    final span = rt.text;
    if (span is TextSpan) {
      if (longestWidget == null ||
          span.toPlainText().length >
              (longestWidget.text as TextSpan).toPlainText().length) {
        longestWidget = rt;
      }
    }
  }
  if (longestWidget == null) return 0;
  final span = longestWidget.text as TextSpan;
  final rp =
      tester.renderObject<RenderParagraph>(find.byWidget(longestWidget));
  final dims = <PlaceholderDimensions>[];
  var child = rp.firstChild;
  while (child != null) {
    dims.add(
      PlaceholderDimensions(
        size: child.size,
        alignment: PlaceholderAlignment.bottom,
      ),
    );
    child = rp.childAfter(child);
  }
  final painter = TextPainter(
    text: span,
    textDirection: ui.TextDirection.rtl,
    textAlign: TextAlign.center,
    locale: const Locale('ar'),
  )
    ..setPlaceholderDimensions(dims)
    ..layout(maxWidth: pageWidth);
  return painter.computeLineMetrics().length;
}

void main() {
  // Load the real QCF page fonts before any test pumps a widget.
  //
  // The qcf_quran package declares its page-font assets with Windows
  // backslash paths (assets\fonts\qcf4\...) in its pubspec, so the
  // test harness's font manifest never registers them on Linux and
  // TextPainter would measure .notdef boxes (uniform ~18px per glyph)
  // instead of real word-glyphs — every line-count result would be
  // meaningless. The asset FILES themselves are bundled (rootBundle
  // can load them with forward slashes), so register them manually
  // under the packaged family names the widgets look up
  // ('packages/qcf_quran/QCF_P001' ...). The basmala also uses
  // QCF_P001 on every page, so all 604 are needed.
  // (On the phone the fonts render fine — only the test manifest is
  // affected — which is why this is a test-only workaround, not an
  // app change.)
  setUpAll(() async {
    for (var page = 1; page <= 604; page++) {
      final p = page.toString().padLeft(3, '0');
      final data = await rootBundle.load(
          'packages/qcf_quran/assets/fonts/qcf4/QCF4${p}_X-Regular.woff');
      final loader = FontLoader('packages/qcf_quran/QCF_P$p');
      loader.addFont(Future.value(data));
      await loader.load();
    }
  });

  testWidgets('calibrated sp renders exactly 15 lines per page',
      (tester) async {
    // Realme 12 Pro+ approx: 1080x2400 physical, density ~2.63
    // -> logical 411 x 913.
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Calibrated sp for a 411dp-wide screen: 411 / 392.7.
    const calibratedSp = 411 / 392.7;
    expect(await _countPageLines(tester, 3, 411, calibratedSp), 15);
    expect(await _countPageLines(tester, 233, 411, calibratedSp), 15);

    // The old sizing (sp 1.18) combined with the largest system font
    // size (x1.3) wrapped lines: this is the v7 bug, it must wrap.
    const buggySp = 1.1803 * 1.3;
    expect(await _countPageLines(tester, 233, 411, buggySp),
        greaterThan(15));
  });

  testWidgets(
      'restored line breaks: pages that rendered 14/13/16 lines now render 15',
      (tester) async {
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const calibratedSp = 411 / 392.7;
    // Known-bad pages from the pre-fix sweep (rendered 14, 13 or 16):
    // 15/24/32 = 14, 452 = 13, 69/240/279 = 13, 342/350/456 = 16,
    // 602/604 (Juz Amma, 3 surahs each) = 14.
    for (final page in [
      15,
      24,
      32,
      69,
      240,
      279,
      342,
      350,
      452,
      456,
      602,
      604,
    ]) {
      expect(
        await _countPageLines(tester, page, 411, calibratedSp),
        15,
        reason: 'page $page must render exactly 15 lines',
      );
    }
  });

  testWidgets('all 604 pages render the correct line count', (tester) async {
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const calibratedSp = 411 / 392.7;
    final deviations = <String>[];
    for (var page = 1; page <= 604; page++) {
      final rendered = await _countPageLines(tester, page, 411, calibratedSp);
      // Pages 1-2 are special: surah banner + short opening verses
      // (Fatiha on p.1, Baqarah 1-5 on p.2) = 8 lines, not 15.
      // Every other Madinah Mushaf page has exactly 15 lines,
      // including pages with several short surahs (headers and
      // basmalas each occupy one of the 15 lines).
      final expected = page <= 2 ? 8 : 15;
      if (rendered != expected) {
        deviations.add('page $page: rendered=$rendered expected=$expected');
      }
    }
    expect(deviations, isEmpty,
        reason: 'pages with wrong line count: ${deviations.join('; ')}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
