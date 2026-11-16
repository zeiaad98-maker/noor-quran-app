import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/word_meanings.dart';

/// Task 1 — word-meanings coverage, measured with the app's own matching
/// logic (QuranWordData.coverageStats, over the REAL bundled assets).
///
/// BEFORE (غريب القرآن only, app's own matching logic):
///   9,079 / 77,429 = 11.7% with a meaning.
///   (The coordinator's earlier 8,898 / 11.5% used a slightly different
///   matching method; 9,079 is what coverageStats() itself measures.)
/// AFTER (غريب القرآن + مفردات الراغب root lexicon):
///   49,064 / 77,429 = 63.4% with a meaning;
///   77,429 / 77,429 = 100% with a non-blank gloss.
/// The gloss is NEVER blank: every one of the 77,429 words has either a
/// meaning or its (real, bundled) morphology description.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coverage: lexicon lifts meanings far above the 11.5% baseline',
      () async {
    final stats = await QuranWordData.coverageStats();
    // Printed so the run log records the measured numbers.
    // ignore: avoid_print
    print('COVERAGE total=${stats.total} withGharib=${stats.withGharib} '
        'withLexicon=${stats.withLexicon} withMeaning=${stats.withMeaning} '
        'withGloss=${stats.withGloss}');
    expect(stats.total, 77429);
    // غريب القرآن alone covered 9,079 (11.7%) before the lexicon.
    expect(stats.withGharib, 9079);
    // مفردات الراغب (root lexicon) covers 46,199 words on its own.
    expect(stats.withLexicon, 46199);
    // Combined meaning coverage: غريب ∪ lexicon = 49,064 (63.4%).
    expect(stats.withMeaning, 49064);
    // A gloss exists for EVERY word (meaning or morphology description).
    expect(stats.withGloss, stats.total);
  });

  test('spot check: عَلَيْكَ (3:7) falls back to its morphology', () async {
    // The morphology word (QCF/morph orthography) is عَلَيۡكَ.
    const word = 'عَلَيۡكَ';
    final gloss = await QuranWordData.wordGloss(3, 7, word);
    expect(gloss, 'حرف جر');
    expect(await QuranWordData.glossSourceForWord(3, 7, word), 'morph');
    // And it has no غريب القرآن meaning (the original bug report).
    expect(await QuranWordData.meaningForWord(3, 7, word), isNull);
  });

  test('spot check: السَّمَاوَاتِ (2:29) comes from the root lexicon',
      () async {
    final words = await QuranWordData.wordsForAyah(2, 29);
    String? found;
    for (final w in words) {
      final lex = await QuranWordData.lexiconForWord(2, 29, w);
      if (lex != null && lex.startsWith('سَمَاءُ كلّ شيء: أعلاه')) {
        found = w;
        break;
      }
    }
    expect(found, isNotNull,
        reason: 'no word in 2:29 matched the سما lexicon entry');
    expect(
        await QuranWordData.glossSourceForWord(2, 29, found!), 'lexicon');
    final gloss = await QuranWordData.wordGloss(2, 29, found);
    expect(gloss, startsWith('سَمَاءُ كلّ شيء: أعلاه'));
  });

  test('spot check: five common words all have a non-blank gloss',
      () async {
    // (surah, verse, index into wordsForAyah) — real morph-orthography
    // words, taken from the bundled morphology itself.
    const picks = [
      (1, 1, 0), // بِسْمِ
      (1, 1, 1), // اللَّهِ
      (2, 255, 0), // اللَّهُ (آية الكرسي)
      (112, 1, 1), // هُوَ
      (36, 1, 0), // يس
    ];
    for (final (surah, verse, index) in picks) {
      final words = await QuranWordData.wordsForAyah(surah, verse);
      final word = words[index];
      final gloss = await QuranWordData.wordGloss(surah, verse, word);
      final source =
          await QuranWordData.glossSourceForWord(surah, verse, word);
      // ignore: avoid_print
      print('GLOSS $surah:$verse [$word] source=$source gloss=$gloss');
      expect(gloss.trim(), isNotEmpty, reason: '$surah:$verse $word');
      expect(source, isIn(['gharib', 'lexicon', 'morph']),
          reason: '$surah:$verse $word');
    }
  });
}
