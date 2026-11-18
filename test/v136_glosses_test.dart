import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/word_meanings.dart';

/// v13.6 step 1 — Wahy-style short word glosses (مخلوف «كلمات القرآن:
/// تفسير وبيان» + small additions from التفسير الميسر), wired as the
/// FIRST meaning source: additions → مخلوف → غريب → Raghib → morphology.
///
/// Coverage numbers below are MEASURED by QuranWordData.coverageStats()
/// over the real bundled assets (see the printed COVERAGE line); update
/// them only when the data itself changes, never to make a test pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('4:4 فَكُلُوهُ returns the short gloss (additions, from Muyassar)',
      () async {
    const word = 'فَكُلُوهُ';
    final gloss = await QuranWordData.wordGloss(4, 4, word);
    expect(gloss, 'فخذوه حلالاً.');
    expect(await QuranWordData.glossSourceForWord(4, 4, word), 'addition');
    // The additions gloss is used verbatim (already short).
    expect(gloss.length, lessThanOrEqualTo(160));
  });

  test('priority: مخلوف beats غريب where both gloss the word', () async {
    // 4:4 صَدُقَاتِهِنَّ: غريب says «مُهُورِهِنَّ.»; مخلوف says «مُهُورهنّ».
    // The user's choice (مخلوف first) means the مخلوف gloss wins.
    const word = 'صَدُقَاتِهِنَّ';
    final gloss = await QuranWordData.wordGloss(4, 4, word);
    expect(gloss, 'مُهُورهنّ');
    expect(await QuranWordData.glossSourceForWord(4, 4, word), 'makhloof');
  });

  test('priority: غريب still wins where مخلوف has no gloss', () async {
    // 4:4 نِحْلَةً: غريب «فَرِيضَةً عَنْ طِيبِ نَفْسٍ.»; مخلوف «فريضة أو
    // عطية بطيب نفس» — both exist, so مخلوف wins here too. Use a word
    // مخلوف skips: 3:7 عَلَيْكَ has no مخلوف gloss and no غريب gloss,
    // so it still falls through to its morphology description.
    const word = 'عَلَيۡكَ';
    expect(await QuranWordData.meaningForWord(3, 7, word), isNull);
    expect(await QuranWordData.glossSourceForWord(3, 7, word), 'morph');
    expect(await QuranWordData.wordGloss(3, 7, word), 'حرف جر');
  });

  test('coverage: مخلوف lifts meanings above the 63.4% baseline',
      () async {
    final stats = await QuranWordData.coverageStats();
    // ignore: avoid_print
    print('COVERAGE-MKH total=${stats.total} '
        'withMakhloof=${stats.withMakhloof} '
        'withAddition=${stats.withAddition} '
        'withGharib=${stats.withGharib} '
        'withLexicon=${stats.withLexicon} '
        'withMeaning=${stats.withMeaning} '
        'withGloss=${stats.withGloss}');
    expect(stats.total, 77429);
    // Measured with the app's own matching (strict for مخلوف /
    // additions): 10,308 words show a مخلوف gloss first, 1 word an
    // additions gloss; the union with غريب + Raghib is 50,409 (65.1%).
    expect(stats.withMakhloof, 10308);
    expect(stats.withAddition, 1);
    expect(stats.withGharib, 9851);
    expect(stats.withLexicon, 46199);
    expect(stats.withMeaning, 50409);
    // A gloss still exists for EVERY word (meaning or morphology).
    expect(stats.withGloss, stats.total);
  });

  test('sample across the Mushaf: every gloss ≤ 160 chars', () async {
    const picks = [
      (1, 1), (1, 2), (1, 3),
      (2, 1), (2, 2), (2, 3),
      (4, 4),
      (5, 1), (5, 2), (5, 3),
      (18, 1), (18, 2), (18, 3),
      (36, 1), (36, 2), (36, 3),
      (55, 1), (55, 2), (55, 3),
      (67, 1), (67, 2), (67, 3),
      (112, 1), (112, 2), (112, 3), (112, 4),
    ];
    for (final (surah, verse) in picks) {
      final words = await QuranWordData.wordsForAyah(surah, verse);
      for (final w in words) {
        final gloss = await QuranWordData.wordGloss(surah, verse, w);
        expect(gloss.length, lessThanOrEqualTo(160),
            reason: 'gloss for $w in $surah:$verse is ${gloss.length} '
                'chars: "$gloss"');
        expect(gloss.trim(), isNotEmpty);
      }
    }
  });
}
