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
  // أحمد بن علي العجمي (v13.11, user order 2026-11-18): everyayah
  // folder, mp3quran server and islamic.network edition all
  // verified live (200) before adding — no Quran.com recitation
  // id verified, so none is set (do not invent one).
  Reciter(
    name: 'أحمد بن علي العجمي',
    server: 'cdn.mp3quran.net/audio/ahmad-ajmi/r1',
    everyayah: 'ahmed_ibn_ali_al_ajamy_128kbps',
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

/// Global ayah number (1-based, counting from 1:1): the key
/// islamic.network addresses per-ayah audio by (e.g. 7:1 = 955).
int globalAyahNumber(int surah, int ayah) {
  var n = ayah;
  for (var s = 1; s < surah; s++) {
    n += quran.getVerseCount(s);
  }
  return n;
}

/// Per-ayah mp3 of [reciter] from islamic.network (v13.11) — a
/// DIFFERENT host from everyayah.com, for when everyayah is
/// unreachable from the user's network: the user gets "تعذّر تحميل
/// الصوت" on strong internet (2026-11-18, page 151) because every
/// fallback above is the same everyayah host. Verified by CONTENT
/// (2026-11-18): islamic.network's files are the exact same
/// recordings as everyayah's — identical transcripts AND
/// bit-identical decoded PCM on sampled ayahs (Hani Rifai 4 ayahs;
/// الحصري، العفاسي، عبد الباسط، المعيقلي، إبراهيم الأخضر،
/// الشاطري، سويد، السديس 2 ayahs each; الحذيفي 3/4 bit-identical
/// + one different take; الشريم والعجمي transcript-verified,
/// 64k vs 128k so not bit-identical). Only editions verified that
/// way are listed here — never add a reciter on a name match alone.
/// Tunaiji has NO per-ayah files here (the API serves that edition
/// surah-by-surah only), so he has no islamic.network step — same
/// for محمد الطبلاوي and ياسر الدوسري (editions exist, 403
/// per-ayah). Since v13.12 all 16 reciters get alternate hosts
/// ([altAyahUrls]) — the three below have no islamic.network step,
/// and المنشاوي has no islamic.network step either (his edition
/// there is murattal, not mujawwad).
/// المنشاوي is also excluded: islamic.network's ar.minshawimujawwad
/// is the murattal recording under a mujawwad name (verified
/// 2026-11-18). Null when the reciter has no verified edition.
/// Since v13.12 every reciter — including المنشاوي, Tunaiji,
/// Tablawi and Dosari — gets alternate hosts instead
/// ([altAyahUrls]); المنشاوي's alternates are the genuine
/// mujawwad recording (Maqra + Al Furqan, content-verified).
/// عجمي caveat: his surah-first ayahs on islamic.network carry a
/// Basmala prefix (~2.5 s) before the ayah — mid-surah ayahs are
/// clean. As a fallback that beats silence, and the Basmala is
/// recited before most surahs anyway.
String? islamicNetworkUrl(Reciter reciter, int surah, int ayah) {
  // Verified by CONTENT (identical transcripts + bit-identical
  // decoded PCM on sampled ayahs, 2026-11-18) — only these.
  // (edition, kbps): Akhdar's per-ayah files live on the 32 kbps
  // path (the 64 path 403s); everyone else is 64.
  // Caveats (documented, not hidden): الحذيفي is bit-identical
  // on 3/4 sampled ayahs — 2:255 is the same voice's different
  // take (59.85 s vs 59.09 s). الشريم is transcript-verified
  // (correct ayah, right voice, durations within 0.03 s) but
  // 0/4 bit-identical — a different performance of the same
  // reciter. Both stay mapped: as a FALLBACK the right ayah in
  // the right voice beats silence.
  // NOT المنشاوي: islamic.network's ar.minshawimujawwad is the
  // murattal recording under a mujawwad name (its 2:255 is
  // byte-identical to ar.minshawi) — mapping it would play the
  // wrong style where mujawwad is expected, so he stays
  // everyayah-only. Never add a reciter on a name match alone.
  const editions = {
    'Hani_Rifai_64kbps': ('ar.hanirifai', 64),
    'Husary_64kbps': ('ar.husary', 64),
    'Alafasy_64kbps': ('ar.alafasy', 64),
    'Abdul_Basit_Murattal_64kbps': ('ar.abdulbasitmurattal', 64),
    'Maher_AlMuaiqly_64kbps': ('ar.mahermuaiqly', 64),
    'Ibrahim_Akhdar_32kbps': ('ar.ibrahimakhbar', 32),
    'ahmed_ibn_ali_al_ajamy_128kbps': ('ar.ahmedajamy', 64),
    'Hudhaify_64kbps': ('ar.hudhaify', 64),
    'Abu_Bakr_Ash-Shaatree_64kbps': ('ar.shaatree', 64),
    'Ayman_Sowaid_64kbps': ('ar.aymanswoaid', 64),
    'Saood_ash-Shuraym_64kbps': ('ar.saoodshuraym', 64),
    'Abdurrahmaan_As-Sudais_64kbps': ('ar.abdurrahmaansudais', 64),
  };
  final entry = editions[reciter.everyayah];
  if (entry == null) return null;
  final (edition, kbps) = entry;
  return 'https://cdn.islamic.network/quran/audio/$kbps/$edition/'
      '${globalAyahNumber(surah, ayah)}.mp3';
}

/// Per-ayah mp3 of [reciter] from SurahPedia (v13.13) — the host
/// SurahApp itself uses, so the one that demonstrably works from
/// the user's Syrian network while everyayah / islamic.network /
/// Maqra / mirrors keep failing on his phone there (v13.12, same
/// «تعذّر تحميل الصوت», Husary page 2). The bucket is public, no
/// auth: `https://resources.surahpedia.com/{Folder}/{SSSAAA}.mp3`
/// — the folder names are SurahApp's own bundled
/// `ReciterInfo.recitationDirectory` values, verified by CONTENT
/// 2026-11-18 (report at ~/workspace/noor-quran-v1/
/// reciter-alt-servers/surahpedia-audio-pattern.md): Husary
/// 002001.mp3 is byte-identical to everyayah Husary_64kbps
/// 002001.mp3 (SHA256 d822f6530…); Hani Rifai 2:1 and 7:1
/// byte-identical; Tunaiji/Tablawi/Dosari 2:255 transcribed as
/// Ayat al-Kursi. The files are the SAME everyayah recordings —
/// only the host is new, which is exactly what matters for Syria.
/// First step of [AudioDownloadService.cacheAyahFile] and of
/// [ayahStreamUrlsInOrder] for the 15 mapped reciters. Null for
/// العجمي: SurahPedia has NO folder for him (full bucket listing
/// checked; guesses Ajmi / Ahmed_Ajami / Ahmad_Ajami / Ajamy /
/// Ahmed_bin_Ali_Al-Ajmi all 404) — he keeps the v13.12 chain
/// unchanged, and no folder is invented for him. Whole-surah
/// files ({Folder}/{SSS}.mp3) exist for most reciters but are a
/// DIFFERENT slower take (Husary Baqarah 191 MB) — they are NEVER
/// used in playback and never sliced with per-ayah timings; page
/// preload uses per-ayah files only.
String? surahpediaAyahUrl(Reciter reciter, int surah, int ayah) {
  const folders = {
    'Husary_64kbps': 'Husary',
    'Alafasy_64kbps': 'Alafasy',
    'Minshawy_Mujawwad_64kbps': 'Minshawy_Mujawwad',
    'Abdul_Basit_Murattal_64kbps': 'Abdul_Basit_Murattal',
    'Maher_AlMuaiqly_64kbps': 'Maher_Al-Muaiqly',
    'Hudhaify_64kbps': 'Hudhaify',
    'Abu_Bakr_Ash-Shaatree_64kbps': 'Abu_Bakr_Ash-Shatree',
    'Ayman_Sowaid_64kbps': 'Ayman_Suwaid',
    'Saood_ash-Shuraym_64kbps': 'Saood_Ash-Shuraim',
    'Abdurrahmaan_As-Sudais_64kbps': 'Abdurrahmaan_As-Sudais',
    'Hani_Rifai_64kbps': 'Hani_Rifai',
    'Ibrahim_Akhdar_32kbps': 'Ibrahim_Al-kdar',
    'khalefa_al_tunaiji_64kbps': 'Khalefa_Al-Tunaiji',
    'Mohammad_al_Tablaway_64kbps': 'Mohammad_al_Tablaway',
    'Yasser_Ad-Dussary_128kbps': 'Yasser_Ad-Dussary',
  };
  final folder = folders[reciter.everyayah];
  if (folder == null) return null;
  return 'https://resources.surahpedia.com/$folder/'
      '${ayahFileName(surah, ayah)}.mp3';
}

/// Alternate per-ayah hosts for ALL 16 reciters (v13.12) — a
/// DIFFERENT host family from everyayah.com, for when everyayah is
/// unreachable from the user's Syrian network. Ordered per reciter
/// (primary first); tried in [AudioDownloadService.cacheAyahFile]
/// after the www per-ayah file and the islamic.network attempt,
/// before the bare per-ayah file — the same position
/// islamic.network occupies for the 12. Verified by CONTENT
/// 2026-11-18 (byte-identical samples vs everyayah — full reports
/// at ~/workspace/noor-quran-v1/reciter-alt-servers/REPORT.md,
/// REPORT-group-a.md, REPORT-group-b.md):
/// Tunaiji verses.quran.com + Maqra/Hugging Face; Tablawi
/// Maqra/Hugging Face + mirrors.quranicaudio.com 128k (same
/// recording re-encoded at 128k); Dosari mirrors.quranicaudio.com
/// + Maqra/Hugging Face; Husary mirror + Maqra; Afasy Maqra +
/// verses; Minshawi (genuine MUJAWWAD) Maqra + Al Furqan;
/// Abdul Basit mirror + Maqra; Muaiqly mirror + Maqra; Hani Maqra
/// + verses; Hudhaify Maqra + mirror 128k; Shatri Maqra + verses;
/// Suwaid mirror + Maqra; Shuraym Maqra + verses; Sudais Maqra +
/// verses; Akhdar Maqra 32k + Al Furqan; Ajmi Maqra 128k +
/// Al Furqan. Al Furqan is used only where no static host carries
/// the reciter (Minshawi, Akhdar, Ajmi) — its API serves the same
/// verified files. Hugging Face resolve URLs redirect
/// (huggingface.co → CDN); Dart's http client follows redirects
/// by default (verified live 2026-11-18: the Maqra 002255 files
/// resolve to 200, byte-identical to the everyayah references).
/// Syria reachability is NOT verified from the VM — only the
/// user's phone in Syria can test these hosts. Never add a host
/// on a name match alone: every URL above was verified by content
/// first. Minshawi's alternate hosts are the genuine MUJAWWAD
/// recording — never islamic.network's ar.minshawimujawwad (it is
/// murattal under a mujawwad name).
List<String> altAyahUrls(Reciter reciter, int surah, int ayah) {
  final name = ayahFileName(surah, ayah);
  switch (reciter.everyayah) {
    case 'khalefa_al_tunaiji_64kbps':
      return [
        'https://verses.quran.com/Tunaiji/mp3/$name.mp3',
        'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/$name.mp3',
      ];
    case 'Mohammad_al_Tablaway_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/mohammad-al-tablawi-64kbps/resolve/main/$name.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Mohammad_al_Tablaway_128kbps/$name.mp3',
      ];
    case 'Yasser_Ad-Dussary_128kbps':
      return [
        'https://mirrors.quranicaudio.com/everyayah/Yasser_Ad-Dussary_128kbps/$name.mp3',
        'https://huggingface.co/datasets/maqra-project/yasser-ad-dossari-128kbps/resolve/main/$name.mp3',
      ];
    case 'Husary_64kbps':
      return [
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/$name.mp3',
        'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/$name.mp3',
      ];
    case 'Alafasy_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/mishari-alafasy-64kbps/resolve/main/$name.mp3',
        'https://verses.quran.com/Alafasy/mp3/$name.mp3',
      ];
    case 'Minshawy_Mujawwad_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/mohamed-siddiq-al-minshawi-mujawwad-64kbps/resolve/main/$name.mp3',
        alFurqanAyahUrl('minshawy-mujawwad', surah, ayah),
      ];
    case 'Abdul_Basit_Murattal_64kbps':
      return [
        'https://mirrors.quranicaudio.com/everyayah/Abdul_Basit_Murattal_64kbps/$name.mp3',
        'https://huggingface.co/datasets/maqra-project/abdul-basit-murattal-64kbps/resolve/main/$name.mp3',
      ];
    case 'Maher_AlMuaiqly_64kbps':
      return [
        'https://mirrors.quranicaudio.com/everyayah/Maher_AlMuaiqly_64kbps/$name.mp3',
        'https://huggingface.co/datasets/maqra-project/maher-al-muaiqly-64kbps/resolve/main/$name.mp3',
      ];
    case 'Hani_Rifai_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/hani-ar-rifai-64kbps/resolve/main/$name.mp3',
        'https://verses.quran.com/Rifai/mp3/$name.mp3',
      ];
    case 'Hudhaify_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/ali-al-hudhaifi-64kbps/resolve/main/$name.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Hudhaify_128kbps/$name.mp3',
      ];
    case 'Abu_Bakr_Ash-Shaatree_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/abu-bakr-ash-shatri-64kbps/resolve/main/$name.mp3',
        'https://verses.quran.com/Shatri/mp3/$name.mp3',
      ];
    case 'Ayman_Sowaid_64kbps':
      return [
        'https://mirrors.quranicaudio.com/everyayah/Ayman_Sowaid_64kbps/$name.mp3',
        'https://huggingface.co/datasets/maqra-project/ayman-swaid-64kbps/resolve/main/$name.mp3',
      ];
    case 'Saood_ash-Shuraym_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/saud-ash-shuraim-64kbps/resolve/main/$name.mp3',
        'https://verses.quran.com/Shuraym/mp3/$name.mp3',
      ];
    case 'Abdurrahmaan_As-Sudais_64kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/abdurrahman-as-sudais-64kbps/resolve/main/$name.mp3',
        'https://verses.quran.com/Sudais/mp3/$name.mp3',
      ];
    case 'Ibrahim_Akhdar_32kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/ibrahim-al-akhdar-32kbps/resolve/main/$name.mp3',
        alFurqanAyahUrl('ibrahim-akhdar', surah, ayah),
      ];
    case 'ahmed_ibn_ali_al_ajamy_128kbps':
      return [
        'https://huggingface.co/datasets/maqra-project/ahmed-al-ajmi-128kbps/resolve/main/$name.mp3',
        alFurqanAyahUrl('ahmed-al-ajamy', surah, ayah),
      ];
    default:
      return const [];
  }
}

/// Per-ayah mp3 from the Al Furqan API (free, no key):
/// `https://alfurqan.online/api/v1/audio/<slug>/surah/<S>/ayah/<A>`
/// with UNPADDED surah/ayah numbers. Only used in [altAyahUrls]
/// for the three reciters no static host carries (Minshawi
/// mujawwad, Akhdar, Ajmi) — the API's files for them were verified
/// byte-identical to everyayah 2026-11-18. Rate limit 100 req/min/IP
/// per its docs: fine for a paced page preload, not for bursts.
String alFurqanAyahUrl(String slug, int surah, int ayah) =>
    'https://alfurqan.online/api/v1/audio/$slug/surah/$surah/ayah/$ayah';

/// The ayah-stream hosts in the order ONE ayah is streamed from
/// when the cache misses (v13.12 — the user's correction,
/// 2026-11-18): Wahy plays a single ayah directly, without
/// downloading the whole surah, and the word path already streams
/// from every host in order — but the ayah path streamed ONLY the
/// bare everyayah URL (blocked from Syria) with a 20 s timeout.
/// Now (v13.13): SurahPedia first for the 15 mapped reciters
/// ([surahpediaAyahUrl] — SurahApp's own host, the one that
/// works from Syria), then www per-ayah, then the alternate hosts
/// ([altAyahUrls] — the same Part 1 list), then islamic.network
/// (when the reciter has a verified edition), bare per-ayah last.
/// العجمي has no SurahPedia folder, so his order is the v13.12
/// one unchanged (www first). Cache-on-play
/// ([AudioDownloadService.cacheAyahFile]) stays the primary
/// path — this list is only the streaming fallback on a cache
/// failure, exactly like the word path ([wbwWordUrlsInOrder]).
/// Pure, pinned by unit tests.
List<String> ayahStreamUrlsInOrder(Reciter reciter, int surah, int ayah) {
  final urls = <String>[];
  final surahpediaUrl = surahpediaAyahUrl(reciter, surah, ayah);
  if (surahpediaUrl != null) urls.add(surahpediaUrl);
  urls.add(everyayahWwwUrl(reciter, surah, ayah));
  urls.addAll(altAyahUrls(reciter, surah, ayah));
  final islamicUrl = islamicNetworkUrl(reciter, surah, ayah);
  if (islamicUrl != null) urls.add(islamicUrl);
  urls.add(everyayahUrl(reciter, surah, ayah));
  return urls;
}

/// Moves the URL whose host matches [fastestHost] to the front of
/// [urls], keeping the rest in their standing order (v13.19
/// fastest-host memory: the host that delivered first buffered
/// data fastest on the last successful play is tried first next
/// time, so a slow first host does not burn its deadline on every
/// ayah). Returns [urls] unchanged when [fastestHost] is null, when
/// the chain has fewer than two URLs, or when no URL matches the
/// host (the host is not in this chain — e.g. a wbw-only host on
/// the ayah chain — so there is nothing to move). The remembered
/// host is only an ordering hint: it never bypasses the per-host
/// first-data deadline or the validation. Pure, pinned by unit
/// tests.
List<String> orderUrlsFastestFirst(List<String> urls, String? fastestHost) {
  if (fastestHost == null || fastestHost.isEmpty || urls.length < 2) {
    return urls;
  }
  final index = urls.indexWhere((url) {
    try {
      return Uri.parse(url).host == fastestHost;
    } catch (_) {
      return false;
    }
  });
  if (index <= 0) return urls;
  return [urls[index], ...urls.sublist(0, index), ...urls.sublist(index + 1)];
}

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
