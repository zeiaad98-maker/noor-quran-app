import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quran/quran.dart' as quran;

/// Offline Quran word data (Quranpedia dumps, bundled under assets/quran_data):
/// - word meanings (غريب القرآن — السراج في بيان غريب القرآن، مع التبيان كبديل)
/// - word lexicon (مفردات ألفاظ القرآن للراغب الأصفهاني، ت ٥٠٢هـ،
///   keyed by normalized root; consulted after غريب القرآن)
/// - التفسير الميسر (كاملاً، آية بآية)
/// - simplified morphology / i'rab (Quranic Arabic Corpus via Quranpedia)
/// - hizb-quarter boundaries (240 quarter starts, from alquran.cloud metadata)
///
/// All files are loaded lazily on first use and cached in memory.
class QuranWordData {
  static Map<String, dynamic>? _meanings;
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
    s = s.replaceAll(RegExp(r'[\u064B-\u0655\u0640\u06D6-\u06ED]'), '');
    s = s.replaceAll('\u0622', '\u0627'); // آ -> ا
    s = s.replaceAll('\u0623', '\u0627'); // أ -> ا
    s = s.replaceAll('\u0625', '\u0627'); // إ -> ا
    s = s.replaceAll('\u0671', '\u0627'); // ٱ -> ا
    s = s.replaceAll('\u0649', '\u064A'); // ى -> ي
    s = s.replaceAll('\u0629', '\u0647'); // ة -> ه
    s = s.replaceAll(RegExp(r'\s+'), '');
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

  /// Meaning of one tapped word, matched by normalized form.
  /// غريب القرآن entries come first (ayah-specific); when the word has
  /// no special meaning there, the root lexicon (مفردات الراغب) is
  /// consulted. Returns null only when neither source has anything.
  static Future<String?> meaningForWord(
      int surah, int verse, String word) async {
    final entries = await meaningsForAyah(surah, verse);
    final gharib = _matchWord(entries, word);
    if (gharib != null) return gharib;
    return lexiconForWord(surah, verse, word);
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
  /// the غريب القرآن meaning when present, else the root-lexicon
  /// definition, else the (real, bundled) morphology description
  /// (type/root/pattern — e.g. "حرف جر" for عَلَيْكَ), else a plain
  /// statement that it is a Quranic word. Nothing here is invented:
  /// every branch comes from a bundled source.
  static Future<String> wordGloss(
      int surah, int verse, String word) async {
    final meaning = await meaningForWord(surah, verse, word);
    if (meaning != null && meaning.trim().isNotEmpty) return meaning;
    final morph = await morphForWord(surah, verse, word);
    if (morph != null && morph.trim().isNotEmpty) return morph;
    return 'كلمة من كلمات القرآن الكريم';
  }

  /// Which source [wordGloss] draws on for this word, so the UI can
  /// label it honestly: 'gharib' (غريب القرآن), 'lexicon'
  /// (مفردات الراغب، مادة الجذر), 'morph' (الوصف الصرفي فقط),
  /// or 'none' (word not found in any bundled source).
  static Future<String> glossSourceForWord(
      int surah, int verse, String word) async {
    final entries = await meaningsForAyah(surah, verse);
    if (_matchWord(entries, word) != null) return 'gharib';
    if (await lexiconForWord(surah, verse, word) != null) return 'lexicon';
    if (await morphForWord(surah, verse, word) != null) return 'morph';
    return 'none';
  }

  /// Coverage of the bundled word data over the whole Mushaf, measured
  /// with the app's own matching logic ([_matchWord] + root lookup):
  /// total words, words with a غريب القرآن meaning, words with a
  /// root-lexicon definition, words with either meaning, and words
  /// with any non-blank gloss (meaning or morphology description).
  static Future<
      ({
        int total,
        int withGharib,
        int withLexicon,
        int withMeaning,
        int withGloss
      })> coverageStats() async {
    await ensureLoaded();
    var total = 0;
    var withGharib = 0;
    var withLexicon = 0;
    var withMeaning = 0;
    var withGloss = 0;
    for (final ayah in _morphology!.entries) {
      final key = ayah.key;
      final rawMeanings = _meanings![key];
      final meaningEntries = rawMeanings == null
          ? <(String, String)>[]
          : (rawMeanings as List<dynamic>)
              .map((e) => (e[0] as String, e[1] as String))
              .toList(growable: false);
      for (final w in ayah.value as List<dynamic>) {
        final word = w[0] as String;
        final desc = w.length >= 2 ? w[1] as String : '';
        total++;
        final hasGharib = _matchWord(meaningEntries, word) != null;
        final hasLexicon = _lexiconLookup(desc) != null;
        if (hasGharib) withGharib++;
        if (hasLexicon) withLexicon++;
        if (hasGharib || hasLexicon) withMeaning++;
        if (hasGharib || hasLexicon || desc.isNotEmpty) withGloss++;
      }
    }
    return (
      total: total,
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

  static String? _matchWord(List<(String, String)> entries, String word) {
    final wordNorm = normalizeArabic(word);
    if (wordNorm.isEmpty) return null;
    // 1) exact normalized match (handles multi-word phrases too)
    for (final (text, value) in entries) {
      if (normalizeArabic(text) == wordNorm) return value;
    }
    // 2) token match inside a multi-word phrase (e.g. بِسْمِ in بِسْمِ اللهِ)
    for (final (text, value) in entries) {
      for (final token in text.split(RegExp(r'\s+'))) {
        if (normalizeArabic(token) == wordNorm) return value;
      }
    }
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
