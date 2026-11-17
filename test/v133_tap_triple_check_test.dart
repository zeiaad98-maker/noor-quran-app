import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;

import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/widgets/noor_qcf_page.dart';

// ---------------------------------------------------------------------
// v13.3 TRIPLE CHECK — verification only, no app code touched.
// Pass 1 (this file): the REAL Dart tap path.
//   1a. Page-grouping simulation over ALL 6236 verses: the grouping
//       the live page does (glyph ordinal -> span -> wordIndex) must
//       reproduce buildQcfWordMap's words exactly.
//   1b. The REAL Dart file-number rule (v13.4: file == audio
//       position from audioPositionForQcfWord, no shift table)
//       against the Quran.com API ground truth
//       (/home/hatch/workspace/noor-quran-v1/v133_api_gt.json,
//       77,433 display positions), plus the map's word TEXTS vs
//       the API texts. The API's 'f' disagrees with position
//       numbering in exactly 27,964 places — pinned as proof the
//       API field is wrong relative to its own files, never as a
//       failure.
//   1c. Edge cases pinned: 13:10, 2:181, 8:6, 13:37, 37:130, 15:7,
//       27:20, 36:22, 27:26, Baqarah 2:6-2:16.
//   1d/1e/3. WIDGET tests with the real production page: invoke every
//       word span's recognizer and do REAL tapAt hits on page 3
//       (every word of 2:6-2:16) and on the edge-case words.
// ---------------------------------------------------------------------

/// Skeleton comparison: strip diacritics / marks / tatweel, unify
/// alef forms, ؤ->و, ئ/ى/ي->ي, drop standalone hamza and invisible
/// chars. Two spellings of the same word compare equal; different
/// words do not.
String _skeleton(String s) {
  final buf = StringBuffer();
  for (final c in s.codeUnits) {
    if (c >= 0x064B && c <= 0x065F) continue; // tashkeel + small marks
    // (0x065E: the bundled text's single-char tanwin variant; the
    // API writes the same mark as tanwin + U+06ED — both stripped)
    if (c == 0x0670 || c == 0x0640) continue; // dagger alef, tatweel
    if (c >= 0x06D6 && c <= 0x06ED) continue; // pause marks etc.
    if (c >= 0x08D3 && c <= 0x08F3) continue; // extended marks
    if (c == 0x200F || c == 0x200E || c == 0x200A || c == 0x0020) continue;
    if (c == 0x00A0) continue; // NBSP: the bundled text joins the
    // leading ۞ to its word with U+00A0 (199 verses), so the map's
    // first word text carries a leading NBSP the API writes as a
    // plain space — same word, different space.
    if (c == 0x0621) continue; // standalone hamza
    var ch = c;
    if (ch == 0x0622 || ch == 0x0623 || ch == 0x0625 || ch == 0x0671) {
      ch = 0x0627; // alef forms -> ا
    }
    if (ch == 0x0624) ch = 0x0648; // ؤ -> و
    if (ch == 0x0626 || ch == 0x0649 || ch == 0x064A) {
      ch = 0x064A; // ئ / ى / ي -> ي
    }
    buf.writeCharCode(ch);
  }
  return buf.toString();
}

const _merged = <String, List<int>>{
  '2:181': [2, 3],
  '8:6': [3, 4],
  '13:37': [7, 8],
  '37:130': [2, 3],
};

/// Simulate the live page's span grouping for one verse and return
/// the (wordIndex, glyph ordinals) of each span, in order.
/// Written from the grouping contract (consecutive glyphs with the
/// same glyph->word value form one span; '\n' is not a glyph), and
/// checked against the map's own words/glyphs lists.
List<(int, List<int>)> _simulateSpans(String verseText, QcfWordMap map) {
  int glyphWord(int ordinal) => ordinal < map.glyphToWord.length
      ? map.glyphToWord[ordinal]
      : map.wordCount - 1;
  final spans = <(int, List<int>)>[];
  var glyphOrdinal = 0;
  var i = 0;
  while (i < verseText.length) {
    final c = verseText.codeUnitAt(i);
    if (c == 10) {
      i++;
      continue;
    }
    final wordIndex = glyphWord(glyphOrdinal);
    final glyphs = <int>[];
    while (i < verseText.length) {
      final c2 = verseText.codeUnitAt(i);
      if (c2 == 10) break;
      if (glyphWord(glyphOrdinal) != wordIndex) break;
      glyphs.add(glyphOrdinal);
      glyphOrdinal++;
      i++;
    }
    spans.add((wordIndex, glyphs));
  }
  return spans;
}

bool _noScale() => false;

Map<String, dynamic> _loadJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1a: page grouping reproduces the word map for all 6236 verses',
      () {
    final drift = <String>[];
    var totalGlyphs = 0;
    var totalSpans = 0;
    var totalSplits = 0;
    for (var s = 1; s <= 114; s++) {
      for (var v = 1; v <= quran.getVerseCount(s); v++) {
        final map = buildQcfWordMap(s, v);
        final verseText = getVerseQCF(s, v, verseEndSymbol: false);
        final spans = _simulateSpans(verseText, map);
        totalGlyphs += map.glyphCount;
        totalSpans += spans.length;
        final key = '$s:$v';
        // Invariants of the live grouping (a span is a maximal run
        // of glyphs with the same word index; a '\n' inside a word's
        // glyphs splits it into two spans of the same word, both
        // tappable and both reporting that word):
        // 1. spans partition the glyph sequence exactly once, in
        //    order (no skipped / duplicated glyph, '\n' handled).
        final allGlyphs = spans.expand((sp) => sp.$2).toList();
        final realGlyphs =
            verseText.codeUnits.where((c) => c != 10).length;
        if (allGlyphs.length != realGlyphs) {
          drift.add('$key glyphs consumed=${allGlyphs.length} '
              'real=$realGlyphs');
          continue;
        }
        for (var o = 0; o < allGlyphs.length; o++) {
          if (allGlyphs[o] != o) {
            drift.add('$key glyph order broken at $o: ${allGlyphs[o]}');
            break;
          }
        }
        // 2. Every word's own glyph(s) sit in a span of that word.
        //    (Mark glyphs share the span but are not in the word's
        //    own glyph list — that is correct, not drift.)
        final spanOfGlyph = <int, int>{};
        for (final (w, glyphs) in spans) {
          for (final g in glyphs) {
            spanOfGlyph[g] = w;
          }
        }
        for (var k = 0; k < map.wordCount; k++) {
          for (final g in map.words[k].glyphs) {
            if (spanOfGlyph[g] != k) {
              drift.add('$key word $k glyph $g in span '
                  '${spanOfGlyph[g]}');
              break;
            }
          }
        }
        // 3. Word indices are non-decreasing and cover all words;
        //    consecutive spans share an index ONLY across a '\n'
        //    (a word split over a line break).
        var prev = -1;
        var splits = 0;
        for (final (w, _) in spans) {
          if (w < prev) {
            drift.add('$key word order falls: $prev -> $w');
            break;
          }
          if (w == prev) splits++;
          prev = w;
        }
        if (spans.isNotEmpty && spans.first.$1 != 0) {
          drift.add('$key first span word ${spans.first.$1}');
        }
        if (spans.isNotEmpty && spans.last.$1 != map.wordCount - 1) {
          drift.add('$key last span word ${spans.last.$1}');
        }
        if (spans.length != map.wordCount + splits) {
          drift.add('$key spans=${spans.length} words=${map.wordCount} '
              'splits=$splits');
        }
        totalSplits += splits;
        // The spans must consume exactly the verse's glyphs.
        final consumed = spans.fold<int>(0, (n, sp) => n + sp.$2.length);
        if (key == '13:10') {
          if (consumed != 15 || realGlyphs != 15) {
            drift.add('$key consumed=$consumed real=$realGlyphs');
          }
        } else if (consumed != map.glyphCount || consumed != realGlyphs) {
          drift.add(
              '$key consumed=$consumed map=${map.glyphCount} real=$realGlyphs');
        }
        // exact flag: true everywhere except 13:10.
        if (map.exact != (key != '13:10')) {
          drift.add('$key exact=${map.exact}');
        }
      }
    }
    // ignore: avoid_print
    print('1a: glyphs=$totalGlyphs spans=$totalSpans '
        'lineSplits=$totalSplits drift=${drift.length}');
    for (final d in drift.take(20)) {
      // ignore: avoid_print
      print('  DRIFT $d');
    }
    expect(drift, isEmpty);
  });

  test('1b: Dart file numbers (== audio position) + word texts vs API',
      () {
    final gt = _loadJson(
        '/home/hatch/workspace/noor-quran-v1/v133_api_gt.json');
    // v13.4: the file number IS the audio position — no shift table.
    // The API's 'f' is NOT the file to request: it counts pause
    // marks as positions and disagrees with position numbering in
    // exactly 27,963 of 77,433 positions (2,705 ayahs) — that
    // disagreement is the API being wrong relative to its own
    // files (proven by transcription), so it is counted here as
    // documentation, never as a failure. (One position, 36:52
    // word 7 هَـٰذَا, has NO audio_url in the API at all — null —
    // and is skipped here; file 007 exists and speaks it.)
    final apiDisagree = <String>[];
    final rangeError = <String>[];
    final textMismatch = <String>[];
    final countMismatch = <String>[];
    var checked = 0;
    for (var s = 1; s <= 114; s++) {
      for (var v = 1; v <= quran.getVerseCount(s); v++) {
        final key = '$s:$v';
        final apiWords =
            (gt[key]!['words'] as List).cast<Map<String, dynamic>>();
        final map = buildQcfWordMap(s, v);
        final merged = _merged[key];
        final expectedDisplay = apiWords.length + (merged == null ? 0 : 1);
        if (map.wordCount != expectedDisplay) {
          countMismatch.add(
              '$key map=${map.wordCount} api=${apiWords.length}');
          continue;
        }
        for (var d = 1; d <= map.wordCount; d++) {
          checked++;
          final audioPos = audioPositionForQcfWord(s, v, d);
          // The controller's guard (audioPos <= tokens.length) must
          // never reject a real tap.
          if (audioPos < 1 || audioPos > apiWords.length) {
            rangeError.add('$key display $d -> audioPos $audioPos '
                'out of ${apiWords.length}');
            continue;
          }
          // v13.4 rule: file == audioPos. The API's number is
          // recorded only to pin how far it disagrees.
          final apiFile = apiWords[audioPos - 1]['f'] as int?;
          if (apiFile != null && apiFile != audioPos) {
            apiDisagree.add('$key display $d audioPos $audioPos '
                'api=$apiFile');
          }
        }
        // Word texts: display words vs the API word at the same
        // audio position (merged pair concatenated).
        String displaySkeleton(int d) {
          // d is 1-based display position.
          if (merged != null && d - 1 == merged[0]) {
            return _skeleton(map.words[merged[0]].text +
                map.words[merged[1]].text);
          }
          if (merged != null && d - 1 == merged[1]) return '';
          return _skeleton(map.words[d - 1].text);
        }

        for (var d = 1; d <= map.wordCount; d++) {
          if (merged != null && d - 1 == merged[1]) continue;
          final audioPos = audioPositionForQcfWord(s, v, d);
          final apiText = apiWords[audioPos - 1]['t'] as String? ?? '';
          final ours = displaySkeleton(d);
          final theirs = _skeleton(apiText);
          if (ours != theirs) {
            // Known: 15:7 word 6 — the map corrects the bundled
            // typo كُنتَ to the Mushaf's كُنتُم; the API keeps كُنتَ.
            if (key == '15:7' && d == 6) continue;
            textMismatch.add(
                '$key display $d ours=${map.words[d - 1].text} '
                'api=$apiText');
          }
        }
      }
    }
    // ignore: avoid_print
    print('1b: positions=$checked apiDisagree=${apiDisagree.length} '
        'textMismatch=${textMismatch.length} '
        'countMismatch=${countMismatch.length}');
    for (final m in apiDisagree.take(5)) {
      // ignore: avoid_print
      print('  API-DISAGREE $m');
    }
    for (final m in textMismatch.take(20)) {
      // ignore: avoid_print
      print('  TEXT $m');
    }
    for (final m in countMismatch.take(20)) {
      // ignore: avoid_print
      print('  COUNT $m');
    }
    expect(rangeError, isEmpty);
    expect(checked, 77433);
    expect(apiDisagree.length, 27963,
        reason: 'the API disagrees with position numbering in exactly '
            '27,963 places — that is the API being wrong, not the app');
    // Key cases (transcription-proven): the API says 016/012/002/
    // 056, the file that speaks the word is 015/011/001/048.
    expect((gt['3:7']['words'] as List)[14]['f'], 16);
    expect((gt['2:81']['words'] as List)[10]['f'], 12);
    expect((gt['2:26']['words'] as List)[0]['f'], 2);
    expect((gt['2:255']['words'] as List)[47]['f'], 56);
    // Exactly one known TEXT quirk in the underlying data (NOT a tap
    // error — both independent passes agree, indices and files are
    // right). Pinned by location only (the word spelling contains
    // invisible diacritic variants):
    // * 11:13 word 3: the bundled text writes ٱفۡتَرَىٰهُ (alef
    //   maksura) where the API writes افْتَرَاهُ (plain alef) — the
    //   same word, different alef spelling convention.
    // (There used to be a second quirk — 37:24 word 3 carried a
    // trailing '\n' — but v13.3 FIX D strips word padding, so it is
    // gone and the count dropped from 2 to 1.)
    expect(textMismatch.length, 1);
    expect(textMismatch[0].startsWith('11:13 display 3 '), isTrue);
    expect(countMismatch, isEmpty);
  });

  test('1c: edge cases pinned', () {
    // 13:10 — 14 words, 15 glyphs, best-effort; the extra glyph
    // clamps to the last word (the page's glyphWord fallback).
    final m1310 = buildQcfWordMap(13, 10);
    expect(m1310.exact, isFalse);
    expect(m1310.wordCount, 14);
    expect(m1310.glyphCount, 14);
    expect(getVerseQCF(13, 10, verseEndSymbol: false)
        .codeUnits
        .where((c) => c != 10)
        .length, 15);
    // The page's clamp: ordinal 14 -> last word (13).
    final clamped =
        14 < m1310.glyphToWord.length ? m1310.glyphToWord[14] : 13;
    expect(clamped, 13);

    // Merged ayahs: both display halves share one audio position,
    // words after the pair shift down by one (else NEXT word plays).
    expect(audioPositionForQcfWord(2, 181, 3), 3);
    expect(audioPositionForQcfWord(2, 181, 4), 3);
    expect(audioPositionForQcfWord(2, 181, 5), 4);
    expect(audioPositionForQcfWord(2, 181, 14), 13);
    expect(audioPositionForQcfWord(8, 6, 4), 4);
    expect(audioPositionForQcfWord(8, 6, 5), 4);
    expect(audioPositionForQcfWord(8, 6, 6), 5);
    expect(audioPositionForQcfWord(13, 37, 8), 8);
    expect(audioPositionForQcfWord(13, 37, 9), 8);
    expect(audioPositionForQcfWord(13, 37, 10), 9);
    expect(audioPositionForQcfWord(37, 130, 3), 3);
    expect(audioPositionForQcfWord(37, 130, 4), 3);

    // 2:181: display 12 (ٱللَّهَ) is audio position 11 (the merged
    // pair بَعۡدَ مَا shifts everything after it down by one), so
    // its file is 011 — the number the old shift table claimed was
    // SKIPPED (the ۚ after word 10 counted as a position). It is
    // not skipped: file 011 speaks ٱللَّهَ (transcribed 2026-11-17,
    // both ASR models).
    expect(audioPositionForQcfWord(2, 181, 12), 11);
    expect(wbwWordUrl(2, 181, audioPositionForQcfWord(2, 181, 12)),
        'https://audio.qurancdn.com/wbw/002_181_011.mp3');
    expect(audioPositionForQcfWord(2, 181, 10), 9);
    expect(wbwWordUrl(2, 181, audioPositionForQcfWord(2, 181, 10)),
        'https://audio.qurancdn.com/wbw/002_181_009.mp3');
    // 37:130 display word 4 (يَاسِينَ) is audio position 3, file
    // 003 — file 004 does not exist and must never be requested
    // (37:130 has only 3 audio words).
    expect(audioPositionForQcfWord(37, 130, 4), 3);
    expect(wbwWordUrl(37, 130, audioPositionForQcfWord(37, 130, 4)),
        'https://audio.qurancdn.com/wbw/037_130_003.mp3');

    // 15:7 joined token + typo fix; 27:20 / 36:22 splits.
    final m157 = buildQcfWordMap(15, 7);
    expect(m157.wordCount, 8);
    expect(_skeleton(m157.words[0].text), 'لو');
    expect(_skeleton(m157.words[1].text), 'ما');
    expect(_skeleton(m157.words[5].text), 'كنتم');
    expect(buildQcfWordMap(27, 20).wordCount, 12);
    expect(buildQcfWordMap(36, 22).wordCount, 8);
    // 27:26 — trailing U+200F in the API text must not shift
    // anything; the map has 8 words.
    expect(buildQcfWordMap(27, 26).wordCount, 8);

    // Baqarah page 3 (2:6-2:16): word counts per verse (API counts).
    const p3Counts = {
      6: 11,
      7: 12,
      8: 11,
      9: 10,
      10: 12,
      11: 11,
      12: 7,
      13: 19,
      14: 16,
      15: 7,
      16: 11,
    };
    for (final e in p3Counts.entries) {
      expect(buildQcfWordMap(2, e.key).wordCount, e.value,
          reason: '2:${e.key}');
    }
  });

  test('dump full Dart map to /tmp for pass 2 (independent Python check)',
      () {
    final out = <String, dynamic>{};
    for (var s = 1; s <= 114; s++) {
      for (var v = 1; v <= quran.getVerseCount(s); v++) {
        final map = buildQcfWordMap(s, v);
        out['$s:$v'] = {
          'words': map.words
              .map((w) => {
                    'i': w.wordIndex,
                    't': w.text,
                    'l': w.lookupText,
                    'g': w.glyphs,
                  })
              .toList(),
          'g2w': map.glyphToWord,
          'exact': map.exact,
        };
      }
    }
    File('/home/hatch/workspace/noor-quran-v1/v133_dart_map.json')
        .writeAsStringSync(jsonEncode(out));
    // ignore: avoid_print
    print('dumped ${out.length} ayahs to '
        '/home/hatch/workspace/noor-quran-v1/v133_dart_map.json');
  });

  // ---------------------------------------------------------------
  // Widget tests — the REAL production page (NoorQcfPage).
  // ---------------------------------------------------------------
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

  int pageOf(int surah, int verse) {
    for (var p = 1; p <= 604; p++) {
      for (final r in getPageData(p)) {
        if (r['surah'] == surah &&
            verse >= (r['start'] as int) &&
            verse <= (r['end'] as int)) {
          return p;
        }
      }
    }
    throw StateError('no page for $surah:$verse');
  }

  /// Pump a real page and return (wordTaps, verseTaps, pump helpers).
  Future<({List<(int, int, int)> wordTaps, List<(int, int)> verseTaps})>
      pumpPage(WidgetTester tester, int page) async {
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
              pageNumber: page,
              sp: calibratedSp,
              theme: testTheme(),
              onTap: (s, v) => verseTaps.add((s, v)),
              onWordTap: (s, v, w) => wordTaps.add((s, v, w)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (wordTaps: wordTaps, verseTaps: verseTaps);
  }

  /// All leaf TextSpans with a TapGestureRecognizer, in document
  /// order, from the page's longest RichText (the Mushaf paragraph).
  List<TextSpan> wordSpans(WidgetTester tester) {
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
    final out = <TextSpan>[];
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.recognizer is TapGestureRecognizer &&
            (span.children == null || span.children!.isEmpty)) {
          out.add(span);
        }
        if (span.children != null) {
          for (final c in span.children!) {
            walk(c);
          }
        }
      }
    }

    walk(longestWidget!.text as TextSpan);
    return out;
  }

  /// Invoke every word span's recognizer and check the reported
  /// sequence: per verse, each word index exactly once, ascending.
  void checkRecognizerSequence(
    List<TextSpan> spans,
    List<(int, int, int)> wordTaps,
    List<(int, int)> verseTaps,
    List<(int, int)> verses,
  ) {
    for (final span in spans) {
      (span.recognizer as TapGestureRecognizer).onTap?.call();
    }
    // Group word taps by verse, in order.
    final byVerse = <String, List<int>>{};
    for (final (s, v, w) in wordTaps) {
      byVerse.putIfAbsent('$s:$v', () => []).add(w);
    }
    for (final (s, v) in verses) {
      final map = buildQcfWordMap(s, v);
      final got = byVerse['$s:$v'] ?? const <int>[];
      // A word split over a line break is two spans of the same
      // word: collapse consecutive duplicates before comparing.
      final dedup = <int>[];
      for (final w in got) {
        if (dedup.isEmpty || dedup.last != w) dedup.add(w);
      }
      expect(dedup, List.generate(map.wordCount, (i) => i),
          reason: 'recognizer sequence for $s:$v');
    }
    // One verse-number tap per verse (the ۝ glyphs).
    expect(verseTaps.length, verses.length,
        reason: 'verse-number spans: $verseTaps');
  }

  List<(int, int)> versesOfPage(int page) {
    final out = <(int, int)>[];
    for (final r in getPageData(page)) {
      for (var v = r['start'] as int; v <= (r['end'] as int); v++) {
        out.add((r['surah'] as int, v));
      }
    }
    return out;
  }

  testWidgets('1d: page 3 recognizers report every word exactly',
      (tester) async {
    final taps = await pumpPage(tester, 3);
    final verses = versesOfPage(3);
    expect(verses.map((e) => e.$2).toList(),
        [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
    final spans = wordSpans(tester);
    checkRecognizerSequence(
        spans, taps.wordTaps, taps.verseTaps, verses);
  });

  testWidgets('1e: edge pages recognizers report every word exactly',
      (tester) async {
    final targets = <(int, int)>[
      (13, 10),
      (2, 181),
      (15, 7),
      (27, 26),
      (37, 130),
      (8, 6),
      (13, 37),
    ];
    final pages = <int, List<(int, int)>>{};
    for (final t in targets) {
      pages.putIfAbsent(pageOf(t.$1, t.$2), () => []).add(t);
    }
    // ignore: avoid_print
    print('edge pages: $pages');
    for (final entry in pages.entries) {
      final taps = await pumpPage(tester, entry.key);
      final verses = versesOfPage(entry.key);
      final spans = wordSpans(tester);
      // Every verse on the page, not just the targets.
      checkRecognizerSequence(
          spans, taps.wordTaps, taps.verseTaps, verses);
    }
  });

  /// Character index in [verseText] of the glyph at [glyphOrdinal].
  int charIndexOfGlyph(String verseText, int glyphOrdinal) {
    var ordinal = 0;
    for (var i = 0; i < verseText.length; i++) {
      if (verseText.codeUnitAt(i) == 10) continue;
      if (ordinal == glyphOrdinal) return i;
      ordinal++;
    }
    return verseText.length;
  }

  testWidgets('3: real taps on EVERY word of Baqarah page 3 (2:6-2:16)',
      (tester) async {
    final taps = await pumpPage(tester, 3);
    // The Mushaf paragraph is the longest RichText.
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

    var tapped = 0;
    final wrong = <String>[];
    for (var v = 6; v <= 16; v++) {
      final verseText = getVerseQCF(2, v, verseEndSymbol: false);
      var verseStart = plainText.indexOf(verseText);
      if (verseStart < 0) {
        // First verse on the page: the hair space U+200A sits
        // after the first glyph, breaking a verbatim search.
        final withHair =
            '${verseText.substring(0, 1)}\u200A${verseText.substring(1)}';
        verseStart = plainText.indexOf(withHair);
      }
      expect(verseStart, greaterThanOrEqualTo(0),
          reason: '2:$v must appear on page 3');
      final map = buildQcfWordMap(2, v);
      for (var w = 0; w < map.wordCount; w++) {
        final glyphOrdinal = map.words[w].glyphs.first;
        // The page inserts a hair space U+200A after the first
        // glyph of its first verse (2:6 here): every later char
        // offset in the rendered paragraph is +1.
        final hairShift = (v == 6 && glyphOrdinal > 0) ? 1 : 0;
        final charOffset = verseStart +
            charIndexOfGlyph(verseText, glyphOrdinal) +
            hairShift;
        final boxes = rp.getBoxesForSelection(
          TextSelection(
              baseOffset: charOffset, extentOffset: charOffset + 1),
        );
        expect(boxes, isNotEmpty, reason: '2:$v word $w must have a box');
        final before = taps.wordTaps.length;
        await tester.tapAt(rp.localToGlobal(boxes.first.toRect().center));
        await tester.pump();
        tapped++;
        if (taps.wordTaps.length != before + 1 ||
            taps.wordTaps.last != (2, v, w)) {
          wrong.add(
              '2:$v word $w (${map.words[w].text}) -> ${taps.wordTaps.length > before ? taps.wordTaps.last : 'NO TAP'}');
        }
      }
    }
    // ignore: avoid_print
    print('pass 3: tapped=$tapped wrong=${wrong.length}');
    for (final w in wrong.take(20)) {
      // ignore: avoid_print
      print('  WRONG $w');
    }
    expect(wrong, isEmpty);
    expect(taps.verseTaps, isEmpty);
  });

  testWidgets('3b: real taps on the reported edge words', (tester) async {
    // (surah, verse, wordIndex 0-based, note)
    const targets = <(int, int, int, String)>[
      (2, 181, 2, 'بَعْدَ half of merged pair'),
      (2, 181, 3, 'مَا half of merged pair'),
      (2, 181, 11, 'ٱللَّهَ after skipped file 011'),
      (13, 10, 13, 'last word, extra glyph clamps here'),
      (15, 7, 0, 'لَّوۡ split token'),
      (15, 7, 5, 'كُنتُم typo fix'),
      (37, 130, 2, 'إِلۡ half of merged pair'),
      (37, 130, 3, 'يَاسِينَ half of merged pair'),
      (27, 26, 7, 'ٱلْعَظِيمِ with trailing U+200F'),
      (2, 8, 1, 'ٱلنَّاسِ next to مَن — the "card showed من" page'),
      (2, 8, 2, 'مَن itself'),
      (2, 8, 0, 'وَمِنَ'),
    ];
    final byPage = <int, List<(int, int, int, String)>>{};
    for (final t in targets) {
      byPage.putIfAbsent(pageOf(t.$1, t.$2), () => []).add(t);
    }
    for (final entry in byPage.entries) {
      final taps = await pumpPage(tester, entry.key);
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
      final pageVerses = versesOfPage(entry.key);
      final firstVerse = pageVerses.first;
      for (final (s, v, w, note) in entry.value) {
        final verseText = getVerseQCF(s, v, verseEndSymbol: false);
        var verseStart = plainText.indexOf(verseText);
        if (verseStart < 0) {
          final withHair =
              '${verseText.substring(0, 1)}\u200A${verseText.substring(1)}';
          verseStart = plainText.indexOf(withHair);
        }
        expect(verseStart, greaterThanOrEqualTo(0),
            reason: '$s:$v on page ${entry.key}');
        final map = buildQcfWordMap(s, v);
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
        expect(boxes, isNotEmpty, reason: '$s:$v word $w ($note)');
        final before = taps.wordTaps.length;
        await tester.tapAt(rp.localToGlobal(boxes.first.toRect().center));
        await tester.pump();
        expect(taps.wordTaps.length, before + 1, reason: '$s:$v w$w $note');
        expect(taps.wordTaps.last, (s, v, w), reason: '$s:$v w$w $note');
      }
    }
  });
}
