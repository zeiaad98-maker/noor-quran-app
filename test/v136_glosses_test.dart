import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/word_meanings.dart';

/// v13.6 step 1 — Wahy-style short word glosses (مخلوف «كلمات القرآن:
/// تفسير وبيان» + small additions from التفسير الميسر), wired as the
/// FIRST meaning source: additions → مخلوف → غريب → Raghib → morphology.
///
/// v13.11: the Tafsir Center meanings («ضيف معاني مركز تفسير») are
/// now the FIRST source (shown in full) and cover every word — the
/// مخلوف / additions glosses below are fallback-only, and the tests
/// pin the Center's text where it exists. The old sources' coverage
/// counts (10,308 مخلوف / 3 additions / 9,851 غريب / 46,199 lexicon)
/// are unchanged; only the union is now 100%.
///
/// Coverage numbers below are MEASURED by QuranWordData.coverageStats()
/// over the real bundled assets (see the printed COVERAGE line); update
/// them only when the data itself changes, never to make a test pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('4:4 فَكُلُوهُ returns the gloss (Tafsir Center, same text)',
      () async {
    const word = 'فَكُلُوهُ';
    final gloss = await QuranWordData.wordGloss(4, 4, word);
    // v13.11: the Tafsir Center text is byte-identical to the old
    // additions gloss here — «فخذوه حلالاً.» — but the source is now
    // the Center (first source).
    expect(gloss, 'فخذوه حلالاً.');
    expect(await QuranWordData.glossSourceForWord(4, 4, word),
        'tafsircenter');
    expect(gloss.length, lessThanOrEqualTo(160));
  });

  test('priority: Tafsir Center beats مخلوف where both gloss the word',
      () async {
    // 4:4 صَدُقَاتِهِنَّ: غريب says «مُهُورِهِنَّ.»; مخلوف says
    // «مُهُورهنّ»; the Tafsir Center says «مهورهن.» — first source
    // wins (v13.11).
    const word = 'صَدُقَاتِهِنَّ';
    final gloss = await QuranWordData.wordGloss(4, 4, word);
    expect(gloss, 'مهورهن.');
    expect(await QuranWordData.glossSourceForWord(4, 4, word),
        'tafsircenter');
  });

  test('priority: غريب still wins where مخلوف has no gloss', () async {
    // 4:4 نِحْلَةً: غريب «فَرِيضَةً عَنْ طِيبِ نَفْسٍ.»; مخلوف «فريضة أو
    // عطية بطيب نفس» — both exist, so مخلوف wins here too. Use a word
    // مخلوف skips: 3:7 عَلَيْكَ has no مخلوف gloss and no غريب gloss —
    // v13.11: the Tafsir Center glosses it («على: حرف جر بمعنى "إلى".
    // "ك": ضمير مخاطب.»), so it no longer falls through to morphology.
    const word = 'عَلَيۡكَ';
    expect(await QuranWordData.meaningForWord(3, 7, word),
        'على: حرف جر بمعنى "إلى". "ك": ضمير مخاطب.');
    expect(await QuranWordData.glossSourceForWord(3, 7, word),
        'tafsircenter');
    expect(await QuranWordData.wordGloss(3, 7, word),
        'على: حرف جر بمعنى "إلى". "ك": ضمير مخاطب.');
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
    // additions): 10,322 words show a مخلوف gloss first (was 10,308
    // before the v13.11 normalizeArabic fix), 3 words an additions
    // gloss (4:4 + v13.9: 15:11، 15:12); غريب 11,855 (was 9,851
    // before the same fix); the union with غريب + Raghib was 50,411
    // (65.1%) — v13.11: the Tafsir Center covers every word, so the
    // union is 77,429 (100%).
    expect(stats.withMakhloof, 10322);
    expect(stats.withAddition, 3);
    expect(stats.withGharib, 11855);
    expect(stats.withLexicon, 46199);
    expect(stats.withMeaning, 77429);
    // A gloss still exists for EVERY word (meaning or morphology).
    expect(stats.withGloss, stats.total);
  });

  test('sample across the Mushaf: every gloss is non-empty', () async {
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
        // v13.11: Tafsir Center meanings are shown in full, so a
        // gloss may exceed 160 chars — it must only be non-empty.
        expect(gloss.trim(), isNotEmpty);
      }
    }
  });
}
