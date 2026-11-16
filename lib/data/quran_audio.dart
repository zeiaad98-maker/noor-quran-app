import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:quran/quran.dart' as quran;

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
    quranComAudioPrefix:
        '//mirrors.quranicaudio.com/everyayah/Husary_64kbps/',
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
      byIndex[seg[0] as int] = WordSegment(seg[2] as int, seg[3] as int);
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
    final response =
        await http.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return null;
    final verse =
        (jsonDecode(response.body) as Map<String, dynamic>)['verse']
            as Map<String, dynamic>?;
    if (verse == null) return null;
    return parseWordSegments(verse);
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
