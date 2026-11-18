import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quran/quran.dart' as quran;

import 'qcf_word_map.dart';

/// Offline Quran word data (Quranpedia dumps, bundled under assets/quran_data):
/// - word meanings (غريب القرآن — السراج في بيان غريب القرآن، مع التبيان كبديل)
/// - Tafsir Center word meanings (v13.11, the user's pick — «ضيف معاني
///   مركز تفسير»): the Center's own word-by-word compilation, CC BY 4.0,
///   FIRST meaning source, shown in FULL (never shortened) — it covers
///   100% of words, so the older sources below are fallback-only.
/// - Tafsir Center per-word sarf + per-word i'rab (v13.11, his order
///   «ضيف الصرف والإعراب هلأ مع هالنسخة»): the same dataset/licence,
///   FIRST source for the التصريف/الإعراب tabs, shown in FULL (never
///   shortened) — 100% coverage, so the simplified morphology below is
///   fallback-only. Whole-ayah i'rab is NOT bundled (new feature
///   needing design — later version).
/// - short in-ayah glosses (مخلوف «كلمات القرآن: تفسير وبيان»، v13.6)
///   + small additions condensed from التفسير الميسر where مخلوف has
///   none (e.g. 4:4 فَكُلُوهُ = «فخذوه حلالاً.») — fallback-only since
///   v13.11 (the Tafsir Center source above covers every word).
/// - word lexicon (مفردات ألفاظ القرآن للراغب الأصفهاني، ت ٥٠٢هـ،
///   keyed by normalized root; consulted after غريب القرآن)
/// - التفسير الميسر (كاملاً، آية بآية)
/// - simplified morphology / i'rab (Quranic Arabic Corpus via Quranpedia)
/// - hizb-quarter boundaries (240 quarter starts, from alquran.cloud metadata)
///
/// All files are loaded lazily on first use and cached in memory.
class QuranWordData {
  static Map<String, dynamic>? _meanings;
  static Map<String, dynamic>? _tafsirCenter;
  static Map<String, dynamic>? _sarfTC;
  static Map<String, dynamic>? _irabTC;
  static Map<String, dynamic>? _makhloof;
  static Map<String, dynamic>? _additions;
  static Map<String, dynamic>? _lexicon;
  static Map<String, dynamic>? _tafsir;
  static Map<String, dynamic>? _morphology;
  static List<List<int>>? _quarters;
  static bool _loading = false;
  static Future<void>? _loadFuture;

  /// NOTE (v11, widget tests): the old form returned the shared
  /// [_loadFuture] directly. A future completed in one zone (real
  /// async in runAsync, or another test's FakeAsync) never fires its
  /// callbacks inside a different zone's pump loop, so a popup opened
  /// in a later test would spin its loader forever. The async fast
  /// path below returns a fresh future created in the CALLER's zone
  /// once the data is loaded, so awaits always resolve on the next
  /// pump. On a real device the behaviour is identical (one extra
  /// microtask); the cold path is unchanged. [_quarters] is set last
  /// in [_loadAll], so it is the loaded signal.
  static Future<void> ensureLoaded() async {
    if (_quarters != null) return;
    _loadFuture ??= _loadAll();
    await _loadFuture!;
  }

  static Future<void> _loadAll() async {
    if (_loading) return;
    _loading = true;
    final meaningsRaw =
        await rootBundle.loadString('assets/quran_data/word_meanings.json');
    // Tafsir Center meanings (v13.11) — the primary meaning source,
    // loaded like غريب القرآن (required, not optional).
    final tafsirCenterRaw = await rootBundle
        .loadString('assets/quran_data/word_meanings_tafsircenter.json');
    // Tafsir Center per-word sarf + per-word i'rab (v13.11) — the
    // primary source for the التصريف/الإعراب tabs, required like the
    // meanings above (same dataset, same CC BY 4.0 licence).
    final sarfTCRaw = await rootBundle
        .loadString('assets/quran_data/word_sarf_tafsircenter.json');
    final irabTCRaw = await rootBundle
        .loadString('assets/quran_data/word_irab_tafsircenter.json');
    // مخلوف short glosses + additions are optional like the lexicon:
    // a missing/corrupt file must not break the rest of the word data.
    try {
      final makhRaw = await rootBundle
          .loadString('assets/quran_data/word_glosses_makhloof.json');
      _makhloof = jsonDecode(makhRaw) as Map<String, dynamic>;
    } catch (_) {
      _makhloof = <String, dynamic>{};
    }
    try {
      final addRaw = await rootBundle
          .loadString('assets/quran_data/word_gloss_additions.json');
      _additions = jsonDecode(addRaw) as Map<String, dynamic>;
    } catch (_) {
      _additions = <String, dynamic>{};
    }
    // The lexicon is optional: a missing/corrupt file must not break
    // the rest of the word data (meanings, tafsir, morphology).
    try {
      final lexRaw =
          await rootBundle.loadString('assets/quran_data/word_lexicon.json');
      _lexicon = jsonDecode(lexRaw) as Map<String, dynamic>;
    } catch (_) {
      _lexicon = <String, dynamic>{};
    }
    final tafsirRaw =
        await rootBundle.loadString('assets/quran_data/tafsir_muyassar.json');
    final morphRaw =
        await rootBundle.loadString('assets/quran_data/word_morphology.json');
    final quartersRaw =
        await rootBundle.loadString('assets/quran_data/hizb_quarters.json');
    _meanings = jsonDecode(meaningsRaw) as Map<String, dynamic>;
    _tafsirCenter = jsonDecode(tafsirCenterRaw) as Map<String, dynamic>;
    _sarfTC = jsonDecode(sarfTCRaw) as Map<String, dynamic>;
    _irabTC = jsonDecode(irabTCRaw) as Map<String, dynamic>;
    _tafsir = jsonDecode(tafsirRaw) as Map<String, dynamic>;
    _morphology = jsonDecode(morphRaw) as Map<String, dynamic>;
    final quartersJson = jsonDecode(quartersRaw) as List<dynamic>;
    _quarters = quartersJson
        .map((e) => <int>[e[0] as int, e[1] as int])
        .toList(growable: false);
  }

  /// Strip diacritics / tatweel and unify alef forms, for word matching.
  /// Spaces are removed so multi-word phrases match single tapped words.
  static String normalizeArabic(String input) {
    var s = input;
    // Dagger alef ٰ is usually a REAL alef (e.g. مُّحۡكَمَٰتٌ =
    // مُّحْكَمَاتٌ, ٱلصَّلَوٰةَ = ٱلصَّلَاةَ): convert it to a plain
    // ا, do NOT strip it — stripping loses the letter and breaks
    // matching against the morphology / غريب القرآن entries (v12
    // fix). EXCEPT on an alef maqsura (مُوسَىٰ): there the ى already
    // carries the long-a and the dagger alef is only a pronunciation
    // mark — drop it, or مُوسَىٰ would no longer match مُوسَى.
    s = s.replaceAll('\u0649\u0670', '\u0649'); // ىٰ -> ى
    s = s.replaceAll('\u0670', '\u0627'); // ٰ -> ا
    // Hamza-above U+0654 / hamza-below U+0655 on a seat letter is a
    // REAL hamza letter, not a diacritic: the Uthmani asset writes
    // it as ئ (ya + hamza-above, e.g. ٱلسَّيّئُ in 35:43) while
    // the reader's QCF text writes the same word with the
    // precomposed ئ (ٱلسَّيِّئُ) — and مخلوف writes it a third way,
    // with hamza-BELOW (يٕ). Unify the seat+hamza to the
    // precomposed letter BEFORE the strip below, or the strip
    // deletes the hamza on one side only (asset norm السيي vs QCF
    // norm السيئ) and the word silently loses its meaning/sarf/
    // irab (v13.11 fix — the last unmatched display word in the
    // whole Mushaf, 35:43 word 9; the same fix also keeps its
    // مخلوف match, whose entry uses the hamza-below spelling).
    // The tatweel seat (ـٔ, 495 words, e.g. أَنۢبِـُٔونِي) needs
    // no such rule: both sides write it the same way and the strip
    // removes the tatweel + hamza identically on both.
    s = s.replaceAll('\u064A\u0654', '\u0626'); // ئ -> ئ
    s = s.replaceAll('\u0648\u0654', '\u0624'); // ؤ -> ؤ
    s = s.replaceAll('\u0627\u0654', '\u0623'); // أ -> أ
    s = s.replaceAll('\u064A\u0655', '\u0626'); // يٕ -> ئ
    s = s.replaceAll('\u0648\u0655', '\u0624'); // وٕ -> ؤ
    s = s.replaceAll('\u0627\u0655', '\u0625'); // إ -> إ
    // Strip diacritics + tatweel + small marks — INCLUDING the open
    // tanwin U+08F0–U+08F2 (v13.11 fix): the Tafsir Center asset uses
    // Uthmani open tanwin (6,643 words, e.g. ءَايَٰتࣱ ends U+08F1)
    // while the reader's QCF text uses closed tanwin (آيَاتٌ ends
    // U+064C) — without this the two spellings never match and the
    // word falls back to the old (possibly wrong) gloss. The range
    // runs to U+065F to cover the QCF font's U+065E mark (fatha with
    // two dots, the dammatan in e.g. آيَاتٌ's QCF lookup text).
    s = s.replaceAll(
        RegExp(r'[\u064B-\u065F\u0640\u06D6-\u06ED\u08F0-\u08F2]'), '');
    s = s.replaceAll('\u0622', '\u0627'); // آ -> ا
    // Uthmani hamza+alef IS a madda: ءَايَٰتࣱ (asset/morphology) and
    // آيَاتٌ (QCF text) are the same word — collapse ءا to ا after
    // the diacritics are gone, or the match fails (v13.11 fix).
    s = s.replaceAll('\u0621\u0627', '\u0627'); // ءا -> ا
    s = s.replaceAll('\u0623', '\u0627'); // أ -> ا
    s = s.replaceAll('\u0625', '\u0627'); // إ -> ا
    s = s.replaceAll('\u0671', '\u0627'); // ٱ -> ا
    s = s.replaceAll('\u0649', '\u064A'); // ى -> ي
    s = s.replaceAll('\u0629', '\u0647'); // ة -> ه
    s = s.replaceAll(RegExp(r'\s+'), '');
    // Last guard: after all the unifications above, a word is ONLY
    // Arabic letters — drop any mark the ranges above missed (a
    // stray mark here silently breaks the meaning lookup for that
    // word, which is exactly how آيَاتٌ lost its meaning).
    s = s.replaceAll(RegExp(r'[^\u0621-\u064A]'), '');
    return s;
  }

  static String _key(int surah, int verse) => '$surah:$verse';

  /// Ordered Uthmani words of an ayah, aligned 1:1 with Quran.com's
  /// word-audio segments (segment i = words[i], 0-based).
  ///
  /// Source: the bundled morphology dump (Quranic Arabic Corpus word
  /// list — Uthmani orthography, e.g. `يَٰٓـَٔادَمُ` is ONE word and the
  /// pause mark ۖ stays attached to its word). The `quran` package's
  /// simple text must NOT be used for audio indices: it splits
  /// `يَا آدَمُ` into two tokens and leaves ۖ as a token of its own,
  /// so 2:33 has 24 simple tokens but only 22 audio segments — the
  /// old word chips passed the simple index, playing the wrong word
  /// and 404-ing on the last chips (v9 word-audio bug).
  /// Falls back to the simple-text split when the ayah has no
  /// morphology entry (the dump covers all 6236 ayahs, so this is
  /// only a safety net).
  static Future<List<String>> wordsForAyah(int surah, int verse) async {
    await ensureLoaded();
    final raw = _morphology![_key(surah, verse)];
    if (raw == null) {
      return quran
          .getVerse(surah, verse)
          .split(' ')
          .where((w) => w.isNotEmpty)
          .toList(growable: false);
    }
    return (raw as List<dynamic>)
        .map((e) => e[0] as String)
        .toList(growable: false);
  }

  /// All (word, meaning) pairs for an ayah, or empty list.
  static Future<List<(String, String)>> meaningsForAyah(
      int surah, int verse) async {
    await ensureLoaded();
    final raw = _meanings![_key(surah, verse)];
    if (raw == null) return <(String, String)>[];
    return (raw as List<dynamic>)
        .map((e) => (e[0] as String, e[1] as String))
        .toList(growable: false);
  }

  static List<(String, String)> _entriesFrom(
      Map<String, dynamic>? data, int surah, int verse) {
    final raw = data?[_key(surah, verse)];
    if (raw == null) return <(String, String)>[];
    return (raw as List<dynamic>)
        .map((e) => (e[0] as String, e[1] as String))
        .toList(growable: false);
  }

  /// Tafsir Center word meanings for an ayah (v13.11), or empty list.
  /// Same format as [meaningsForAyah] («surah:ayah» → [[word, meaning]]).
  static Future<List<(String, String)>> tafsirCenterEntriesForAyah(
      int surah, int verse) async {
    await ensureLoaded();
    return _entriesFrom(_tafsirCenter, surah, verse);
  }

  /// Tafsir Center per-word sarf for an ayah (v13.11), or empty list.
  /// Same format («surah:ayah» → [[word, sarf]]); the sarf text is
  /// the Center's full analysis (avg ~157 chars) — shown in FULL,
  /// never shortened, exactly like the meanings.
  static Future<List<(String, String)>> tafsirCenterSarfEntriesForAyah(
      int surah, int verse) async {
    await ensureLoaded();
    return _entriesFrom(_sarfTC, surah, verse);
  }

  /// Tafsir Center per-word i'rab for an ayah (v13.11), or empty list.
  /// Same format («surah:ayah» → [[word, i'rab]]); the i'rab text is
  /// the Center's full per-word analysis (avg ~138 chars) — shown in
  /// FULL, never shortened. Whole-ayah i'rab is a different table
  /// and is NOT bundled (new feature needing design).
  static Future<List<(String, String)>> tafsirCenterIrabEntriesForAyah(
      int surah, int verse) async {
    await ensureLoaded();
    return _entriesFrom(_irabTC, surah, verse);
  }

  /// Full Tafsir Center sarf of one tapped word, or null when the
  /// Center has no entry for it (it covers 100%, so null should
  /// never happen — the caller falls back to [morphForWord]).
  static Future<String?> sarfForWord(
      int surah, int verse, String word) async {
    final entries = await tafsirCenterSarfEntriesForAyah(surah, verse);
    return _matchWord(entries, word);
  }

  /// Full Tafsir Center per-word i'rab of one tapped word, or null
  /// when the Center has no entry for it (100% coverage — the caller
  /// falls back to the simplified [morphForWord] description).
  static Future<String?> irabForWord(
      int surah, int verse, String word) async {
    final entries = await tafsirCenterIrabEntriesForAyah(surah, verse);
    return _matchWord(entries, word);
  }

  /// Which source the التصريف tab draws on for this word:
  /// 'tafsircenter' (مركز تفسير, v13.11 — the card shows the small
  /// credit line for it), 'morph' (the simplified bundled morphology
  /// description, fallback-only), or 'none'.
  static Future<String> sarfSourceForWord(
      int surah, int verse, String word) async {
    if (await sarfForWord(surah, verse, word) != null) {
      return 'tafsircenter';
    }
    if (await morphForWord(surah, verse, word) != null) return 'morph';
    return 'none';
  }

  /// Which source the الإعراب tab draws on for this word:
  /// 'tafsircenter' (مركز تفسير, v13.11 — the card shows the small
  /// credit line for it), 'morph' (the simplified bundled morphology
  /// description, fallback-only, with the honest disclaimer), or
  /// 'none'.
  static Future<String> irabSourceForWord(
      int surah, int verse, String word) async {
    if (await irabForWord(surah, verse, word) != null) {
      return 'tafsircenter';
    }
    if (await morphForWord(surah, verse, word) != null) return 'morph';
    return 'none';
  }

  /// Coverage of the Tafsir Center sarf + per-word i'rab over the
  /// whole Mushaf, measured with the app's own matching logic (the
  /// same [_matchWord] the card uses, on the card's own lookup
  /// text). The denominator is the TRUE display-word count — the
  /// QCF words (77,433) — NOT the morphology-entry count (77,429):
  /// the morphology file merges 4 phrases into one entry each
  /// (بَعۡدَ مَا in 2:181/8:6/13:37, إِلۡ يَاسِينَ in 37:130), so
  /// its 77,429 entries hide 4 display spellings that never appear
  /// in the card (15:7's duplicated لَّوۡمَا entry and its 2
  /// display words cancel out). (The meanings' 77,429/77,429 used
  /// morphology entries and reached 100% only because the
  /// غريب/lexicon fallbacks caught the merged entries.) Both tables
  /// cover 100% of display words by construction (77,432 dataset
  /// rows = the same word universe, plus the 15:7 لَوْمَا gloss
  /// used twice); this measures it in-app, through the card's
  /// lookup path.
  static Future<({int total, int withSarf, int withIrab})>
      sarfIrabCoverageStats() async {
    await ensureLoaded();
    var total = 0;
    var withSarf = 0;
    var withIrab = 0;
    for (final key in _morphology!.keys) {
      final parts = key.split(':');
      final surah = int.parse(parts[0]);
      final verse = int.parse(parts[1]);
      final sarfEntries = _entriesFrom(_sarfTC, surah, verse);
      final irabEntries = _entriesFrom(_irabTC, surah, verse);
      for (final word in buildQcfWordMap(surah, verse).words) {
        total++;
        if (_matchWord(sarfEntries, word.lookupText) != null) withSarf++;
        if (_matchWord(irabEntries, word.lookupText) != null) withIrab++;
      }
    }
    return (total: total, withSarf: withSarf, withIrab: withIrab);
  }

  /// مخلوف short in-ayah glosses for an ayah (v13.6), or empty list.
  static Future<List<(String, String)>> makhloofEntriesForAyah(
      int surah, int verse) async {
    await ensureLoaded();
    return _entriesFrom(_makhloof, surah, verse);
  }

  /// Additions (short glosses condensed from التفسير الميسر where
  /// مخلوف has none) for an ayah, or empty list.
  static Future<List<(String, String)>> additionEntriesForAyah(
      int surah, int verse) async {
    await ensureLoaded();
    return _entriesFrom(_additions, surah, verse);
  }

  /// Meaning of one tapped word, matched by normalized form.
  /// Priority (v13.11, the user's pick — «ضيف معاني مركز تفسير»):
  /// the Tafsir Center meanings FIRST, shown in FULL — never
  /// [shortenGloss]-shortened (the user approved the small credit
  /// line instead; cutting the text would lose content and would
  /// count as an adaptation under CC BY 4.0). It covers 100% of
  /// words, so the older sources below (additions → مخلوف → غريب
  /// القرآن → root lexicon) are fallback-only. v13.2: the fallback
  /// branches ARE [shortenGloss]-shortened, so the word card AND
  /// the meaning sheet both show the short plain gloss (the user:
  /// "اختصر وهيك بس يكون مفهوم المعنى").
  /// Returns null only when no source has anything.
  static Future<String?> meaningForWord(
      int surah, int verse, String word) async {
    final tafsirCenterEntries =
        await tafsirCenterEntriesForAyah(surah, verse);
    final tafsirCenter = _matchWord(tafsirCenterEntries, word);
    if (tafsirCenter != null) return tafsirCenter;
    final additionEntries = await additionEntriesForAyah(surah, verse);
    final addition = _matchWordStrict(additionEntries, word);
    if (addition != null) return shortenGloss(addition);
    final makhloofEntries = await makhloofEntriesForAyah(surah, verse);
    final makhloof = _matchWordStrict(makhloofEntries, word);
    if (makhloof != null) return shortenGloss(makhloof);
    final entries = await meaningsForAyah(surah, verse);
    final gharib = _matchWord(entries, word);
    if (gharib != null) return shortenGloss(gharib);
    final lex = await lexiconForWord(surah, verse, word);
    if (lex != null) return shortenGloss(lex);
    return null;
  }

  /// Hard cap for any displayed word meaning (v13.2). A gloss is
  /// "short" when it fits in one or two lines of the word card.
  static const int maxGlossLength = 160;

  /// Soft target for a shortened gloss: the first sentence / first
  /// clause of a dictionary entry usually fits in ~120 chars.
  static const int _shortGlossTarget = 120;

  /// A gloss shorter than this is treated as a fragment (bare
  /// headword, "يقال: ..." usage note, ...) that may not explain the
  /// word on its own: the next sentence/clause is kept too, so the
  /// meaning stays UNDERSTOOD (the user's condition), up to the
  /// [maxGlossLength] hard cap.
  static const int _minClearGloss = 25;

  /// A sentence/clause that starts a citation ("قال الشاعر ...",
  /// "قيل ...") adds poetry / a quotation, not meaning: skipped when
  /// appending extra text for clarity, never skipped when it IS the
  /// first sentence (then the entry itself starts with a quote).
  static bool _isCitation(String text) =>
      text.startsWith('قال') || text.startsWith('قيل');

  /// Split [text] into sentences at Arabic/English sentence
  /// terminators (؛ . 。), keeping each terminator, trimming parts.
  static List<String> _sentences(String text) {
    final out = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      buf.write(ch);
      if (ch == '。' || ch == '؛' || ch == '.') {
        final s = buf.toString().trim();
        if (s.isNotEmpty) out.add(s);
        buf.clear();
      }
    }
    final rest = buf.toString().trim();
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  /// Cut [text] at the last word boundary at or before [cap] chars
  /// and mark the cut with "…". Only used when no sentence/clause
  /// boundary can bring the text under the cap.
  static String _truncateAtWord(String text, int cap) {
    if (text.length <= cap) return text;
    final cut = text.substring(0, cap);
    final sp = cut.lastIndexOf(' ');
    return '${sp > 0 ? cut.substring(0, sp) : cut}…';
  }

  /// Shorten a bundled meaning to a short plain gloss (≤
  /// [maxGlossLength] chars, usually ≤ ~120). TRUNCATION ONLY: it
  /// never rewrites or invents — it keeps the entry's own words.
  ///
  /// 1. Already short (≤ ~120 chars)? Return as-is.
  /// 2. Else the FIRST sentence only (cut at the first 。/؛/.).
  /// 3. Clarity guard: if that first sentence is a fragment
  ///    (< 25 chars — bare headword, "يقال: ..." note), keep the
  ///    next sentence too (skipping citation sentences), up to the
  ///    160-char cap, so the meaning stays understood.
  /// 4. If the result is still > ~120 chars, keep its first clause
  ///    (up to the first ،), plus following clauses only while the
  ///    text is still a fragment (< 25 chars) — never a citation
  ///    clause.
  /// 5. Hard cap 160 chars at a word boundary ("…").
  static String shortenGloss(String text) {
    final s = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length <= _shortGlossTarget) return s;
    final sentences = _sentences(s);
    if (sentences.isEmpty) return _truncateAtWord(s, _shortGlossTarget);
    var result = sentences[0];
    var i = 1;
    while (result.length < _minClearGloss && i < sentences.length) {
      final next = sentences[i];
      i++;
      if (_isCitation(next)) continue;
      if (result.length + 1 + next.length <= maxGlossLength) {
        result = '$result $next';
      } else {
        for (final part in next.split('،')) {
          final p = part.trim();
          if (p.isEmpty || _isCitation(p)) continue;
          final joiner = result.endsWith('.') ||
                  result.endsWith('。') ||
                  result.endsWith('؛')
              ? ' '
              : '، ';
          if (result.length + joiner.length + p.length <= maxGlossLength) {
            result = result + joiner + p;
          } else {
            break;
          }
        }
        break;
      }
    }
    if (result.length > _shortGlossTarget) {
      final parts =
          result.split('،').map((e) => e.trim()).toList(growable: false);
      var acc = parts[0];
      for (var j = 1; j < parts.length; j++) {
        if (acc.length >= _minClearGloss) break;
        final p = parts[j];
        if (_isCitation(p)) continue;
        if (acc.length + 2 + p.length <= _shortGlossTarget) {
          acc = '$acc، $p';
        } else {
          break;
        }
      }
      result = acc;
    }
    if (result.length > maxGlossLength) {
      result = _truncateAtWord(result, maxGlossLength - 3);
    }
    return result.trim();
  }

  /// Length distribution of the gloss [wordGloss] actually displays
  /// for every word of the Mushaf (same matching as [coverageStats],
  /// with [shortenGloss] applied to the FALLBACK meaning branches):
  /// total words, words with a (shortened) meaning, median and max
  /// displayed-gloss length, and how many glosses exceed 160 / 120
  /// chars. v13.11: the Tafsir Center meanings are shown in FULL
  /// (never shortened), so over160 is no longer 0 — it counts the
  /// long Tafsir Center entries (11% > 120 chars, max 720). That is
  /// the user's approved behaviour, not a regression.
  static Future<
      ({
        int total,
        int withShortMeaning,
        int medianLength,
        int maxLength,
        int over160,
        int over120
      })> glossLengthStats() async {
    await ensureLoaded();
    final lengths = <int>[];
    var withShortMeaning = 0;
    for (final ayah in _morphology!.entries) {
      final key = ayah.key;
      final parts = key.split(':');
      final surah = int.parse(parts[0]);
      final verse = int.parse(parts[1]);
      final rawMeanings = _meanings![key];
      final meaningEntries = rawMeanings == null
          ? <(String, String)>[]
          : (rawMeanings as List<dynamic>)
              .map((e) => (e[0] as String, e[1] as String))
              .toList(growable: false);
      final tafsirCenterEntries = _entriesFrom(_tafsirCenter, surah, verse);
      final additionEntries = _entriesFrom(_additions, surah, verse);
      final makhloofEntries = _entriesFrom(_makhloof, surah, verse);
      for (final w in ayah.value as List<dynamic>) {
        final word = w[0] as String;
        final desc = w.length >= 2 ? w[1] as String : '';
        String gloss;
        // v13.11 priority: Tafsir Center (full text) → additions →
        // مخلوف → غريب → Raghib.
        final tafsirCenter = _matchWord(tafsirCenterEntries, word);
        final addition = tafsirCenter == null
            ? _matchWordStrict(additionEntries, word)
            : null;
        final makhloof =
            addition == null && tafsirCenter == null
                ? _matchWordStrict(makhloofEntries, word)
                : null;
        final gharib =
            makhloof == null && addition == null && tafsirCenter == null
                ? _matchWord(meaningEntries, word)
                : null;
        if (tafsirCenter != null) {
          gloss = tafsirCenter;
          withShortMeaning++;
        } else if (addition != null) {
          gloss = shortenGloss(addition);
          withShortMeaning++;
        } else if (makhloof != null) {
          gloss = shortenGloss(makhloof);
          withShortMeaning++;
        } else if (gharib != null) {
          gloss = shortenGloss(gharib);
          withShortMeaning++;
        } else {
          final lex = _lexiconLookup(desc);
          if (lex != null) {
            gloss = shortenGloss(lex);
            withShortMeaning++;
          } else if (desc.isNotEmpty) {
            gloss = desc;
          } else {
            gloss = 'كلمة من كلمات القرآن الكريم';
          }
        }
        lengths.add(gloss.length);
      }
    }
    lengths.sort();
    var over160 = 0;
    var over120 = 0;
    for (final l in lengths) {
      if (l > 160) over160++;
      if (l > 120) over120++;
    }
    return (
      total: lengths.length,
      withShortMeaning: withShortMeaning,
      medianLength: lengths.isEmpty ? 0 : lengths[lengths.length ~/ 2],
      maxLength: lengths.isEmpty ? 0 : lengths.last,
      over160: over160,
      over120: over120,
    );
  }

  /// Root (e.g. "نزل") from a morphology description such as
  /// "فعل ماضٍ، للغائب، الجذر (نزل)، الوزن (أَفْعَلَ)".
  /// Returns null for words with no root (particles, pronouns, ...).
  static final _rootRe = RegExp(r'الجذر \(([^)]+)\)');

  static String? _rootOfMorph(String morphDesc) =>
      _rootRe.firstMatch(morphDesc)?.group(1);

  /// Candidate lexicon keys for a root. The first is the exact
  /// normalized root; the rest vary a final weak letter (و/ي/ا),
  /// because the lexicon's headword may spell a weak-final root with
  /// ا (e.g. root سمو → headword سما), undouble a geminate root
  /// (أسس → أس، أبب → أبّ), or drop a final weak letter (أخو → أخ).
  /// Exact matches always win; the order below is the lookup order.
  static List<String> _rootKeyCandidates(String root) {
    final base = normalizeArabic(root);
    final candidates = <String>[base];
    if (base.isEmpty) return candidates;
    final last = base[base.length - 1];
    if (last == 'و' || last == 'ي' || last == 'ا') {
      for (final rep in ['ا', 'و', 'ي']) {
        if (rep != last) {
          candidates.add(base.substring(0, base.length - 1) + rep);
        }
      }
    }
    if (base.length >= 2 && base[base.length - 1] == base[base.length - 2]) {
      candidates.add(base.substring(0, base.length - 1));
    }
    if (last == 'و' || last == 'ي') {
      candidates.add(base.substring(0, base.length - 1));
    }
    if (base.length == 3 &&
        (base[1] == 'و' || base[1] == 'ي')) {
      // Hollow root: medial weak letter spelled ا (كان، مال، دار)،
      // and with a final hamza spelled ء (شاء، جاء).
      candidates.add('${base[0]}ا${base[2]}');
      if (base[2] == 'ا') {
        candidates.add('${base[0]}اء');
      }
    }
    return candidates.toSet().toList(growable: false);
  }

  /// Lexicon definition for a word's root, or null when the word has
  /// no root or its root has no entry in مفردات الراغب.
  static String? _lexiconLookup(String morphDesc) {
    final root = _rootOfMorph(morphDesc);
    if (root == null) return null;
    for (final candidate in _rootKeyCandidates(root)) {
      final value = _lexicon![candidate];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Lexicon (مفردات الراغب) definition for one tapped word, via its
  /// morphology root. Returns null when no entry exists.
  static Future<String?> lexiconForWord(
      int surah, int verse, String word) async {
    final morph = await morphForWord(surah, verse, word);
    if (morph == null) return null;
    await ensureLoaded();
    return _lexiconLookup(morph);
  }

  /// A gloss for a tapped word that NEVER returns blank for a real word:
  /// the Tafsir Center meaning when present (v13.11 — shown in FULL,
  /// never shortened), else the غريب القرآن meaning, else the
  /// root-lexicon definition, else the (real, bundled) morphology
  /// description (type/root/pattern — e.g. "حرف جر" for عَلَيْكَ), else
  /// a plain statement that it is a Quranic word. Nothing here is
  /// invented: every branch comes from a bundled source. v13.2:
  /// the fallback meaning branches are [shortenGloss]-shortened
  /// (≤ 160 chars); the morphology fallback is already short
  /// (measured max 145 chars).
  static Future<String> wordGloss(
      int surah, int verse, String word) async {
    final meaning = await meaningForWord(surah, verse, word);
    if (meaning != null && meaning.trim().isNotEmpty) return meaning;
    final morph = await morphForWord(surah, verse, word);
    if (morph != null && morph.trim().isNotEmpty) return morph;
    return 'كلمة من كلمات القرآن الكريم';
  }

  /// Which source [wordGloss] draws on for this word, so the UI can
  /// label it honestly: 'tafsircenter' (مركز تفسير للدراسات القرآنية,
  /// v13.11 — the card shows the small credit line for it),
  /// 'addition' (short gloss condensed from التفسير الميسر),
  /// 'makhloof' (مخلوف «كلمات القرآن»), 'gharib' (غريب القرآن),
  /// 'lexicon' (مفردات الراغب، مادة الجذر), 'morph' (الوصف الصرفي
  /// فقط), or 'none' (word not found in any bundled source).
  static Future<String> glossSourceForWord(
      int surah, int verse, String word) async {
    final tafsirCenterEntries =
        await tafsirCenterEntriesForAyah(surah, verse);
    if (_matchWord(tafsirCenterEntries, word) != null) {
      return 'tafsircenter';
    }
    final additionEntries = await additionEntriesForAyah(surah, verse);
    if (_matchWordStrict(additionEntries, word) != null) return 'addition';
    final makhloofEntries = await makhloofEntriesForAyah(surah, verse);
    if (_matchWordStrict(makhloofEntries, word) != null) return 'makhloof';
    final entries = await meaningsForAyah(surah, verse);
    if (_matchWord(entries, word) != null) return 'gharib';
    if (await lexiconForWord(surah, verse, word) != null) return 'lexicon';
    if (await morphForWord(surah, verse, word) != null) return 'morph';
    return 'none';
  }

  /// Coverage of the bundled word data over the whole Mushaf, measured
  /// with the app's own matching logic (strict for مخلوف / additions,
  /// [_matchWord] + root lookup for the rest): total words, words with
  /// a مخلوف gloss, words with an additions gloss, words with a غريب
  /// القرآن meaning, words with a root-lexicon definition, words with
  /// either meaning, and words with any non-blank gloss (meaning or
  /// morphology description). The per-source counts are independent
  /// (a word can match several sources); [withMeaning] is the union
  /// in priority order (v13.11: Tafsir Center → additions → مخلوف →
  /// غريب → lexicon).
  static Future<
      ({
        int total,
        int withMakhloof,
        int withAddition,
        int withGharib,
        int withLexicon,
        int withMeaning,
        int withGloss
      })> coverageStats() async {
    await ensureLoaded();
    var total = 0;
    var withMakhloof = 0;
    var withAddition = 0;
    var withGharib = 0;
    var withLexicon = 0;
    var withMeaning = 0;
    var withGloss = 0;
    for (final ayah in _morphology!.entries) {
      final key = ayah.key;
      final parts = key.split(':');
      final surah = int.parse(parts[0]);
      final verse = int.parse(parts[1]);
      final rawMeanings = _meanings![key];
      final meaningEntries = rawMeanings == null
          ? <(String, String)>[]
          : (rawMeanings as List<dynamic>)
              .map((e) => (e[0] as String, e[1] as String))
              .toList(growable: false);
      final additionEntries = _entriesFrom(_additions, surah, verse);
      final makhloofEntries = _entriesFrom(_makhloof, surah, verse);
      final tafsirCenterEntries = _entriesFrom(_tafsirCenter, surah, verse);
      for (final w in ayah.value as List<dynamic>) {
        final word = w[0] as String;
        final desc = w.length >= 2 ? w[1] as String : '';
        total++;
        final hasTafsirCenter =
            _matchWord(tafsirCenterEntries, word) != null;
        final hasAddition =
            _matchWordStrict(additionEntries, word) != null;
        final hasMakhloof =
            _matchWordStrict(makhloofEntries, word) != null;
        final hasGharib = _matchWord(meaningEntries, word) != null;
        final hasLexicon = _lexiconLookup(desc) != null;
        if (hasAddition) withAddition++;
        if (hasMakhloof) withMakhloof++;
        if (hasGharib) withGharib++;
        if (hasLexicon) withLexicon++;
        if (hasTafsirCenter ||
            hasAddition ||
            hasMakhloof ||
            hasGharib ||
            hasLexicon) {
          withMeaning++;
        }
        if (hasTafsirCenter ||
            hasAddition ||
            hasMakhloof ||
            hasGharib ||
            hasLexicon ||
            desc.isNotEmpty) {
          withGloss++;
        }
      }
    }
    return (
      total: total,
      withMakhloof: withMakhloof,
      withAddition: withAddition,
      withGharib: withGharib,
      withLexicon: withLexicon,
      withMeaning: withMeaning,
      withGloss: withGloss,
    );
  }

  /// Simplified i'rab / morphology description of one tapped word.
  /// Returns null when no entry exists for the word.
  static Future<String?> morphForWord(
      int surah, int verse, String word) async {
    await ensureLoaded();
    final raw = _morphology![_key(surah, verse)];
    if (raw == null) return null;
    final entries = (raw as List<dynamic>)
        .map((e) => (e[0] as String, e[1] as String))
        .toList(growable: false);
    return _matchWord(entries, word);
  }

  /// Strict word match for the مخلوف / additions sources: exact
  /// normalized match, then token-in-phrase. The third step of
  /// [_matchWord] (containment) is NOT used here: a short particle
  /// (على، إلا، لكم، إلى) is a substring of many unrelated phrases, so
  /// containment returns the phrase's gloss for a word it does not
  /// explain (verified: 157 containment-only مخلوف matches, ~8/10
  /// wrong — e.g. 4:141 عَلَى getting the gloss of «أَلَمْ
  /// نَسْتَحْوِذْ عَلَيْكُمْ»). Those words fall through to غريب /
  /// Raghib / the morphology description instead. The غريب and
  /// morphology lookups keep [_matchWord] (containment included) —
  /// their behaviour is unchanged.
  /// Last vowel/diacritic of a word (U+064B–U+0652: tanwin, fatha,
  /// damma, kasra, sukun, shadda), scanning from the end and skipping
  /// trailing pause marks (ۚ etc.). Used to tell apart repeated
  /// words that differ only in case — the same bare word often recurs
  /// in one ayah in different cases (ٱللَّهُ / ٱللَّهَ / ٱللَّهِ;
  /// 847 such groups in the sarf asset alone), and picking the first
  /// normalized match would show the wrong i'rab for the later
  /// occurrences (e.g. 35:43 word 9 ٱلسَّيِّئُ nominative getting
  /// word 5's genitive i'rab). Open tanwin (U+08F0–U+08F2) is not in
  /// this range, so a word ending in it simply gets no vowel
  /// preference (first match stands, as before).
  static String _finalVowel(String s) {
    for (var i = s.length - 1; i >= 0; i--) {
      final c = s.codeUnitAt(i);
      if (c >= 0x064B && c <= 0x0652) {
        return String.fromCharCode(c);
      }
    }
    return '';
  }

  /// Among normalized-equal candidates, prefer the one whose final
  /// vowel matches the lookup word's (see [_finalVowel]); falls back
  /// to the first candidate when none matches.
  static String _preferVowel(
      List<(String, String)> candidates, String word) {
    final want = _finalVowel(word);
    if (want.isNotEmpty) {
      for (final (text, value) in candidates) {
        if (_finalVowel(text) == want) return value;
      }
    }
    return candidates.first.$2;
  }

  static String? _matchWordStrict(
      List<(String, String)> entries, String word) {
    final wordNorm = normalizeArabic(word);
    if (wordNorm.isEmpty) return null;
    final exact = <(String, String)>[];
    for (final (text, value) in entries) {
      if (normalizeArabic(text) == wordNorm) exact.add((text, value));
    }
    if (exact.isNotEmpty) return _preferVowel(exact, word);
    final tokenMatches = <(String, String)>[];
    for (final (text, value) in entries) {
      for (final token in text.split(RegExp(r'\s+'))) {
        if (normalizeArabic(token) == wordNorm) {
          tokenMatches.add((token, value));
        }
      }
    }
    if (tokenMatches.isNotEmpty) return _preferVowel(tokenMatches, word);
    return null;
  }

  static String? _matchWord(List<(String, String)> entries, String word) {
    final wordNorm = normalizeArabic(word);
    if (wordNorm.isEmpty) return null;
    // 1) exact normalized match (handles multi-word phrases too)
    final exact = <(String, String)>[];
    for (final (text, value) in entries) {
      if (normalizeArabic(text) == wordNorm) exact.add((text, value));
    }
    if (exact.isNotEmpty) return _preferVowel(exact, word);
    // 2) token match inside a multi-word phrase (e.g. بِسْمِ in بِسْمِ اللهِ)
    final tokenMatches = <(String, String)>[];
    for (final (text, value) in entries) {
      for (final token in text.split(RegExp(r'\s+'))) {
        if (normalizeArabic(token) == wordNorm) {
          tokenMatches.add((token, value));
        }
      }
    }
    if (tokenMatches.isNotEmpty) return _preferVowel(tokenMatches, word);
    // 3) containment for longer words (phrase contains the word)
    if (wordNorm.length >= 3) {
      for (final (text, value) in entries) {
        if (normalizeArabic(text).contains(wordNorm)) return value;
      }
    }
    return null;
  }

  /// التفسير الميسر text for an ayah, or null if missing.
  static Future<String?> tafsirForAyah(int surah, int verse) async {
    await ensureLoaded();
    return _tafsir![_key(surah, verse)] as String?;
  }

  /// Label like «الربع الثاني من الحزب 7» for the quarter containing
  /// this ayah, derived from the 240 quarter-start boundaries.
  static Future<String> hizbQuarterLabel(int surah, int verse) async {
    await ensureLoaded();
    final order = surah * 1000 + verse;
    var q = 0;
    for (var i = 0; i < _quarters!.length; i++) {
      final b = _quarters![i];
      if (b[0] * 1000 + b[1] <= order) {
        q = i;
      } else {
        break;
      }
    }
    const quarterNames = ['الأول', 'الثاني', 'الثالث', 'الرابع'];
    final hizb = q ~/ 4 + 1;
    final quarterInHizb = q % 4;
    return 'الربع ${quarterNames[quarterInHizb]} من الحزب $hizb';
  }
}
