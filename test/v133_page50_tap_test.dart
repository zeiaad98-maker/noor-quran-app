import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';

import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/widgets/noor_qcf_page.dart';

// v13.3 page-50 investigation (user report 2026-11-17 17:44):
// tapped الَّذِينَ (3:7 word 15) — highlight correct, sound wrong.
// Real tapAt on EVERY word of page 50 through the production page,
// reporting tap -> word text -> audio position -> wbw file.

Map<String, dynamic> _loadJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('3:7 static mapping: word 15 is الذين -> file 015 (v13.4)', () {
    final map = buildQcfWordMap(3, 7);
    expect(map.wordCount, 46);
    expect(map.exact, isTrue);
    final gt = _loadJson('/home/hatch/workspace/noor-quran-v1/v133_api_gt.json');
    final apiWords = (gt['3:7']['words'] as List).cast<Map<String, dynamic>>();
    for (final d in [2, 14, 15, 16]) {
      final audioPos = audioPositionForQcfWord(3, 7, d);
      // v13.4: file == audio position. The API's number is wrong
      // here (word 15: API says 016, file 015 speaks الَّذِينَ).
      final file = audioPos;
      final apiFile = apiWords[audioPos - 1]['f'] as int;
      final apiText = apiWords[audioPos - 1]['t'] as String;
      // ignore: avoid_print
      print('3:7 display $d map=${map.words[d - 1].text} '
          'audioPos=$audioPos file=$file apiFile=$apiFile apiText=$apiText');
      expect(audioPos, d, reason: 'no merged pair in 3:7');
      expect(file, audioPos);
    }
    // The API disagrees exactly where a pause mark precedes:
    // word 2 has no shift (file 002), words 14/15/16 are each one
    // too high in the API (015/016/017 for positions 14/15/16).
    expect(apiWords[1]['f'], 2);
    expect(apiWords[13]['f'], 15);
    expect(apiWords[14]['f'], 16);
    expect(apiWords[15]['f'], 17);
    // Word 15 must be الَّذِينَ and word 2 الَّذِي (same word as the
    // API text up to diacritic code-point conventions — the bundled
    // text and the API differ in one mark's code point on word 2,
    // the same class as the known 11:13 quirk; compare skeletons).
    String skeleton(String s) {
      final buf = StringBuffer();
      for (final c in s.codeUnits) {
        if (c >= 0x064B && c <= 0x065F) continue;
        if (c == 0x0670 || c == 0x0640) continue;
        if (c >= 0x06D6 && c <= 0x06ED) continue;
        if (c == 0x00A0 || c == 0x200F || c == 0x200A) continue;
        var ch = c;
        if (ch == 0x0622 || ch == 0x0623 || ch == 0x0625 || ch == 0x0671) {
          ch = 0x0627;
        }
        if (ch == 0x0626 || ch == 0x0649 || ch == 0x064A) ch = 0x064A;
        buf.writeCharCode(ch);
      }
      return buf.toString();
    }

    expect(skeleton(map.words[14].text),
        skeleton(apiWords[14]['t'] as String));
    expect(skeleton(map.words[1].text), skeleton(apiWords[1]['t'] as String));
    // ignore: avoid_print
    print('word 15 text == API: ${map.words[14].text}');
    // ignore: avoid_print
    print('word 2 text == API: ${map.words[1].text}');
  });

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

  int charIndexOfGlyph(String verseText, int glyphOrdinal) {
    var ordinal = 0;
    for (var i = 0; i < verseText.length; i++) {
      if (verseText.codeUnitAt(i) == 10) continue;
      if (ordinal == glyphOrdinal) return i;
      ordinal++;
    }
    return verseText.length;
  }

  testWidgets('page 50: real tapAt on every word of 3:1-3:9', (tester) async {
    const page = 50;
    final verses = <(int, int)>[];
    for (final r in getPageData(page)) {
      for (var v = r['start'] as int; v <= (r['end'] as int); v++) {
        verses.add((r['surah'] as int, v));
      }
    }
    // ignore: avoid_print
    print('page 50 verses: $verses');
    expect(verses.map((e) => e.$2).toList(), [1, 2, 3, 4, 5, 6, 7, 8, 9]);

    final wordTaps = <(int, int, int)>[];
    const calibratedSp = 411 / 392.7;
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          minTextAdapt: true,
          builder: (_, __) => Scaffold(
            body: NoorQcfPage(
              pageNumber: page,
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

    final wrong = <String>[];
    var tapped = 0;
    final firstVerse = verses.first;
    // Search cursor: the paragraph opens with the surah header
    // (WidgetSpan) + the Basmala span (" ﱁ  ﱂﱃﱄ\n") BEFORE the first
    // verse. 3:1's text is a SINGLE glyph (64577) that also occurs
    // as the Basmala's first glyph — a plain indexOf finds the
    // Basmala, not the verse (a test bug, not an app bug: tapping
    // the Basmala correctly does nothing). Start after the Basmala's
    // newline, then advance past each verse found.
    var searchFrom = plainText.indexOf('\n') + 1;
    for (final (s, v) in verses) {
      final verseText = getVerseQCF(s, v, verseEndSymbol: false);
      var verseStart = plainText.indexOf(verseText, searchFrom);
      if (verseStart < 0) {
        final withHair =
            '${verseText.substring(0, 1)}\u200A${verseText.substring(1)}';
        verseStart = plainText.indexOf(withHair, searchFrom);
      }
      expect(verseStart, greaterThanOrEqualTo(0),
          reason: '$s:$v must appear on page 50');
      searchFrom = verseStart + verseText.length;
      final map = buildQcfWordMap(s, v);
      for (var w = 0; w < map.wordCount; w++) {
        final glyphOrdinal = map.words[w].glyphs.first;
        final hairShift =
            (s == firstVerse.$1 && v == firstVerse.$2 && glyphOrdinal > 0)
                ? 1
                : 0;
        final charOffset = verseStart +
            charIndexOfGlyph(verseText, glyphOrdinal) +
            hairShift;
        final boxes = rp.getBoxesForSelection(
          TextSelection(
              baseOffset: charOffset, extentOffset: charOffset + 1),
        );
        expect(boxes, isNotEmpty, reason: '$s:$v word $w must have a box');
        final before = wordTaps.length;
        await tester.tapAt(rp.localToGlobal(boxes.first.toRect().center));
        await tester.pump();
        tapped++;
        final audioPos = audioPositionForQcfWord(s, v, w + 1);
        // v13.4: file == audio position (no shift table).
        final file = audioPos;
        // ignore: avoid_print
        print('TAP $s:$v word ${w + 1} ${map.words[w].text} '
            '-> tap=${wordTaps.length > before ? wordTaps.last : 'NONE'} '
            'audioPos=$audioPos file=${file.toString().padLeft(3, '0')}');
        if (wordTaps.length != before + 1 ||
            wordTaps.last != (s, v, w)) {
          wrong.add('$s:$v word ${w + 1} (${map.words[w].text}) -> '
              '${wordTaps.length > before ? wordTaps.last : 'NO TAP'}');
        }
      }
    }
    // ignore: avoid_print
    print('page50: tapped=$tapped wrong=${wrong.length}');
    for (final w in wrong.take(20)) {
      // ignore: avoid_print
      print('  WRONG $w');
    }
    expect(wrong, isEmpty);
  });
}
