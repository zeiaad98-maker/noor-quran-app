import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/widgets/noor_qcf_page.dart';

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

/// Character index in [verseText] of the glyph at [glyphOrdinal]
/// (glyphs are the non-'\n' code units, in order).
int _charIndexOfGlyph(String verseText, int glyphOrdinal) {
  var ordinal = 0;
  for (var i = 0; i < verseText.length; i++) {
    if (verseText.codeUnitAt(i) == 10) continue;
    if (ordinal == glyphOrdinal) return i;
    ordinal++;
  }
  return verseText.length;
}

void main() {
  // Same font loading as qcf_real_render_test: the package fonts
  // are only registered in the test manifest via FontLoader.
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

  testWidgets(
      'tapping a word reports its true (surah, verse, wordIndex)',
      (tester) async {
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final wordTaps = <(int, int, int)>[];
    final verseTaps = <(int, int)>[];
    const calibratedSp = 411 / 392.7;

    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          enableScaleText: _noScale,
          minTextAdapt: true,
          builder: (_, __) => Scaffold(
            body: NoorQcfPage(
              pageNumber: 6,
              sp: calibratedSp,
              theme: _testTheme(),
              onTap: (s, v) => verseTaps.add((s, v)),
              onWordTap: (s, v, w) => wordTaps.add((s, v, w)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The Mushaf paragraph is the RichText with the longest text.
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
    expect(longestWidget, isNotNull);
    final plainText = (longestWidget!.text as TextSpan).toPlainText();
    final rp =
        tester.renderObject<RenderParagraph>(find.byWidget(longestWidget));

    // 2:33 on page 6 — 22 words. Word 14 is ٱلسَّمَٰوَٰتِ,
    // word 3 is بِأَسْمَٰٓئِهِمۡ.
    final verseText = getVerseQCF(2, 33, verseEndSymbol: false);
    final verseStart = plainText.indexOf(verseText);
    expect(verseStart, greaterThanOrEqualTo(0),
        reason: '2:33 glyph text must appear verbatim in the page');
    final map = buildQcfWordMap(2, 33);

    Future<void> tapWord(int wordIndex) async {
      final glyphOrdinal = map.glyphToWord.indexOf(wordIndex);
      final charOffset =
          verseStart + _charIndexOfGlyph(verseText, glyphOrdinal);
      final boxes = rp.getBoxesForSelection(
        TextSelection(
          baseOffset: charOffset,
          extentOffset: charOffset + 1,
        ),
      );
      expect(boxes, isNotEmpty, reason: 'word $wordIndex must have a box');
      await tester.tapAt(rp.localToGlobal(boxes.first.toRect().center));
      await tester.pump();
    }

    await tapWord(14);
    expect(wordTaps, [(2, 33, 14)]);
    expect(verseTaps, isEmpty);

    await tapWord(3);
    expect(wordTaps, [(2, 33, 14), (2, 33, 3)]);
    expect(verseTaps, isEmpty);
  });

  testWidgets('tapping the verse-end number opens the ayah sheet',
      (tester) async {
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final wordTaps = <(int, int, int)>[];
    final verseTaps = <(int, int)>[];
    const calibratedSp = 411 / 392.7;

    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          enableScaleText: _noScale,
          minTextAdapt: true,
          builder: (_, __) => Scaffold(
            body: NoorQcfPage(
              pageNumber: 6,
              sp: calibratedSp,
              theme: _testTheme(),
              onTap: (s, v) => verseTaps.add((s, v)),
              onWordTap: (s, v, w) => wordTaps.add((s, v, w)),
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
    expect(longestWidget, isNotNull);
    final plainText = (longestWidget!.text as TextSpan).toPlainText();
    final rp =
        tester.renderObject<RenderParagraph>(find.byWidget(longestWidget));

    // The verse-end number glyph sits right after the verse text.
    final verseText = getVerseQCF(2, 33, verseEndSymbol: false);
    final verseStart = plainText.indexOf(verseText);
    expect(verseStart, greaterThanOrEqualTo(0));
    final numberOffset = verseStart + verseText.length;
    final boxes = rp.getBoxesForSelection(
      TextSelection(
        baseOffset: numberOffset,
        extentOffset: numberOffset + 1,
      ),
    );
    expect(boxes, isNotEmpty);
    await tester.tapAt(rp.localToGlobal(boxes.first.toRect().center));
    await tester.pump();

    expect(verseTaps, [(2, 33)]);
    expect(wordTaps, isEmpty);
  });
}
