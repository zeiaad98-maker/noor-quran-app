import 'package:flutter_test/flutter_test.dart';
import 'package:quran/quran.dart' as quran;

import 'package:noor_quran/data/word_meanings.dart';

/// v9 word-audio bug: the ayah sheet built its word chips from the
/// `quran` package's SIMPLE text (`getVerse(...).split(' ')`), but
/// Quran.com's word audio (segments + wbw files) numbers words in
/// UTHMANI order. For 2:33 the simple text has 24 tokens
/// (`يَا` + `آدَمُ` split, plus a standalone `ۖ`) while the audio has
/// 22 words — so taps played the WRONG word, and the last chips
/// 404'd on wbw (`..._023.mp3`, `..._024.mp3` do not exist).
/// These tests pin the fix: word indices come from the bundled
/// Uthmani word list (QuranWordData.wordsForAyah).
///
/// NOTE (v13.2): the segment tests that lived here
/// (parseWordSegments / fetchWordSegments) are gone with the deleted
/// segment subsystem — the word plays ONLY its wbw file now. The
/// Uthmani-alignment tests stay: the wbw file number is derived from
/// this token order (via the shift table), so a drift here breaks
/// word audio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wordsForAyah: Uthmani list is segment-aligned (2:33 = 22)', () async {
    final words = await QuranWordData.wordsForAyah(2, 33);
    expect(words.length, 22);
    // Word 2 is the SINGLE Uthmani token يَـٰٓـَٔادَمُ (the old simple
    // split made it two chips: يَا + آدَمُ). Its normalized form is
    // 'ياادم' — the dagger alef is a real alef here (the vocative
    // يَا + آدَمُ); the v12 normalizeArabic fix keeps it instead of
    // stripping it (the old expectation 'يادم' lost that letter).
    expect(QuranWordData.normalizeArabic(words[1]), 'ياادم');
    expect(QuranWordData.normalizeArabic(words[21]), 'تكتمون');
    // And the pause mark is attached to its word, not a token.
    expect(words.any((w) => w.trim() == 'ۖ'), isFalse);

    // Spot checks against the live API segment counts (verified
    // 2026-11-16): 2:25 = 34, 2:26 = 39, 2:255 = 50, 1:1 = 4.
    expect((await QuranWordData.wordsForAyah(2, 25)).length, 34);
    expect((await QuranWordData.wordsForAyah(2, 26)).length, 39);
    expect((await QuranWordData.wordsForAyah(2, 255)).length, 50);
    expect((await QuranWordData.wordsForAyah(1, 1)).length, 4);
  });

  test('the old simple-text split really differs (documents the bug)', () {
    final simple = quran
        .getVerse(2, 33)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    expect(simple.length, 24);
    expect(simple[1], 'يَا');
    expect(simple[2], 'آدَمُ');
    expect(simple[5], 'ۖ');
  });
}
