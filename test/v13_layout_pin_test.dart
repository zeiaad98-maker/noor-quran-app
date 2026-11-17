import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

import 'package:noor_quran/widgets/noor_qcf_page.dart';

/// v13 layout pins (the user's report: pages 3, 4, 6 render with the
/// first word of a real Mushaf line alone on its own centred line,
/// the page then has more than 15 lines and the bottom verses clip
/// off).
///
/// Root cause: the user's saved zoom was ~1.04 and the slider allowed
/// up to 1.08, but the QCF fonts are calibrated for 1.00 — at 1.02+
/// real pages wrap. The fix caps the zoom at 0.98 (see
/// clampMushafZoom): visually identical to 1.00, but every page keeps
/// ≥6 dp of margin against the few-dp wider rendering the device
/// shows vs the test-loaded fonts.
///
/// These tests pin the SHIPPED size (zoom 0.98, 411.4 dp wide):
/// * pages 3, 4, 6 render exactly 15 lines, with the exact Madinah
///   line structure (per-line glyph counts below — the real printed
///   lines: no word alone on a line, no clipped verse);
/// * the whole Mushaf (604 pages) renders 15 lines per page
///   (8 for pages 1–2) with at least 6 dp of line-width margin
///   on the tightest verse line (measured 7.1 dp at 0.98; at 1.00 it
///   is under 5 dp, so this also pins the fix against the old size).
bool _noScale() => false;

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

/// Renders [page] with the REAL page widget and returns the laid-out
/// visual lines' texts (hard '\n' breaks + any wraps), plus the
/// widest line's width. Same measurement as qcf_real_render_test:
/// re-layout the pumped paragraph's span with a fresh TextPainter,
/// feeding it the REAL placeholder dimensions.
Future<(List<String>, double)> _renderedLines(
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
  if (longestWidget == null) return (<String>[], 0.0);
  final span = longestWidget.text as TextSpan;
  final rp = tester.renderObject<RenderParagraph>(find.byWidget(longestWidget));
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
  final full = span.toPlainText();
  final lines = <String>[];
  var offset = 0;
  while (offset < full.length) {
    final range = painter.getLineBoundary(TextPosition(offset: offset));
    lines.add(full.substring(range.start, range.end));
    offset = range.end;
    if (offset < full.length && full[offset] == '\n') offset++;
  }
  // Widest VERSE line: lines holding a WidgetSpan (the surah-name
  // header image) are a fixed-width placeholder, not text — they
  // span the page by design and do not scale with the zoom, so they
  // must not count toward the line-width margin.
  final metrics = painter.computeLineMetrics();
  var maxWidth = 0.0;
  for (var i = 0; i < metrics.length && i < lines.length; i++) {
    if (lines[i].contains('\uFFFC')) continue;
    if (metrics[i].width > maxWidth) maxWidth = metrics[i].width;
  }
  return (lines, maxWidth);
}

void main() {
  setUpAll(() async {
    for (var page = 1; page <= 604; page++) {
      final p = page.toString().padLeft(3, '0');
      final data = await rootBundle
          .load('packages/qcf_quran/assets/fonts/qcf4/QCF4${p}_X-Regular.woff');
      final loader = FontLoader('packages/qcf_quran/QCF_P$p');
      loader.addFont(Future.value(data));
      await loader.load();
    }
  });

  // The shipped size: zoom 0.98 on the user's 411.4 dp-wide phone.
  const width = 411.4;
  const sp = width / 392.7 * 0.98;

  testWidgets('pages 3, 4, 6: exact Madinah 15-line structure', (tester) async {
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Per-line glyph counts of the real printed Madinah lines
    // (from the QCF data's hard breaks — the correct layout).
    const expected = {
      3: [10, 11, 9, 10, 8, 10, 10, 11, 9, 10, 10, 10, 9, 8, 8],
      4: [10, 10, 11, 8, 10, 11, 12, 9, 10, 9, 11, 11, 9, 10, 8],
      6: [12, 9, 12, 8, 9, 14, 9, 9, 9, 10, 9, 10, 10, 12, 12],
    };
    for (final entry in expected.entries) {
      final (lines, maxWidth) =
          await _renderedLines(tester, entry.key, width, sp);
      expect(lines.length, 15,
          reason: 'page ${entry.key} must be exactly 15 lines');
      expect(
        [for (final l in lines) l.runes.length],
        entry.value,
        reason: 'page ${entry.key} line structure must be the '
            'Madinah breaks (no word alone, no clipped verse)',
      );
      // No isolated word on any line (the v13 bug shape).
      for (final l in lines) {
        expect(l.runes.length, greaterThan(1),
            reason: 'page ${entry.key}: no word may sit alone');
      }
      // Every line keeps real margin (the device renders a few dp
      // wider than the test fonts — the widest line must stay
      // comfortably inside the page).
      expect(maxWidth, lessThan(width - 6),
          reason: 'page ${entry.key} widest line must keep ≥6 dp');
    }
  });

  testWidgets('whole Mushaf at zoom 0.98: 15 lines, margin on every page',
      (tester) async {
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var globalMax = 0.0;
    var globalMaxPage = 0;
    for (var page = 1; page <= 604; page++) {
      final (lines, maxWidth) = await _renderedLines(tester, page, width, sp);
      final expectedLines = page <= 2 ? 8 : 15;
      expect(lines.length, expectedLines,
          reason: 'page $page must be $expectedLines lines');
      if (maxWidth > globalMax) {
        globalMax = maxWidth;
        globalMaxPage = page;
      }
    }
    // The tightest page still keeps ≥6 dp of margin at the shipped
    // size — the whole Mushaf is fixed, not just pages 3/4/6.
    expect(globalMax, lessThan(width - 6),
        reason: 'widest line (page $globalMaxPage) must keep ≥6 dp');
  });
}
