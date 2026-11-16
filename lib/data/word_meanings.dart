import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quran/quran.dart' as quran;

/// Offline Quran word data (Quranpedia dumps, bundled under assets/quran_data):
/// - word meanings (غريب القرآن — السراج في بيان غريب القرآن، مع التبيان كبديل)
/// - التفسير الميسر (كاملاً، آية بآية)
/// - simplified morphology / i'rab (Quranic Arabic Corpus via Quranpedia)
/// - hizb-quarter boundaries (240 quarter starts, from alquran.cloud metadata)
///
/// All files are loaded lazily on first use and cached in memory.
class QuranWordData {
  static Map<String, dynamic>? _meanings;
  static Map<String, dynamic>? _tafsir;
  static Map<String, dynamic>? _morphology;
  static List<List<int>>? _quarters;
  static bool _loading = false;
  static Future<void>? _loadFuture;

  static Future<void> ensureLoaded() {
    _loadFuture ??= _loadAll();
    return _loadFuture!;
  }

  static Future<void> _loadAll() async {
    if (_loading) return;
    _loading = true;
    final meaningsRaw =
        await rootBundle.loadString('assets/quran_data/word_meanings.json');
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
    s = s.replaceAll(RegExp(r'[\u064B-\u0655\u0670\u0640\u06D6-\u06ED]'), '');
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
  /// Returns null when the word has no special meaning in غريب القرآن.
  static Future<String?> meaningForWord(
      int surah, int verse, String word) async {
    final entries = await meaningsForAyah(surah, verse);
    return _matchWord(entries, word);
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
