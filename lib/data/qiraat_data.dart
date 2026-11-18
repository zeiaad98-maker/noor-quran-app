import 'dart:convert';

import 'package:flutter/services.dart';

import 'word_meanings.dart';

/// One reading of a word in another qira'ah.
///
/// [text] is the word as read in that reading, [readers] the Arabic
/// names of who reads it that way (imams, or riwayahs like
/// «شعبة عن عاصم» when two transmitters of one imam differ),
/// [hafs] marks the reading of our Mushaf (حفص عن عاصم).
class QiraatReading {
  final String text;
  final List<String> readers;
  final bool hafs;

  const QiraatReading({
    required this.text,
    required this.readers,
    required this.hafs,
  });
}

/// One variant juncture in an ayah: the Hafs [word] and the 0-based
/// [span] of the word(s) it covers, with every [readings] of it.
///
/// Source: TheAbubakrAbu/Quran-Tajweed-Engine data/qiraat-variants.json
/// (MIT), trimmed to the fields the card shows — see
/// ~/workspace/noor-quran-v1/qiraat-work/trim_qiraat.py. 1,560
/// entries over 1,354 ayahs; 74 entries whose source span was null
/// (unmappable to a word) were dropped, not guessed.
class QiraatVariant {
  final String word;
  final int spanStart;
  final int spanEnd;
  final List<QiraatReading> readings;

  const QiraatVariant({
    required this.word,
    required this.spanStart,
    required this.spanEnd,
    required this.readings,
  });

  /// The reading of our Mushaf (حفص عن عاصم), if the source marks one.
  QiraatReading? get hafsReading {
    for (final r in readings) {
      if (r.hafs) return r;
    }
    return null;
  }

  /// Readings other than ours.
  List<QiraatReading> get otherReadings =>
      readings.where((r) => !r.hafs).toList(growable: false);
}

/// Qira'at variants for a tapped word (v13.6, the القراءات tab).
///
/// The file is optional like the lexicon: a missing/corrupt asset
/// must not break the rest of the word data — it only empties this tab.
class QiraatData {
  static Map<String, dynamic>? _ayahs;
  static Future<void>? _loadFuture;

  static Future<void> ensureLoaded() async {
    if (_ayahs != null) return;
    _loadFuture ??= _load();
    await _loadFuture;
  }

  static Future<void> _load() async {
    try {
      final raw = await rootBundle
          .loadString('assets/quran_data/qiraat_variants.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _ayahs = decoded['ayahs'] as Map<String, dynamic>;
    } catch (_) {
      _ayahs = <String, dynamic>{};
    }
  }

  static QiraatVariant _parse(Map<String, dynamic> e) {
    final span = e['span'] as List<dynamic>;
    final readings = (e['readings'] as List<dynamic>)
        .map((r) => QiraatReading(
              text: r['text'] as String,
              readers: (r['readers'] as List<dynamic>)
                  .map((n) => n as String)
                  .toList(growable: false),
              hafs: r['hafs'] as bool? ?? false,
            ))
        .toList(growable: false);
    return QiraatVariant(
      word: e['word'] as String,
      spanStart: span[0] as int,
      spanEnd: span[1] as int,
      readings: readings,
    );
  }

  /// All variants of an ayah, in source order (empty when the ayah
  /// has no recorded variant — most ayahs don't).
  static Future<List<QiraatVariant>> variantsForAyah(
      int surah, int verse) async {
    await ensureLoaded();
    final raw = _ayahs!['$surah:$verse'] as List<dynamic>?;
    if (raw == null) return const [];
    return raw
        .map((e) => _parse(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Variants covering the TAPPED word ([wordIndex] is the 0-based
  /// QCF position, [wordText] the word as shown on the page).
  ///
  /// Two guards, both required: the word index must lie inside the
  /// entry's span AND the entry's word text must match the tapped
  /// word (normalized — the source's word numbering can drift from
  /// the QCF map in merged-word ayahs, and a span alone would then
  /// attribute a variant to the wrong word). A phrase entry
  /// (multi-word span) matches when its text contains the tapped
  /// word; a single-word entry only on exact normalized equality.
  /// Entries failing either guard are skipped, never shown.
  static Future<List<QiraatVariant>> variantsForWord(
      int surah, int verse, int wordIndex, String wordText) async {
    final all = await variantsForAyah(surah, verse);
    final normWord = QuranWordData.normalizeArabic(wordText);
    if (normWord.isEmpty) return const [];
    return all.where((v) {
      if (wordIndex < v.spanStart || wordIndex > v.spanEnd) return false;
      final normEntry = QuranWordData.normalizeArabic(v.word);
      if (normEntry == normWord) return true;
      // Phrase entry: the tapped word is one word of the phrase.
      if (v.spanEnd > v.spanStart && normEntry.contains(normWord)) {
        return true;
      }
      return false;
    }).toList(growable: false);
  }
}
