import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/word_meanings.dart';

/// v13.2 — short plain word meanings.
///
/// مخلوف "كلمات القرآن: تفسير وبيان" is NOT in Dalail (checked
/// 2026-11-17: search_titles / search_books / search_authors — the
/// library holds only a 20-page critique of it, book_id=712, not the
/// book itself; حسنين مخلوف is not in the author index). So the
/// v13.2 fix is the truncation fallback: غريب القرآن when present,
/// else the FIRST sentence of the Raghib root entry (max ~120 chars),
/// with a clarity guard — a fragmentary first sentence (< 25 chars)
/// keeps the next sentence/clause, so the meaning stays UNDERSTOOD
/// (the user's condition: "اختصر وهيك بس يكون مفهوم المعنى").
/// Truncation only shortens; nothing is rewritten or invented.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The morphology-orthography word of an ayah whose normalized
  /// form equals [plain] (e.g. 'فَأَخْرَجَهُمَا').
  Future<String> wordInAyah(int surah, int verse, String plain) async {
    final words = await QuranWordData.wordsForAyah(surah, verse);
    final norm = QuranWordData.normalizeArabic(plain);
    for (final w in words) {
      if (QuranWordData.normalizeArabic(w) == norm) return w;
    }
    fail('word $plain not found in $surah:$verse (words: $words)');
  }

  group('shortenGloss (pure unit tests, no assets)', () {
    test('short text is returned as-is', () {
      expect(QuranWordData.shortenGloss('أَوْقَعَهُمَا فِي الْخَطِيئَةِ.'),
          'أَوْقَعَهُمَا فِي الْخَطِيئَةِ.');
    });

    test('long Raghib entry: first sentence only, then first clause', () {
      // Full خرج entry (130 chars, no sentence terminator): the core
      // definition is its first clause.
      const full =
          'خَرَجَ خُرُوجاً: برز من مقرّه أو حاله، سواء كان مقرّه دارا، أو بلدا، أو ثوبا، وسواء كان حاله حالة في نفسه، أو في أسبابه الخارجة';
      expect(QuranWordData.shortenGloss(full),
          'خَرَجَ خُرُوجاً: برز من مقرّه أو حاله');
    });

    test('first sentence ends at the first . or ؛', () {
      const full =
          'الوِقَايَةُ: حفظُ الشيءِ ممّا يؤذيه ويضرّه. يقال: وَقَيْتُ الشيءَ أَقِيهِ وِقَايَةً ووِقَاءً، وهذا شرح طويل جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا';
      expect(QuranWordData.shortenGloss(full),
          'الوِقَايَةُ: حفظُ الشيءِ ممّا يؤذيه ويضرّه.');
    });

    test('fragmentary first sentence keeps the next sentence (clarity)',
        () {
      // "أي: دنت القيامة." alone (16 chars) is a fragment; the next
      // sentence carries the definition. Citation sentences are skipped.
      const full =
          'أي: دنت القيامة. وأزف وأفد يتقاربان، لكن أزف يقال اعتباراً بضيق وقتها، ويقال: أزف الشخوص، والأَزَفُ: ضيق الوقت، وسمّيت به لقرب كونها، وعلى ذلك عبّر عنها بالسّاعة، وقيل: أَتى أَمْرُ اللَّهِ ، فعبّر عن ذلك بأزف';
      final short = QuranWordData.shortenGloss(full);
      expect(short.length, lessThanOrEqualTo(160));
      expect(short, startsWith('أي: دنت القيامة.'));
      expect(short, contains('وأزف وأفد يتقاربان'));
    });

    test('citation clause is never the added clarity text', () {
      const full =
          'أي: جماعة منفردة. قال الشاعر: ٨٠- وقد أغدو على ثبة كرام ومنه: ثَبَّيْتُ على فلان ، أي: ذكرت متفرّق محاسنه. ويصغر ثُبَيَّة، ويجمع على ثُبَاتٍ وثُبِين، والمحذوف منه اللام، وأمّا ثُبَة الحوض فوسطه الذي يجتمع فيه الماء، وهذا شرح طويل جدا جدا جدا جدا جدا جدا جدا جدا جدا جدا';
      final short = QuranWordData.shortenGloss(full);
      expect(short, isNot(contains('قال الشاعر')));
      expect(short, contains('جماعة منفردة'));
    });

    test('no sentence or clause boundary: hard cap at 160 with …', () {
      final long = 'كلمة' * 60; // 240 chars, no spaces or terminators
      final short = QuranWordData.shortenGloss(long);
      expect(short.length, lessThanOrEqualTo(160));
      expect(short, endsWith('…'));
    });
  });

  group('sample words from the user report', () {
    test('2:36 فَأَخْرَجَهُمَا — short, plain, understood', () async {
      final word = await wordInAyah(2, 36, 'فَأَخْرَجَهُمَا');
      final gloss = await QuranWordData.wordGloss(2, 36, word);
      // Printed so the run log records the exact displayed text.
      // ignore: avoid_print
      print('GLOSS 2:36 فَأَخْرَجَهُمَا = "$gloss" (${gloss.length} chars)');
      expect(gloss, 'خَرَجَ خُرُوجاً: برز من مقرّه أو حاله');
      expect(gloss.length, lessThanOrEqualTo(160));
      // It comes from the Raghib root lexicon (no غريب entry here).
      expect(await QuranWordData.glossSourceForWord(2, 36, word),
          'lexicon');
      // Understandability: "خرج خروجاً: برز من مقره أو حاله" — a
      // plain reader learns فَأَخْرَجَهُمَا = he brought them OUT
      // (of where they were). The old text ran 130 chars of
      // dictionary elaboration; the core definition is kept whole.
    });

    test('5:4 وَاتَّقُوا — short, plain, understood', () async {
      final word = await wordInAyah(5, 4, 'وَاتَّقُوا');
      final gloss = await QuranWordData.wordGloss(5, 4, word);
      // ignore: avoid_print
      print('GLOSS 5:4 وَاتَّقُوا = "$gloss" (${gloss.length} chars)');
      expect(gloss,
          'الوِقَايَةُ: حفظُ الشيءِ ممّا يؤذيه ويضرّه. يقال: وَقَيْتُ الشيءَ أَقِيهِ وِقَايَةً ووِقَاءً');
      expect(gloss.length, lessThanOrEqualTo(160));
      expect(
          await QuranWordData.glossSourceForWord(5, 4, word), 'lexicon');
      // Understandability: "الوقاية: حفظ الشيء مما يؤذيه ويضره" —
      // a plain reader learns وَاتَّقُوا = guard/protect yourselves
      // (from what harms you). The old text was this same entry
      // unshortened; here the whole entry already fits, so nothing
      // is lost — the fix matters for the long entries, not this one.
    });

    test('every word of 2:36 and 5:4 shows a gloss ≤ 160 chars',
        () async {
      for (final (surah, verse) in [(2, 36), (5, 4)]) {
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
  });

  test('sample across the Mushaf: every gloss ≤ 160 chars', () async {
    // First 3 ayahs of a spread of surahs (short + long, Makki + Madani).
    const picks = [
      (1, 1), (1, 2), (1, 3),
      (2, 1), (2, 2), (2, 3),
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
      }
    }
  });

  test('corpus: short-gloss coverage and length stats', () async {
    final stats = await QuranWordData.glossLengthStats();
    final coverage = await QuranWordData.coverageStats();
    // ignore: avoid_print
    print('GLOSS-STATS total=${stats.total} '
        'withShortMeaning=${stats.withShortMeaning} '
        'medianLength=${stats.medianLength} maxLength=${stats.maxLength} '
        'over160=${stats.over160} over120=${stats.over120}');
    expect(stats.total, 77429);
    // Shortening never drops a meaning: same count as before.
    expect(stats.withShortMeaning, coverage.withMeaning);
    expect(stats.withShortMeaning, 49054);
    // 49,054 / 77,429 = 63.4% of words have a short meaning gloss.
    expect(stats.withShortMeaning / stats.total, greaterThan(0.63));
    // NO displayed gloss exceeds the 160-char cap.
    expect(stats.over160, 0);
    expect(stats.maxLength, lessThanOrEqualTo(160));
    // Median displayed gloss is a short phrase, not a dictionary page.
    expect(stats.medianLength, lessThanOrEqualTo(120));
  });

  test('v12 regression: 2:29 السَّمَاوَاتِ still starts with its definition',
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
    expect(found, isNotNull);
    final gloss = await QuranWordData.wordGloss(2, 29, found!);
    expect(gloss, startsWith('سَمَاءُ كلّ شيء: أعلاه'));
    expect(gloss.length, lessThanOrEqualTo(160));
  });
}
