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
///
/// v12 — dagger-alef fix (normalizeArabic: ٰ -> ا, except on ى):
///   withGharib 9,079 -> 9,851 (+772: words whose Uthmani spelling
///   uses a dagger alef where the غريب entry has a plain alef, e.g.
///   مُّحۡكَمَٰتٌ = مُّحْكَمَاتٌ). withMeaning 49,064 -> 49,054
///   (-10: a few words whose غريب entries spell them WITHOUT the
///   alef the dagger represents, e.g. ذَٰلِكَ vs ذَلِكَ — they keep
///   their morphology gloss, so withGloss stays 100%).
///
/// v13.9 — two more verified additions glosses from التفسير الميسر
///   (15:11 يَسْتَهْزِئُونَ «يسخرون به.»، 15:12 كَذَٰلِكَ «مثل ذلك.»):
///   withAddition 1 -> 3, withMeaning 50,409 -> 50,411.
///
/// v13.11 — the Tafsir Center meanings («ضيف معاني مركز تفسير»)
///   are the FIRST source and cover every word: withMeaning
///   50,411 -> 77,429 (100%). The older sources stay as fallbacks.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coverage: lexicon lifts meanings far above the 11.5% baseline',
      () async {
    final stats = await QuranWordData.coverageStats();
    // Printed so the run log records the measured numbers.
    // ignore: avoid_print
    print('COVERAGE total=${stats.total} '
        'withMakhloof=${stats.withMakhloof} '
        'withAddition=${stats.withAddition} '
        'withGharib=${stats.withGharib} '
        'withLexicon=${stats.withLexicon} withMeaning=${stats.withMeaning} '
        'withGloss=${stats.withGloss}');
    expect(stats.total, 77429);
    // مخلوف short glosses (v13.6, strict matching) cover 10,322 words
    // as first source (was 10,308 before the v13.11 normalizeArabic
    // fix — the ءا→ا collapse matches 14 more words); the additions
    // file covers 3 words (4:4 فَكُلُوهُ + v13.9: 15:11
    // يَسْتَهْزِئُونَ، 15:12 كَذَٰلِكَ).
    expect(stats.withMakhloof, 10322);
    expect(stats.withAddition, 3);
    // غريب القرآن alone covered 9,079 (11.7%) before the lexicon,
    // 9,851 after the v12 dagger-alef fix (see the header comment),
    // 11,855 after the v13.11 normalizeArabic fix (open tanwin +
    // U+065E + ءا→ا collapse match ~2,000 more words).
    expect(stats.withGharib, 11855);
    // مفردات الراغب (root lexicon) covers 46,199 words on its own.
    expect(stats.withLexicon, 46199);
    // Combined meaning coverage: Tafsir Center covers every word —
    // 77,429 (100%). The older sources (additions ∪ مخلوف ∪ غريب ∪
    // lexicon) reached 50,411 (65.1%) before v13.11.
    expect(stats.withMeaning, 77429);
    // A gloss exists for EVERY word (meaning or morphology description).
    expect(stats.withGloss, stats.total);
  });

  test('spot check: عَلَيْكَ (3:7) now has a Tafsir Center meaning',
      () async {
    // The morphology word (QCF/morph orthography) is عَلَيۡكَ.
    // v13.11: the Tafsir Center glosses the particle AND its pronoun
    // («على: حرف جر بمعنى "إلى". "ك": ضمير مخاطب.») — the word that
    // used to fall back to its bare morphology description «حرف جر».
    const word = 'عَلَيۡكَ';
    final gloss = await QuranWordData.wordGloss(3, 7, word);
    expect(gloss, 'على: حرف جر بمعنى "إلى". "ك": ضمير مخاطب.');
    expect(await QuranWordData.glossSourceForWord(3, 7, word),
        'tafsircenter');
    expect(await QuranWordData.meaningForWord(3, 7, word), isNotNull);
  });

  test('spot check: السَّمَاوَاتِ (2:29) comes from the Tafsir Center',
      () async {
    final words = await QuranWordData.wordsForAyah(2, 29);
    // The PLURAL سَمَاوَاتِ (not the singular السَّمَاءِ in the مخلوف
    // phrase «اسْتَوَى إِلَى السَّمَاءِ», which مخلوف now glosses).
    final found = words.firstWhere(
      (w) => QuranWordData.normalizeArabic(w).contains('سماوات'),
      orElse: () => '',
    );
    expect(found, isNotEmpty,
        reason: 'no plural سَمَاوَاتِ word in 2:29 (words: $words)');
    // v13.11: displayed gloss from the Tafsir Center (first source).
    expect(
        await QuranWordData.glossSourceForWord(2, 29, found), 'tafsircenter');
    final gloss = await QuranWordData.wordGloss(2, 29, found);
    expect(gloss, startsWith('ما يقابل الأرض، وعددها سبع'));
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
      expect(source,
          isIn([
            'tafsircenter',
            'addition',
            'makhloof',
            'gharib',
            'lexicon',
            'morph'
          ]),
          reason: '$surah:$verse $word');
    }
  });
}
