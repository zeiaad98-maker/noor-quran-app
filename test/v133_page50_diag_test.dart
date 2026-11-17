import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/widgets/noor_qcf_page.dart';

// Diagnostic only: why does the first glyph of page 50 (3:1 الٓمٓ)
// not register a tap in v133_page50_tap_test.dart?
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  QcfThemeData testTheme() => QcfThemeData(
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

  testWidgets('diag 3:1 first glyph', (tester) async {
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final wordTaps = <(int, int, int)>[];
    const calibratedSp = 411 / 392.7;
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          builder: (_, __) => Scaffold(
            body: NoorQcfPage(
              pageNumber: 50,
              sp: calibratedSp,
              theme: testTheme(),
              onTap: (s, v) {},
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
    // ignore: avoid_print
    print('plainText len=${plainText.length} '
        'first 20 code units=${plainText.codeUnits.take(20).toList()}');
    final verseText = getVerseQCF(3, 1, verseEndSymbol: false);
    // ignore: avoid_print
    print('3:1 verseText code units=${verseText.codeUnits.toList()}');
    var verseStart = plainText.indexOf(verseText);
    // ignore: avoid_print
    print('verseStart=$verseStart');
    if (verseStart < 0) {
      final withHair =
          '${verseText.substring(0, 1)}\u200A${verseText.substring(1)}';
      verseStart = plainText.indexOf(withHair);
      // ignore: avoid_print
      print('verseStart with hair=$verseStart');
    }
    // Box for the first glyph (char offset verseStart).
    final boxes = rp.getBoxesForSelection(
      TextSelection(baseOffset: verseStart, extentOffset: verseStart + 1),
    );
    // ignore: avoid_print
    print('boxes=$boxes');
    if (boxes.isNotEmpty) {
      final rect = boxes.first.toRect();
      final center = rp.localToGlobal(rect.center);
      // ignore: avoid_print
      print('box rect=$rect global center=$center size=${tester.view.physicalSize}');
      final pos = rp.getPositionForOffset(rect.center);
      final spanAt = (longestWidget.text as TextSpan)
          .getSpanForPosition(TextPosition(offset: pos.offset));
      // ignore: avoid_print
      print('span at center: ${spanAt.runtimeType} '
          'text=${spanAt is TextSpan ? spanAt.toPlainText() : ''} '
          'recognizer=${spanAt is TextSpan ? spanAt.recognizer : null}');
      // Try taps at 25% / 50% / 75% of the box width.
      for (final frac in [0.25, 0.5, 0.75]) {
        final pt = rp.localToGlobal(
            Offset(rect.left + rect.width * frac, rect.center.dy));
        final before = wordTaps.length;
        await tester.tapAt(pt);
        await tester.pump();
        // ignore: avoid_print
        print('tap at frac $frac -> taps=${wordTaps.length - before} '
            '${wordTaps.length > before ? wordTaps.last : ''}');
      }
    }
    // Also: what does the map say about 3:1?
    final map = buildQcfWordMap(3, 1);
    // ignore: avoid_print
    print('3:1 map words=${map.words.map((w) => w.text).toList()} '
        'glyphs=${map.glyphToWord} exact=${map.exact}');
  });
}
