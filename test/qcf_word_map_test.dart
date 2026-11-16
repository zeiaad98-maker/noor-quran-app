import 'package:flutter_test/flutter_test.dart';
import 'package:quran/quran.dart' as quran;

import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/word_meanings.dart';

/// The glyph -> word mapping is the foundation of the word popup: a tap
/// on a Mushaf word must open exactly that word. These tests prove the
/// mapping against the real QCF data and the bundled morphology for
/// every verse of the Quran — no sampling.
String _bare(String s) {
  final buf = StringBuffer();
  for (final c in s.codeUnits) {
    var ch = c;
    if (ch == 0x0622 || ch == 0x0623 || ch == 0x0625) ch = 0x0627;
    if (ch == 0x0624 || ch == 0x0626) ch = 0x064A;
    if (ch == 0x0621) ch = 0x064A;
    if (ch == 0x0649) ch = 0x064A;
    if ((ch >= 0x0627 && ch <= 0x064A) || ch == 0x0671 || ch == 0x0670) {
      buf.writeCharCode(ch);
    }
  }
  return buf.toString();
}

void main() {
  test('glyph count is exact for all 6236 verses', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final inexact = <String>[];
    var totalGlyphs = 0;
    var totalWords = 0;
    for (var s = 1; s <= 114; s++) {
      for (var v = 1; v <= quran.getVerseCount(s); v++) {
        final map = buildQcfWordMap(s, v);
        totalGlyphs += map.glyphCount;
        totalWords += map.wordCount;
        if (!map.exact) inexact.add('$s:$v');
        // Every glyph maps to a valid word index.
        for (final w in map.glyphToWord) {
          expect(w, inInclusiveRange(0, map.wordCount - 1));
        }
        // Every word owns at least one glyph, in order.
        var prevGlyph = -1;
        for (final word in map.words) {
          expect(word.glyphs, isNotEmpty);
          for (final g in word.glyphs) {
            expect(g, greaterThan(prevGlyph));
            prevGlyph = g;
          }
        }
      }
    }
    // ignore: avoid_print
    print('total glyphs=$totalGlyphs total words=$totalWords '
        'inexact=${inexact.length} $inexact');
    // One known exception: 13:10 has one glyph more than the text
    // predicts (14 words, 15 glyphs) and no mark accounts for it —
    // a font artefact, best-effort there (see qcf_word_map.dart).
    expect(inexact, ['13:10']);
  });

  test('word list matches the bundled morphology (flattened)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final mismatches = <String>[];
    for (var s = 1; s <= 114; s++) {
      for (var v = 1; v <= quran.getVerseCount(s); v++) {
        final map = buildQcfWordMap(s, v);
        final entries = await QuranWordData.wordsForAyah(s, v);
        // Flatten multi-word morph entries (بَعۡدَ مَا is one entry in
        // 2:181, 8:6, 13:37; إِلۡ يَاسِينَ in 37:130).
        final flat = entries
            .expand((e) => e.split(' ').where((w) => w.isNotEmpty))
            .toList();
        if (map.wordCount != flat.length) {
          mismatches.add(
              '$s:$v map=${map.wordCount} morphFlat=${flat.length}');
          continue;
        }
        // Bare letters must agree in order (lookup text, so the 15:7
        // كُنتَ typo in the bundled data still aligns).
        final l1 = map.words.map((w) => _bare(w.lookupText)).join();
        final l2 = flat.map(_bare).join();
        if (l1 != l2) {
          mismatches.add('$s:$v letters differ');
        }
      }
    }
    // ignore: avoid_print
    print('word-list mismatches: ${mismatches.length} $mismatches');
    // One known exception: 15:7 — the bundled morphology duplicates
    // the phrase لَوۡ مَا and spells كُنتُم as كُنتَ (missing م);
    // the map corrects both (see qcf_word_map.dart), so its bare
    // letters differ from the raw morph entries there by design.
    expect(mismatches, ['15:7 letters differ']);
  });

  test('spot checks: 2:33, 1:1, Muqattaat, merged marks, joined tokens',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // 2:33 — 22 words, 23 glyphs; the ۖ glyph (ordinal 4) belongs to
    // the word before it (بِأَسْمَائِهِمْ, word 3). Word spellings
    // are cross-checked against the bundled morphology by bare
    // letters (diacritic order differs between the two datasets).
    final m33 = buildQcfWordMap(2, 33);
    expect(m33.exact, isTrue);
    expect(m33.wordCount, 22);
    expect(m33.glyphCount, 23);
    expect(m33.glyphToWord[4], 3);
    final morph33 = await QuranWordData.wordsForAyah(2, 33);
    expect(_bare(m33.words[14].text), _bare(morph33[14]));
    expect(_bare(m33.words[15].text), _bare(morph33[15]));
    expect(_bare(m33.words[1].text), _bare(morph33[1]));
    expect(_bare(m33.words[3].text), _bare(morph33[3]));

    // 1:1 — 4 words, 4 glyphs, 1:1.
    final m11 = buildQcfWordMap(1, 1);
    expect(m11.exact, isTrue);
    expect(m11.wordCount, 4);
    expect(m11.glyphCount, 4);
    expect(m11.glyphToWord, [0, 1, 2, 3]);

    // 10:1 — الٓرۚ is ONE glyph (the ۚ is drawn inside it).
    final m101 = buildQcfWordMap(10, 1);
    expect(m101.exact, isTrue);
    expect(m101.wordCount, 5);
    expect(m101.glyphCount, 5);

    // 13:1 — الٓمٓرۚ is TWO glyphs (mark separate), plus the ۗ.
    final m131 = buildQcfWordMap(13, 1);
    expect(m131.exact, isTrue);
    expect(m131.glyphCount, 17);
    expect(m131.glyphToWord[0], 0);
    expect(m131.glyphToWord[1], 0);

    // 3:78 — the ۖ after ٱللَّهِ is merged (29 glyphs, not 30).
    final m378 = buildQcfWordMap(3, 78);
    expect(m378.exact, isTrue);
    expect(m378.glyphCount, 29);

    // 26:11 — the ۚ after فِرۡعَوۡنَ is merged (4 glyphs).
    final m2611 = buildQcfWordMap(26, 11);
    expect(m2611.exact, isTrue);
    expect(m2611.glyphCount, 4);

    // 2:26 — the leading ۞ is its own glyph, mapped to word 0.
    final m226 = buildQcfWordMap(2, 26);
    expect(m226.exact, isTrue);
    expect(m226.glyphCount, 44);
    expect(m226.glyphToWord[0], 0);

    // 15:7 — joined token splits; spelling typo corrected.
    final m157 = buildQcfWordMap(15, 7);
    expect(m157.exact, isTrue);
    expect(m157.wordCount, 8);
    expect(_bare(m157.words[0].text), 'لو');
    expect(_bare(m157.words[1].text), 'ما');
    expect(_bare(m157.words[5].text), 'كنتم');
    expect(m157.words[5].lookupText, 'كُنتَ');

    // 27:20 / 36:22 — joined tokens split into two words.
    final m2720 = buildQcfWordMap(27, 20);
    expect(m2720.exact, isTrue);
    expect(m2720.wordCount, 12);
    final m3622 = buildQcfWordMap(36, 22);
    expect(m3622.exact, isTrue);
    expect(m3622.wordCount, 8);

    // 2:181 — merged morph entry بَعۡدَ مَا is two words here.
    final m2181 = buildQcfWordMap(2, 181);
    expect(m2181.exact, isTrue);
    expect(m2181.wordCount, 14);
    expect(m2181.glyphCount, 15);
  });
}

Matcher inInclusiveRange(int min, int max) =>
    _InRange(min, max);

class _InRange extends Matcher {
  final int min;
  final int max;
  _InRange(this.min, this.max);
  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is int && item >= min && item <= max;
  @override
  Description describe(Description description) =>
      description.add('in range $min..$max');
}
