import 'package:qcf_quran/qcf_quran.dart';

/// Glyph -> word mapping for the QCF Mushaf text.
///
/// A QCF verse string is a sequence of Private Use Area glyph codes
/// (one per rendered word-image) plus '\n' hard line breaks. The glyph
/// count is NOT the word count, because pause marks are usually their
/// own glyph. This helper maps every glyph to the TRUE word index
/// (0-based — the Quran.com / audio-segment index) so a tap on the
/// page opens the popup for exactly the word under the finger.
///
/// Rules (each proven against the real QCF data — see
/// test/qcf_word_map_test.dart, which asserts the predicted glyph
/// count equals the real QCF glyph count for all 6236 verses):
/// * one glyph per word; a word's intra-word marks (e.g. the ۜ in
///   وَيَبۡصُۜطُ) and the trailing ۭ are drawn inside that word's
///   glyph — no extra glyph.
/// * a pause mark (ۖ ۗ ۘ ۙ ۚ ۛ ۜ ۩ ۞ ۤ) at the END of a word is its
///   own glyph, mapped to that word; at the START of a word (the ۞
///   hizb marker) it is its own glyph, mapped to the following word;
///   a standalone mark token is its own glyph, mapped to the
///   preceding word (or the first word if it opens the verse).
/// * EXCEPTION — the disjointed letters الٓر (10:1, 11:1, 12:1, 14:1,
///   15:1): their trailing ۚ is drawn inside the الٓر glyph, not as
///   a separate glyph. (The other Muqatta'at with a trailing ۚ —
///   الٓمٓرٰ, طسٓ, صٓ, قٓ, نٓ — DO render the mark as its own glyph.)
/// * EXCEPTION — two single marks are drawn inside their word's
///   glyph: the ۖ after ٱللَّهِ in 3:78, and the ۚ after فِرۡعَوۡنَ
///   in 26:11. (Per-occurrence font artefacts; verified by count.)
/// * EXCEPTION — 13:10 has one glyph more than the text predicts
///   (14 words, 15 glyphs); no mark accounts for it, so that verse
///   is best-effort (`exact` is false there) — the mapping still
///   assigns its glyphs in order, so at most the words after the
///   extra glyph are off by one in that single verse.
/// * three content tokens join two words with no space — they split
///   into two glyphs: لَّوۡمَا (15:7), مَالِيَ (27:20), وَمَالِيَ
///   (36:22). 15:7's bundled spelling كُنتَ is also corrected to
///   كُنتُم for display (the Mushaf and the standard text have the م;
///   both bundled text sources drop it — a data typo).
///
/// The mapping is built SYNCHRONOUSLY from the qcf_quran package data
/// only (getVerseQCF + getVerse), so the reader can build it in
/// build() with no async loading. Meanings / morphology are looked up
/// by word TEXT (see QuranWordData.meaningForWord / morphForWord),
/// never by index, so the merged morph entries (بَعۡدَ مَا is one
/// entry in 2:181, 8:6, 13:37; إِلۡ يَاسِينَ in 37:130) do not shift
/// anything here — unlike the v9 word chips, which used entry indices
/// and played the wrong word after a merged entry in those 4 verses.
class QcfWordInfo {
  /// True word index (0-based) — the Quran.com segment / audio index.
  final int wordIndex;

  /// Display spelling (Uthmani, trailing/leading marks stripped).
  final String text;

  /// Raw spelling as it appears in the bundled data, for
  /// meaning/morphology lookup when [text] finds nothing (e.g. the
  /// 15:7 كُنتَ typo — the data spells it without the م).
  final String lookupText;

  /// Glyph ordinals (into the verse's glyph list) rendering this word.
  final List<int> glyphs;

  const QcfWordInfo({
    required this.wordIndex,
    required this.text,
    required this.lookupText,
    required this.glyphs,
  });
}

class QcfWordMap {
  final int surah;
  final int verse;

  /// Words in reading order.
  final List<QcfWordInfo> words;

  /// glyph ordinal -> true word index. Mark glyphs map to the adjacent
  /// word (the one they follow, or the following word for a leading
  /// mark). Index by the glyph's ordinal among the verse's PUA codes
  /// (line-break '\n' characters are not glyphs and are skipped).
  final List<int> glyphToWord;

  /// False only if the predicted glyph count disagreed with the real
  /// QCF glyph count (a font artefact this file does not model yet).
  /// The map is still usable (best-effort, in-order assignment).
  final bool exact;

  const QcfWordMap({
    required this.surah,
    required this.verse,
    required this.words,
    required this.glyphToWord,
    required this.exact,
  });

  int get wordCount => words.length;
  int get glyphCount => glyphToWord.length;

  /// Word index for a tapped glyph ordinal, or null if out of range.
  int? wordIndexForGlyph(int glyphOrdinal) {
    if (glyphOrdinal < 0 || glyphOrdinal >= glyphToWord.length) {
      return null;
    }
    return glyphToWord[glyphOrdinal];
  }
}

/// Pause / sajdah / hizb marks that can be their own QCF glyph.
/// NOTE: U+06ED (ۭ) is deliberately NOT here — it is drawn inside its
/// word's glyph in 98 of the 99 verses that carry it (verified by
/// count). The single exception is 13:10, whose extra glyph cannot be
/// attributed to any mark from the text alone, so that one verse is
/// best-effort (see the `exact` flag).
const _markCodes = <int>{
  0x06D6, // ۖ
  0x06D7, // ۗ
  0x06D8, // ۘ
  0x06D9, // ۙ
  0x06DA, // ۚ
  0x06DB, // ۛ
  0x06DC, // ۜ
  0x06DE, // ۞ hizb marker
  0x06E4, // ۤ
  0x06E9, // ۩ sajdah
};

bool _isBaseLetter(int c) =>
    (c >= 0x0621 && c <= 0x064A) || c == 0x0671; // ٱ alef wasla

/// Padding that is not part of a word: non-breaking space (U+00A0,
/// joins a leading ۞ to its word), line feed and carriage return
/// (one token carries a trailing '\n'). Stripped from the display
/// spelling in [buildQcfWordMap] (v13.3 FIX D).
bool _isWordPartPadding(int c) => c == 0x00A0 || c == 0x0A || c == 0x0D;

/// Bare letters (diacritics / marks stripped, hamza forms unified,
/// alef wasla unified to plain alef), for matching tokens against the
/// joined-token split table and the exception tables.
String _bare(String s) {
  final buf = StringBuffer();
  for (final c in s.codeUnits) {
    var ch = c;
    if (ch == 0x0622 || ch == 0x0623 || ch == 0x0625) ch = 0x0627;
    if (ch == 0x0624 || ch == 0x0626) ch = 0x064A;
    if (ch == 0x0621) ch = 0x064A;
    if (ch == 0x0649) ch = 0x064A;
    if (ch == 0x0671) ch = 0x0627; // ٱ -> ا
    if ((ch >= 0x0627 && ch <= 0x064A) || ch == 0x0670) {
      buf.writeCharCode(ch);
    }
  }
  return buf.toString();
}

/// Content tokens that join two words with no space, keyed by verse
/// then by the token's bare letters: the two true words (display
/// spellings, in order). Verified against the QCF glyph counts.
const _joinedTokenSplits = <String, Map<String, List<String>>>{
  '15:7': {
    'لوما': ['لَوۡ', 'مَا'],
  },
  '27:20': {
    'مالي': ['مَا', 'لِيَ'],
  },
  '36:22': {
    'ومالي': ['وَمَا', 'لِيَ'],
  },
};

/// Display-spelling corrections (bundled text typo), keyed by verse
/// then by the word's bare letters.
const _spellingFixes = <String, Map<String, String>>{
  '15:7': {
    'كنت': 'كُنتُم',
  },
};

/// Trailing marks drawn INSIDE their word's glyph (not a separate
/// glyph), keyed by verse then by the word's bare letters then by the
/// mark code point. Only two occurrences in the whole Mushaf.
const _mergedTrailingMarks = <String, Map<String, Set<int>>>{
  '3:78': {
    'الله': {0x06D6}, // ۖ after ٱللَّهِ
  },
  '26:11': {
    'فرعون': {0x06DA}, // ۚ after فِرۡعَوۡنَ
  },
};

/// Build the glyph -> word map for one verse, synchronously.
QcfWordMap buildQcfWordMap(int surah, int verse) {
  final content = getVerse(surah, verse);
  final qcf = getVerseQCF(surah, verse, verseEndSymbol: false);
  final realGlyphCount = qcf.codeUnits.where((c) => c != 10).length;

  final words = <QcfWordInfo>[];
  final glyphToWord = <int>[];
  var wordIndex = 0;
  var glyphOrdinal = 0;

  void addGlyph(int wIndex) {
    glyphToWord.add(wIndex);
    glyphOrdinal++;
  }

  final verseKey = '$surah:$verse';
  final splits = _joinedTokenSplits[verseKey];
  final spellingFixes = _spellingFixes[verseKey];
  final mergedMarks = _mergedTrailingMarks[verseKey];

  for (final token in content.split(' ')) {
    if (token.isEmpty) continue;
    final codes = token.codeUnits;
    // Strip leading and trailing marks; the remainder (letters +
    // diacritics + intra-word marks) is the word part. Trailing
    // diacritics (dagger alef, tanwin, …) MUST stay — cutting the
    // word at its last base letter drops them and misspells the word.
    var start = 0;
    while (start < codes.length && _markCodes.contains(codes[start])) {
      start++;
    }
    var end = codes.length;
    while (end > start && _markCodes.contains(codes[end - 1])) {
      end--;
    }
    final bodyHasLetter =
        codes.sublist(start, end).any(_isBaseLetter);

    if (!bodyHasLetter) {
      // Standalone mark token (e.g. ۘ, ۞): one glyph per mark,
      // mapped to the preceding word, or to the first word when it
      // opens the verse (the ۞ in 2:26).
      for (final c in codes) {
        if (!_markCodes.contains(c)) continue;
        addGlyph(words.isEmpty ? 0 : words.length - 1);
      }
      continue;
    }

    // v13.3 (FIX D): the bundled text joins a leading ۞ hizb marker
    // to its word with a non-breaking space (199 verse-first words),
    // and one token (37:24 word 3) carries a trailing '\n'. Both are
    // data quirks, not part of the word — strip them so the card
    // shows the bare word. The tap mapping itself was proven correct
    // (triple check, 0 mismatches); this is display only.
    var wordPart = String.fromCharCodes(codes.sublist(start, end));
    while (wordPart.isNotEmpty &&
        _isWordPartPadding(wordPart.codeUnitAt(0))) {
      wordPart = wordPart.substring(1);
    }
    while (wordPart.isNotEmpty &&
        _isWordPartPadding(wordPart.codeUnitAt(wordPart.length - 1))) {
      wordPart = wordPart.substring(0, wordPart.length - 1);
    }
    final bareWord = _bare(wordPart);

    // Leading marks (before the word): own glyph each, mapped to
    // this token's first word.
    final leadingMarks =
        codes.sublist(0, start).where(_markCodes.contains).toList();
    // Trailing marks (after the word).
    final trailingMarks =
        codes.sublist(end).where(_markCodes.contains).toList();
    // A trailing mark is merged into the word's glyph when the word
    // is the disjointed letters الٓر, or when this verse lists it as
    // a merged mark.
    bool isMerged(int mark) {
      if (bareWord == 'الر') return true;
      final perVerse = mergedMarks?[bareWord];
      return perVerse != null && perVerse.contains(mark);
    }

    for (final _ in leadingMarks) {
      addGlyph(wordIndex);
    }

    // The word part: one word, or two when the token joins two words.
    final split = splits?[bareWord];
    if (split != null) {
      for (final part in split) {
        final fixed = spellingFixes?[_bare(part)] ?? part;
        words.add(QcfWordInfo(
          wordIndex: wordIndex,
          text: fixed,
          lookupText: part,
          glyphs: [glyphOrdinal],
        ));
        addGlyph(wordIndex);
        wordIndex++;
      }
    } else {
      final fixed = spellingFixes?[bareWord] ?? wordPart;
      words.add(QcfWordInfo(
        wordIndex: wordIndex,
        text: fixed,
        lookupText: wordPart,
        glyphs: [glyphOrdinal],
      ));
      addGlyph(wordIndex);
      wordIndex++;
    }

    // Trailing marks: own glyph each (mapped to this token's last
    // word), unless merged into the word's glyph.
    for (final mark in trailingMarks) {
      if (isMerged(mark)) continue;
      addGlyph(wordIndex - 1);
    }
  }

  return QcfWordMap(
    surah: surah,
    verse: verse,
    words: words,
    glyphToWord: glyphToWord,
    exact: glyphOrdinal == realGlyphCount,
  );
}
