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
///
/// v13.11: the Tafsir Center meanings are now the FIRST source and
/// are shown in FULL (never shortened) — so the wordGloss samples
/// below pin the Center's text, and the ≤ 160-char invariant no
/// longer holds for displayed glosses (measured over160 = 4,642,
/// max 720). The shortenGloss unit tests still apply to the
/// FALLBACK branches (additions / مخلوف / غريب / Raghib) and to the
/// function itself.
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
    test('2:36 فَأَخْرَجَهُمَا — Tafsir Center meaning, in full', () async {
      final word = await wordInAyah(2, 36, 'فَأَخْرَجَهُمَا');
      final gloss = await QuranWordData.wordGloss(2, 36, word);
      // Printed so the run log records the exact displayed text.
      // ignore: avoid_print
      print('GLOSS 2:36 فَأَخْرَجَهُمَا = "$gloss" (${gloss.length} chars)');
      expect(gloss, 'فتسبب في إخراجهما. والإخراج: الإبعاد والطرد والتنحية.');
      expect(gloss.length, lessThanOrEqualTo(160));
      // v13.11: it comes from the Tafsir Center (first source).
      expect(await QuranWordData.glossSourceForWord(2, 36, word),
          'tafsircenter');
      // Understandability: "فتسبب في إخراجهما" — a plain reader
      // learns فَأَخْرَجَهُمَا = he caused them to be brought OUT
      // (of where they were).
    });

    test('5:4 وَاتَّقُوا — Tafsir Center meaning, in full', () async {
      final word = await wordInAyah(5, 4, 'وَاتَّقُوا');
      final gloss = await QuranWordData.wordGloss(5, 4, word);
      // ignore: avoid_print
      print('GLOSS 5:4 وَاتَّقُوا = "$gloss" (${gloss.length} chars)');
      expect(gloss,
          'احذروا واجعلوا لكم وقاية تحميكم وتقيكم. والتقوى: أن يجعل العبد بينه وبين غضب الله وعقابه وقاية؛ بفعل أمره وترك معصيته.');
      expect(gloss.length, lessThanOrEqualTo(160));
      expect(
          await QuranWordData.glossSourceForWord(5, 4, word), 'tafsircenter');
      // Understandability: "احذروا واجعلوا لكم وقاية" — a plain
      // reader learns وَاتَّقُوا = guard/protect yourselves (from
      // what harms you).
    });

    test('every word of 2:36 and 5:4 shows a non-empty gloss', () async {
      for (final (surah, verse) in [(2, 36), (5, 4)]) {
        final words = await QuranWordData.wordsForAyah(surah, verse);
        for (final w in words) {
          final gloss = await QuranWordData.wordGloss(surah, verse, w);
          // v13.11: Tafsir Center meanings are shown in full, so a
          // gloss may exceed 160 chars — it must only be non-empty.
          expect(gloss.trim(), isNotEmpty);
        }
      }
    });
  });

  test('sample across the Mushaf: every sampled word shows a gloss',
      () async {
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
        // v13.11: full Tafsir Center text — non-empty is the check.
        expect(gloss.trim(), isNotEmpty,
            reason: 'blank gloss for $w in $surah:$verse');
      }
    }
  });

  test('corpus: meaning coverage and length stats', () async {
    final stats = await QuranWordData.glossLengthStats();
    final coverage = await QuranWordData.coverageStats();
    // ignore: avoid_print
    print('GLOSS-STATS total=${stats.total} '
        'withShortMeaning=${stats.withShortMeaning} '
        'medianLength=${stats.medianLength} maxLength=${stats.maxLength} '
        'over160=${stats.over160} over120=${stats.over120}');
    expect(stats.total, 77429);
    // Showing the meaning never drops it: same count as before.
    expect(stats.withShortMeaning, coverage.withMeaning);
    expect(stats.withShortMeaning, 77429);
    // 77,429 / 77,429 = 100% of words have a meaning gloss (v13.11:
    // the Tafsir Center source covers every word; v13.6 مخلوف +
    // additions lifted it from 49,054 / 63.4% to 50,411 / 65.1%).
    expect(stats.withShortMeaning, stats.total);
    // v13.11: Tafsir Center meanings are shown in FULL, so long
    // entries exist (measured: 4,636 over 160 chars, max 717) —
    // that is the approved behaviour, not a regression.
    expect(stats.over160, 4636);
    expect(stats.maxLength, 717);
    // Median displayed gloss is still a short phrase (35 chars).
    expect(stats.medianLength, lessThanOrEqualTo(120));
  });

  test('v12 regression: 2:29 السَّمَاوَاتِ still starts with its definition',
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
    // The Raghib root-lexicon entry is unchanged (fallback source).
    final lex = await QuranWordData.lexiconForWord(2, 29, found);
    expect(lex, isNotNull);
    expect(lex!, startsWith('سَمَاءُ كلّ شيء: أعلاه'));
    // v13.11: the displayed gloss now comes from the Tafsir Center
    // (first source) — «ما يقابل الأرض، وعددها سبع، ولها أبواب تفتح.»
    final gloss = await QuranWordData.wordGloss(2, 29, found);
    expect(gloss, startsWith('ما يقابل الأرض، وعددها سبع'));
    expect(await QuranWordData.glossSourceForWord(2, 29, found),
        'tafsircenter');
  });
}
