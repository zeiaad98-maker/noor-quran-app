import 'package:quran/quran.dart' as quran;

/// One reciter, with every audio source the player needs.
///
/// [server] is the mp3quran host path (no scheme) of the full-surah files,
/// e.g. `cdn.mp3quran.net/audio/mahmoud-husary/r1`.
/// [everyayah] is the per-ayah folder on everyayah.com, used for the
/// ayah / page / surah scopes and for repetition.
/// [quranComRecitationId] / [quranComAudioPrefix] are only set when
/// Quran.com API v4 carries this reciter. Word audio does NOT use
/// them: since v13.2 the word always plays from Quran.com's dedicated
/// per-word recording (wbw — one fixed teaching voice), never cut
/// from an ayah file (v13.1's segment path is gone: a tap on a word
/// played the whole ayah whenever the seek failed).
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

/// Per-ayah mp3 of [reciter] from the www host (v13.7) — the same
/// address Wahy uses: plain HTTP www, which 301-redirects to
/// `https://www.everyayah.com/...` (verified live 2026-11-18:
/// Tunaiji 002014.mp3 = 200, 159,379 B). Unlike the bare-HTTPS
/// [everyayahUrl] above, this host opens from the user's Syrian
/// network, so it is the first choice for on-demand ayah audio:
/// one small file (~80–160 KB) starts playback in seconds, where
/// the v13.5 ZIP-first order forced a whole-surah download
/// (~58 MB for Baqarah) before the first sound.
String everyayahWwwUrl(Reciter reciter, int surah, int ayah) =>
    'http://www.everyayah.com/data/${reciter.everyayah}/${ayahFileName(surah, ayah)}.mp3';

/// Per-surah ZIP of [reciter] from everyayah.com (v13.5) — Wahy's
/// exact method: Wahy downloads these ZIPs, which is why its ayah
/// audio works on the user's phone while our bare-HTTPS per-ayah
/// URL above does not open from his Syrian network. The address is
/// the plain-HTTP www one Wahy's API redirects to; it 301-redirects
/// to `https://www.everyayah.com/...` (verified live 2026-11-17:
/// Tunaiji 001.zip = 200, 379,310 B, a real ZIP with
/// 001001.mp3–001007.mp3 + 000_license.html; the 001001.mp3 inside
/// is 64 kbps / 5.67 s — Wahy's exact audio, same reciter folder,
/// a different take/bitrate than the per-ayah file). The ZIP is
/// downloaded once per surah and unzipped into the ayah cache dir,
/// so a surah once downloaded plays fully offline.
String everyayahSurahZipUrl(Reciter reciter, int surah) =>
    'http://www.everyayah.com/data/${reciter.everyayah}/zips/'
    '${surah.toString().padLeft(3, '0')}.zip';

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
/// every word of every ayah). [fileNumber] IS the word's 1-based
/// position among the ayah's audio words — the wbw files are
/// numbered by word position only (v13.4): pause marks (ۖ ۗ etc.)
/// do NOT count as positions, whatever the Quran.com API's
/// audio_url field says (it counts them — proven by transcription
/// 2026-11-17: 3:7 word 15 الَّذِينَ is file 015, the API claims
/// 016, and 016 speaks فِي). The hosts are tried in
/// [wbwWordUrlsInOrder] (SurahPedia first since v13.6); the
/// individual builders below are the pieces of that order.
String wbwWordUrl(int surah, int ayah, int fileNumber) =>
    'https://audio.qurancdn.com/wbw/'
    '${surah.toString().padLeft(3, '0')}_'
    '${ayah.toString().padLeft(3, '0')}_'
    '${fileNumber.toString().padLeft(3, '0')}.mp3';

/// Legacy host for the wbw recording (verses.quran.com) — third
/// attempt in [wbwWordUrlsInOrder], when SurahPedia and the current
/// CDN both fail.
String wbwWordUrlLegacy(int surah, int ayah, int fileNumber) =>
    'https://verses.quran.com/wbw/'
    '${surah.toString().padLeft(3, '0')}_'
    '${ayah.toString().padLeft(3, '0')}_'
    '${fileNumber.toString().padLeft(3, '0')}.mp3';

/// SurahPedia host for the wbw recording
/// (resources.surahpedia.com) — FIRST attempt since v13.6 (Wahy's
/// host, proven reachable from the user's Syrian network while the
/// Quran.com hosts are not). A different host, so it can work when
/// the Quran.com hosts are unreachable from the user's network (the
/// user's 'no internet' on a strong connection). Verified 2026-11-17
/// by decompiling Wahy 1.4.9: Wahy's soundOfWord_v2 endpoint
/// 302-redirects to these files, which are BYTE-IDENTICAL to the
/// Quran.com wbw files (MD5-verified — e.g. 003007015 =
/// 16c7e66e1d61d479b544133af3bf0bb2 on both hosts).
/// Note the pattern: slash-separated
/// Word_by-Word/{surah}/{SSSAAAWWW}.mp3, no underscores — the
/// surah folder is unpadded, the file name is the three 3-digit
/// parts concatenated.
String wbwWordUrlSurahPedia(int surah, int ayah, int fileNumber) =>
    'https://resources.surahpedia.com/Word_by-Word/'
    '${surah.toString()}/'
    '${surah.toString().padLeft(3, '0')}'
    '${ayah.toString().padLeft(3, '0')}'
    '${fileNumber.toString().padLeft(3, '0')}.mp3';

/// The wbw hosts in the order a word file is attempted (v13.6):
/// SurahPedia FIRST (Wahy's host — the one that opens from the
/// user's network), then the Quran.com CDN, then the legacy host.
/// One list, used by BOTH the cache path ([AudioDownloadService.
/// cacheWbwFile]) and the streaming path ([AudioPlayerController.
/// _playWbwWord]) so the two can never drift apart again — the
/// v13.5 screenshot showed the word stuck loading because the
/// blocked hosts were tried first and the working one last.
List<String> wbwWordUrlsInOrder(int surah, int ayah, int fileNumber) => [
      wbwWordUrlSurahPedia(surah, ayah, fileNumber),
      wbwWordUrl(surah, ayah, fileNumber),
      wbwWordUrlLegacy(surah, ayah, fileNumber),
    ];

/// v13.4 — the wbw shift table is DELETED, on purpose. It encoded
/// the Quran.com API's audio_url numbering, which counts pause
/// marks as positions; transcription of the real files (2026-11-17,
/// two ASR models in agreement, then a 28-word cross-surah check)
/// proved the FILES are numbered by word position only — file N
/// speaks word N. The API field is wrong relative to its own
/// files, so any table derived from it is wrong too. The wbw file
/// number of a word is its 1-based position among the ayah's
/// audio words ([audioPositionForQcfWord]); no table, no lookup,
/// nothing to go stale.


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

/// Ayahs where the DISPLAY word list (QCF / Mushaf text) and the
/// AUDIO word list (Quran.com API / wbw files / morphology) disagree:
/// two display words are ONE audio word (one wbw file, one API word
/// entry). Verified live 2026-11-17 (API words + wbw 404 probe for
/// 37:130 file 004) and against the bundled morphology (QCF count =
/// token count + 1 in exactly these 4 ayahs, equal everywhere else):
///   * 2:181, 8:6, 13:37 — بَعۡدَ مَا is two display words, one audio
///     word (API word 3 = 'بَعْدَ مَا', wbw file 003 covers both);
///   * 37:130 — إِلۡ يَاسِينَ is two display words, one audio word
///     (API word 3 = 'إِلْ يَاسِينَ', wbw file 003 covers both; file
///     004 does not exist).
/// Keyed by ayah, value = the two 0-based DISPLAY word indices that
/// share one audio word. Every other ayah: display index == audio
/// index, no translation needed.
const Map<String, List<int>> _mergedAudioWords = {
  '2:181': [2, 3],
  '8:6': [3, 4],
  '13:37': [7, 8],
  '37:130': [2, 3],
};

/// The AUDIO word position (1-based, position among the ayah's
/// audio words) of a DISPLAY word tap: [qcfWord] is the 1-based QCF
/// word index (the index the reader reports for the tapped glyph).
/// This position IS the wbw file number (v13.4 — no shift is
/// applied). In the 4 merged ayahs above, both halves of the pair
/// map to the ONE shared audio position, and every word after the
/// pair shifts down by one — without this, tapping a word after the
/// pair plays the NEXT word's file (the v9 word-chip bug, re-found
/// in v13.2). Pure, pinned by unit tests (2:181 word 5 → 4,
/// 37:130 word 4 → 3).
int audioPositionForQcfWord(int surah, int ayah, int qcfWord) {
  final pair = _mergedAudioWords['$surah:$ayah'];
  if (pair == null) return qcfWord;
  if (qcfWord <= pair[0] + 1) return qcfWord;
  if (qcfWord <= pair[1] + 1) return pair[0] + 1;
  return qcfWord - 1;
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
