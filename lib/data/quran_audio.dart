import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

/// One reciter, with every audio source the player needs.
///
/// [server] is the mp3quran host path (no scheme) of the full-surah files,
/// e.g. `cdn.mp3quran.net/audio/mahmoud-husary/r1`.
/// [everyayah] is the per-ayah folder on everyayah.com, used for the
/// ayah / page / surah scopes and for repetition.
/// [quranComRecitationId] / [quranComAudioPrefix] are only set when
/// Quran.com API v4 carries this reciter: they power per-word audio
/// (timed segments inside the reciter's own ayah recording). Reciters
/// without them still get word audio from Quran.com's word-by-word
/// recording (`wbw/...mp3`, one fixed voice).
///
/// Every URL in this list was verified with curl before it was added
/// (mp3quran `001.mp3` -> 200 audio/mpeg, everyayah `001001.mp3` -> 200).
/// Two candidates were rejected:
/// * محمد أيوب — mp3quran works, but everyayah has no folder for him at
///   all, so there is no per-ayah audio; he stays out of the player.
/// * إبراهيم الأخضر `Ibrahim_Akhdar_64kbps` — the folder is listed but
///   its files 404, so the working `Ibrahim_Akhdar_32kbps` is used.
class Reciter {
  final String name;
  final String server;
  final String everyayah;
  final int? quranComRecitationId;
  final String? quranComAudioPrefix;

  const Reciter({
    required this.name,
    required this.server,
    required this.everyayah,
    this.quranComRecitationId,
    this.quranComAudioPrefix,
  });
}

const List<Reciter> reciters = [
  Reciter(
    name: 'محمود الحصري',
    server: 'cdn.mp3quran.net/audio/mahmoud-husary/r1',
    everyayah: 'Husary_64kbps',
    quranComRecitationId: 6,
    quranComAudioPrefix: '//mirrors.quranicaudio.com/everyayah/Husary_64kbps/',
  ),
  Reciter(
    name: 'مشاري العفاسي',
    server: 'cdn.mp3quran.net/audio/mishary-alafasy/r1',
    everyayah: 'Alafasy_64kbps',
    quranComRecitationId: 7,
    quranComAudioPrefix: 'Alafasy/mp3/',
  ),
  Reciter(
    name: 'محمد صديق المنشاوي',
    server: 'cdn.mp3quran.net/audio/muhammad-minshawi/r2',
    everyayah: 'Minshawy_Mujawwad_64kbps',
    quranComRecitationId: 8,
    quranComAudioPrefix: 'Minshawi/Mujawwad/mp3/',
  ),
  Reciter(
    name: 'عبد الباسط عبد الصمد',
    server: 'cdn.mp3quran.net/audio/abdulbasit-abdulsamad/r3',
    everyayah: 'Abdul_Basit_Murattal_64kbps',
    quranComRecitationId: 2,
    quranComAudioPrefix: 'AbdulBaset/Murattal/mp3/',
  ),
  Reciter(
    name: 'ماهر المعيقلي',
    server: 'cdn.mp3quran.net/audio/maher-muaiqly/r1',
    everyayah: 'Maher_AlMuaiqly_64kbps',
  ),
  Reciter(
    name: 'علي الحذيفي',
    server: 'cdn.mp3quran.net/audio/ali-hudhaifi/r1',
    everyayah: 'Hudhaify_64kbps',
  ),
  Reciter(
    name: 'أبو بكر الشاطري',
    server: 'cdn.mp3quran.net/audio/abubakr-shatri/r1',
    everyayah: 'Abu_Bakr_Ash-Shaatree_64kbps',
    quranComRecitationId: 4,
    quranComAudioPrefix: 'Shatri/mp3/',
  ),
  Reciter(
    name: 'أيمن سويد',
    server: 'server15.mp3quran.net/a-rushdi/Almusshaf-Al-Mo-lim',
    everyayah: 'Ayman_Sowaid_64kbps',
  ),
  Reciter(
    name: 'سعود الشريم',
    server: 'cdn.mp3quran.net/audio/saud-shuraim/r1',
    everyayah: 'Saood_ash-Shuraym_64kbps',
    quranComRecitationId: 10,
    quranComAudioPrefix: 'Shuraym/mp3/',
  ),
  Reciter(
    name: 'عبد الرحمن السديس',
    server: 'cdn.mp3quran.net/audio/abdulrahman-sudais/r1',
    everyayah: 'Abdurrahmaan_As-Sudais_64kbps',
    quranComRecitationId: 3,
    quranComAudioPrefix: 'Sudais/mp3/',
  ),
  Reciter(
    name: 'هاني الرفاعي',
    server: 'cdn.mp3quran.net/audio/hani-rifai/r1',
    everyayah: 'Hani_Rifai_64kbps',
    quranComRecitationId: 5,
    quranComAudioPrefix: 'Rifai/mp3/',
  ),
  Reciter(
    name: 'إبراهيم الأخضر',
    server: 'cdn.mp3quran.net/audio/ibrahim-akhdar/r1',
    everyayah: 'Ibrahim_Akhdar_32kbps',
  ),
  Reciter(
    name: 'خليفة الطنيجي',
    server: 'cdn.mp3quran.net/audio/khalifa-tunaiji/r1',
    everyayah: 'khalefa_al_tunaiji_64kbps',
  ),
  Reciter(
    name: 'محمد الطبلاوي',
    server: 'cdn.mp3quran.net/audio/muhammad-tablawi/r1',
    everyayah: 'Mohammad_al_Tablaway_64kbps',
    quranComRecitationId: 11,
    quranComAudioPrefix:
        '//mirrors.quranicaudio.com/everyayah/Mohammad_al_Tablaway_128kbps/',
  ),
  Reciter(
    name: 'ياسر الدوسري',
    server: 'cdn.mp3quran.net/audio/yasser-dosari/r1',
    everyayah: 'Yasser_Ad-Dussary_128kbps',
  ),
];

/// `SSSAAA` file name used by everyayah and by Quran.com ayah audio.
String ayahFileName(int surah, int ayah) =>
    '${surah.toString().padLeft(3, '0')}${ayah.toString().padLeft(3, '0')}';

/// Per-ayah mp3 of [reciter] from everyayah.com.
String everyayahUrl(Reciter reciter, int surah, int ayah) =>
    'https://everyayah.com/data/${reciter.everyayah}/${ayahFileName(surah, ayah)}.mp3';

/// Full-surah mp3 of [reciter] from mp3quran.net (fallback only —
/// the player normally plays the surah as a sequence of ayah files).
String mp3quranSurahUrl(Reciter reciter, int surah) =>
    'https://${reciter.server}/${surah.toString().padLeft(3, '0')}.mp3';

/// Quran.com ayah audio of [reciter] (the file whose timings the
/// word segments below refer to). Null when Quran.com does not carry
/// this reciter.
String? quranComAyahUrl(Reciter reciter, int surah, int ayah) {
  final prefix = reciter.quranComAudioPrefix;
  if (prefix == null) return null;
  if (prefix.startsWith('//')) {
    return 'https:$prefix${ayahFileName(surah, ayah)}.mp3';
  }
  return 'https://verses.quran.com/$prefix${ayahFileName(surah, ayah)}.mp3';
}

/// Word-by-word recording from Quran.com (one fixed voice, works for
/// every word of every ayah). Used for reciters without Quran.com
/// segments, so word audio is never simply missing.
String wbwWordUrl(int surah, int ayah, int wordIndex) =>
    'https://verses.quran.com/wbw/'
    '${surah.toString().padLeft(3, '0')}_'
    '${ayah.toString().padLeft(3, '0')}_'
    '${wordIndex.toString().padLeft(3, '0')}.mp3';

/// Timed span of one word inside its ayah recording, in milliseconds.
class WordSegment {
  final int startMs;
  final int endMs;
  const WordSegment(this.startMs, this.endMs);
}

/// Default reciter (v13): خليفة الطنيجي (index 12 in [reciters]).
/// The user asked for him by name — the current default's pronunciation
/// "isn't good at all when it pronounces it".
const int defaultReciterIndex = 12;

/// The reciter the player starts with. A value the user chose himself
/// is kept; absent, or still the old default (0 = الحصري — the user
/// never chose a reciter, so his saved value is the old default),
/// migrates to الطنيجي. Pure, so it is pinned by unit tests.
int resolveDefaultReciterIndex(int? stored) {
  if (stored == null || stored == 0) return defaultReciterIndex;
  return stored.clamp(0, reciters.length - 1);
}

/// Quran.com segment numbers are ints for most recitations but STRINGS
/// for some (verified live 2026-11-17: Sudais / recitation 3 returns
/// `["0", "1", "50", "570"]` for 2:33) — a bare `as int` throws and
/// the whole ayah falls back to the wbw voice. Coerce both shapes.
int _segmentInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? -1;
  if (value is num) return value.toInt();
  return -1;
}

/// Parses a Quran.com API v4 verse object into its ordered word
/// segments (index 0 = first word). Pure function, so it can be
/// tested against a canned real response.
///
/// The API shape (verified live 2026-11-16, verse 2:33, recitation 6):
/// `verse.audio.segments` is a list of `[wordIndex0, wordIndex1,
/// startMs, endMs]`, e.g. `[0, 1, 850, 1760]`. Returns null when the
/// shape is missing or incomplete (a segment index with no entry).
List<WordSegment>? parseWordSegments(Map<String, dynamic> verseJson) {
  final audio = verseJson['audio'] as Map<String, dynamic>?;
  final segments = audio?['segments'] as List<dynamic>?;
  if (segments == null || segments.isEmpty) return null;
  // Each segment is [wordIndex0, wordIndex1, startMs, endMs].
  final byIndex = <int, WordSegment>{};
  for (final raw in segments) {
    final seg = raw as List<dynamic>;
    if (seg.length >= 4) {
      final index = _segmentInt(seg[0]);
      final start = _segmentInt(seg[2]);
      final end = _segmentInt(seg[3]);
      // A malformed entry is skipped: the contiguity check below
      // then returns null (wbw fallback) instead of a wrong window.
      if (index < 0 || start < 0 || end <= start) continue;
      byIndex[index] = WordSegment(start, end);
    }
  }
  if (byIndex.isEmpty) return null;
  final ordered = <WordSegment>[];
  for (var i = 0; i < byIndex.length; i++) {
    final s = byIndex[i];
    if (s == null) return null;
    ordered.add(s);
  }
  return ordered;
}

/// Per-word timestamps of one ayah from Quran.com API v4
/// (`/verses/by_key/{s}:{a}?audio={recitationId}`), in the reciter's
/// own voice. Returns the segments in word order (index 0 = first
/// word), or null when the reciter has no Quran.com recitation or the
/// request fails.
Future<List<WordSegment>?> fetchWordSegments(
  Reciter reciter,
  int surah,
  int ayah,
) async {
  final recitationId = reciter.quranComRecitationId;
  if (recitationId == null) return null;
  try {
    final uri = Uri.parse(
      'https://api.quran.com/api/v4/verses/by_key/$surah:$ayah'
      '?language=ar&words=false&audio=$recitationId&fields=text_uthmani',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final verse = (jsonDecode(response.body) as Map<String, dynamic>)['verse']
        as Map<String, dynamic>?;
    if (verse == null) return null;
    return parseWordSegments(verse);
  } catch (_) {
    return null;
  }
}

// -- Word-segment resolution (word audio, no per-tap API wait) --------
//
// Root cause of the v9 word-audio failure on a weak connection: every
// word tap first waited on api.quran.com (Cloudflare — the only
// non-BunnyCDN host in the audio path, 15 s timeout, no cache, no
// timeout on the setUrl that follows), then streamed the whole
// 408 KB ayah file before a late word could sound. Resolution order
// below makes the common path (Husary, recitation 6) fully offline:
//   1. bundled asset for Husary — never touches the network;
//   2. SharedPreferences cache for the other segment reciters
//      (one API call per ayah, ever);
//   3. the API, cached on success.
// Anything without segments falls back to the wbw recording.

/// Bundled Husary (recitation 6) segments for the whole Mushaf:
/// `assets/quran_data/word_segments_husary.json`, generated from the
/// live API by `tool/fetch_husary_word_segments.py`
/// (`{"2:33": [[850, 1760], ...], ...}`, 6218 ayahs / 77,098 words).
/// 18 ayahs are absent: the API skips a word index there (e.g. 2:125
/// jumps from index 16 to 18), so no contiguous segment list exists —
/// those ayahs fall back to wbw, exactly as a failed API call would.
Map<String, dynamic>? _bundledHusary;
Future<void>? _bundledHusaryFuture;

Future<void> _ensureBundledHusary() async {
  _bundledHusaryFuture ??= rootBundle
      .loadString('assets/quran_data/word_segments_husary.json')
      .then((raw) {
    _bundledHusary = jsonDecode(raw) as Map<String, dynamic>;
  });
  return _bundledHusaryFuture!;
}

/// Segments of one ayah from the bundled Husary asset, or null when
/// the ayah is one of the 28 without a contiguous list. Pure parsing
/// of a decoded pair list, so tests can inject a fake bundle.
List<WordSegment>? parseStoredSegments(List<dynamic> pairs) {
  final out = <WordSegment>[];
  var prevStart = -1;
  for (final raw in pairs) {
    final pair = raw as List<dynamic>;
    if (pair.length < 2) return null;
    final start = pair[0] as int;
    final end = pair[1] as int;
    // Starts must not go backwards. Overlapping spans ARE allowed:
    // a segment spanning several words is stored once per word it
    // covers (e.g. 2:125 has [34280, 37290] twice), so start can
    // equal — but never fall below — the previous start.
    if (start < 0 || end <= start || start < prevStart) return null;
    out.add(WordSegment(start, end));
    prevStart = start;
  }
  return out.isEmpty ? null : out;
}

/// Test seam: replace the bundled Husary map (and reset the loader).
@visibleForTesting
void setBundledHusaryForTest(Map<String, dynamic>? bundle) {
  _bundledHusary = bundle;
  _bundledHusaryFuture = bundle == null ? null : Future<void>.value();
}

Future<List<WordSegment>?> bundledWordSegments(int surah, int ayah) async {
  await _ensureBundledHusary();
  final raw = _bundledHusary!['$surah:$ayah'] as List<dynamic>?;
  if (raw == null) return null;
  return parseStoredSegments(raw);
}

/// Cheapest-first segment resolution for one ayah (see above).
/// Never throws: every failure degrades to null (wbw fallback).
Future<List<WordSegment>?> wordSegmentsFor(
    Reciter reciter, int surah, int ayah) async {
  final recitationId = reciter.quranComRecitationId;
  if (recitationId == null) return null;
  if (recitationId == 6) return bundledWordSegments(surah, ayah);
  final key = 'word_segments_${recitationId}_$surah:$ayah';
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(key);
    if (cached != null) {
      final stored = jsonDecode(cached) as List<dynamic>;
      final segments = parseStoredSegments(stored);
      if (segments != null) return segments;
      await prefs.remove(key);
    }
    final segments = await fetchWordSegments(reciter, surah, ayah);
    if (segments != null) {
      await prefs.setString(
        key,
        jsonEncode([
          for (final s in segments) [s.startMs, s.endMs],
        ]),
      );
    }
    return segments;
  } catch (_) {
    return null;
  }
}

/// All (surah, ayah) pairs on one Mushaf page, in reading order.
List<(int, int)> ayahsOfPage(int page) {
  final out = <(int, int)>[];
  for (final data in quran.getPageData(page)) {
    final surah = data['surah'] as int;
    for (var v = data['start'] as int; v <= (data['end'] as int); v++) {
      out.add((surah, v));
    }
  }
  return out;
}

/// All (surah, ayah) pairs on pages [fromPage]..[toPage], in order.
List<(int, int)> ayahsOfPages(int fromPage, int toPage) {
  final out = <(int, int)>[];
  for (var p = fromPage; p <= toPage; p++) {
    out.addAll(ayahsOfPage(p));
  }
  return out;
}

/// All (surah, ayah) pairs of one surah, in order.
List<(int, int)> ayahsOfSurah(int surah) => [
      for (var v = 1; v <= quran.getVerseCount(surah); v++) (surah, v),
    ];
