import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;

import 'qcf_word_map.dart';

/// Verified surah-science data for the word popup (علوم السورة) and the
/// page tab (الصفحة).
///
/// Sources (all verbatim from the Dalail research in
/// ~/workspace/noor-quran-v1/dalail-research/ — nothing re-typed):
/// * نزول السورة (Makki/Madani + revelation order, 114/114): Dalail
///   `get_surah_info` cross-checked against quran.com API v4 —
///   0 mismatches. `assets/quran_data/surah_info.json`.
/// * أسماء السورة + مقاصد السورة: مصاعد النظر للبقاعي (Dalail 1404),
///   ALL 114 surahs. Names found for 41 surahs; the other 73 carry an
///   honest note (البقاعي lists no other names for them). The
///   توقيفية/اجتهادية labels were NOT verified, so names ship
///   WITHOUT labels. `assets/quran_data/surah_sciences.json`.
/// * فضائل السورة: موسوعة فضائل سور وآيات القرآن — القسم الصحيح
///   (Dalail 144114), ALL 114 surahs. 66 surahs have a باب (62 with a
///   hadith, 4 whose باب states only "لم يصح ... سوى أنها من المفصل");
///   the other 48 have no باب and carry an honest note. Same file
///   as above.
/// * أسباب النزول (per ayah): صحيح أسباب النزول — إبراهيم العلي
///   (MIT dataset, 200 entries / 277 ayah refs / 50 surahs).
///   `assets/quran_data/asbab_nuzul.json`.
/// * الفوائد: OMITTED — no verified source was found (the book in the
///   user's screenshot, هدايات القرآن الكريم / المختصر, is not in
///   Dalail and no free structured text exists). Never fabricated.
/// * الترجمات: REMOVED in v11 (Bug I — user order "الترجمات احذفها"):
///   no translation tab in the popup and no alquran.cloud fetch.
///   Nothing replaced it.
///
/// Stats (word/letter counts) are computed in-app from the bundled
/// Quran text, not copied from anywhere: word count = the QCF word
/// map's true words (77,433 for the whole Quran), letter count =
/// bare Arabic letters of the Uthmani text.
class SurahInfo {
  final int surah;
  final String nameAr;
  final String revelationPlaceAr; // مكية / مدنية
  final int revelationOrder;
  final int ayahCount;
  final int pageStart;
  final int pageEnd;

  const SurahInfo({
    required this.surah,
    required this.nameAr,
    required this.revelationPlaceAr,
    required this.revelationOrder,
    required this.ayahCount,
    required this.pageStart,
    required this.pageEnd,
  });
}

class SurahScience {
  final int surah;
  final String nameAr;
  final List<String>? names;
  final String? namesVerbatim;
  final String? namesEtymology;
  final String? maqsadShort;
  final String? maqsadVerbatim;
  final String? nuzulVerbatim;
  final String? fadailHeadline;
  final String? fadailHadith;
  final String? fadailSource;

  const SurahScience({
    required this.surah,
    required this.nameAr,
    this.names,
    this.namesVerbatim,
    this.namesEtymology,
    this.maqsadShort,
    this.maqsadVerbatim,
    this.nuzulVerbatim,
    this.fadailHeadline,
    this.fadailHadith,
    this.fadailSource,
  });
}

class SurahStats {
  final int ayahCount;
  final int wordCount;
  final int letterCount;

  const SurahStats({
    required this.ayahCount,
    required this.wordCount,
    required this.letterCount,
  });
}

class SurahSciences {
  static Map<int, SurahInfo>? _info;
  static Map<int, SurahScience>? _sciences;
  static Map<String, List<String>>? _asbab;
  static final Map<int, SurahStats> _statsCache = {};
  static Future<void>? _loadFuture;

  /// NOTE (v11, widget tests): same cross-zone point as
  /// [QuranWordData.ensureLoaded] — the old form returned the shared
  /// [_loadFuture] directly, and a future completed in another zone
  /// never fires its callbacks inside a test's pump loop. The async
  /// fast path returns a fresh caller-zone future once loaded.
  /// [_asbab] is set last in [_loadAll], so it is the loaded signal.
  static Future<void> ensureLoaded() async {
    if (_asbab != null) return;
    _loadFuture ??= _loadAll();
    await _loadFuture!;
  }

  static Future<void> _loadAll() async {
    final infoRaw =
        await rootBundle.loadString('assets/quran_data/surah_info.json');
    final infoJson = jsonDecode(infoRaw) as Map<String, dynamic>;
    _info = {
      for (final e in (infoJson['surahs'] as List<dynamic>))
        (e['surah'] as int): SurahInfo(
          surah: e['surah'] as int,
          nameAr: e['name_ar'] as String,
          revelationPlaceAr: e['revelation_place_ar'] as String,
          revelationOrder: e['revelation_order'] as int,
          ayahCount: e['ayah_count'] as int,
          pageStart: e['page_start'] as int,
          pageEnd: e['page_end'] as int,
        ),
    };
    final sciRaw = await rootBundle
        .loadString('assets/quran_data/surah_sciences.json');
    final sciJson = jsonDecode(sciRaw) as Map<String, dynamic>;
    _sciences = {
      for (final e in (sciJson['surahs'] as List<dynamic>))
        (e['surah'] as int): SurahScience(
          surah: e['surah'] as int,
          nameAr: e['name_ar'] as String,
          names: (e['names_list'] as List<dynamic>?)
              ?.map((n) => n as String)
              .toList(),
          namesVerbatim: e['names_verbatim'] as String?,
          namesEtymology: e['names_etymology_verbatim'] as String?,
          maqsadShort: e['maqsad_short'] as String?,
          maqsadVerbatim: e['maqsad_verbatim'] as String?,
          nuzulVerbatim: e['nuzul_verbatim'] as String?,
          fadailHeadline: e['fadail_headline'] as String?,
          fadailHadith: e['fadail_hadith'] as String?,
          fadailSource: e['fadail_source'] as String?,
        ),
    };
    final asbabRaw =
        await rootBundle.loadString('assets/quran_data/asbab_nuzul.json');
    final asbabJson = jsonDecode(asbabRaw) as List<dynamic>;
    _asbab = {};
    for (final e in asbabJson) {
      final surah = e['surah'] as int;
      final occasions = (e['occasions'] as List<dynamic>)
          .map((o) => o as String)
          .toList();
      for (final ayah in (e['ayahs'] as List<dynamic>)) {
        final key = '$surah:$ayah';
        _asbab!.putIfAbsent(key, () => []).addAll(occasions);
      }
    }
  }

  /// Verified revelation info for a surah, or null if missing.
  static Future<SurahInfo?> infoForSurah(int surah) async {
    await ensureLoaded();
    return _info![surah];
  }

  /// Names / maqsad / fadail for a surah — extracted for all 114
  /// surahs (names for 41, maqsad 114/114, fadail 114/114; surahs
  /// without an alternative name or a dedicated fadail باب carry an
  /// honest source-coverage note instead of a fabricated entry).
  static Future<SurahScience?> scienceForSurah(int surah) async {
    await ensureLoaded();
    return _sciences![surah];
  }

  /// Reasons for revelation of one ayah, from صحيح أسباب النزول
  /// (al-Ali). Empty list when the dataset records none for it.
  static Future<List<String>> asbabForAyah(int surah, int verse) async {
    await ensureLoaded();
    return List<String>.unmodifiable(_asbab!['$surah:$verse'] ?? const []);
  }

  /// Word + letter counts for a surah, computed from the bundled
  /// text. Word count = true words (QCF word map); letter count =
  /// bare Arabic letters of the Uthmani text.
  static SurahStats statsForSurah(int surah) {
    final cached = _statsCache[surah];
    if (cached != null) return cached;
    var words = 0;
    var letters = 0;
    for (var v = 1; v <= quran.getVerseCount(surah); v++) {
      words += buildQcfWordMap(surah, v).wordCount;
      letters += _bareLetters(getVerse(surah, v)).length;
    }
    final stats = SurahStats(
      ayahCount: quran.getVerseCount(surah),
      wordCount: words,
      letterCount: letters,
    );
    _statsCache[surah] = stats;
    return stats;
  }

  /// Bare Arabic letters of a text (diacritics, marks and spaces
  /// stripped; hamza forms unified) — the letter-count basis.
  static String _bareLetters(String s) {
    final buf = StringBuffer();
    for (final c in s.codeUnits) {
      var ch = c;
      if (ch == 0x0622 || ch == 0x0623 || ch == 0x0625) ch = 0x0627;
      if (ch == 0x0624 || ch == 0x0626) ch = 0x064A;
      if (ch == 0x0621) ch = 0x064A;
      if (ch == 0x0649) ch = 0x064A;
      if (ch == 0x0671) ch = 0x0627;
      if ((ch >= 0x0627 && ch <= 0x064A) || ch == 0x0670) {
        buf.writeCharCode(ch);
      }
    }
    return buf.toString();
  }
}
