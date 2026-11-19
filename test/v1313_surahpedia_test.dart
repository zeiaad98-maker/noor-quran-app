import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'fake_mp3.dart';

/// v13.13 — SurahPedia FIRST (user order 2026-11-19, "try every
/// method"): v13.12 still failed on his phone (Husary, page 2,
/// same «تعذّر تحميل الصوت») because everyayah / islamic.network /
/// Maqra / mirrors all fail from his Syrian network — while
/// SurahApp works beautifully there, because its audio comes from
/// its OWN servers (resources.surahpedia.com). The pattern was
/// found by listing the public bucket and verified by CONTENT
/// 2026-11-18 (full report: ~/workspace/noor-quran-v1/
/// reciter-alt-servers/surahpedia-audio-pattern.md): Husary
/// 002001.mp3 is byte-identical to everyayah Husary_64kbps
/// 002001.mp3 (SHA256 d822f6530…); Hani Rifai 2:1 and 7:1
/// byte-identical; Tunaiji/Tablawi/Dosari 2:255 transcribed as
/// Ayat al-Kursi. The files are the SAME everyayah recordings —
/// only the host is new, which is exactly what matters for Syria.
/// SurahPedia is now step 0 of [AudioDownloadService.
/// cacheAyahFile] and of [ayahStreamUrlsInOrder] for the 15
/// mapped reciters; العجمي has NO folder there, so his chain is
/// the v13.12 one unchanged. Whole-surah files are NEVER used in
/// playback (a different slower take) — per-ayah files only.
/// No real HTTP is made except the one live test at the bottom,
/// which skips gracefully when the network is unavailable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final husary = reciters.firstWhere((r) => r.name == 'محمود الحصري');
  final hani = reciters.firstWhere((r) => r.name == 'هاني الرفاعي');
  final tunaiji =
      reciters.firstWhere((r) => r.name == 'خليفة الطنيجي');
  final ajmi =
      reciters.firstWhere((r) => r.name == 'أحمد بن علي العجمي');
  final minshawi =
      reciters.firstWhere((r) => r.name == 'محمد صديق المنشاوي');

  group('surahpediaAyahUrl pins — all 15 mapped reciters (v13.13)',
      () {
    test('exact URL per reciter for 2:255 and 7:1', () {
      // (everyayah folder, SurahPedia folder). Folder names are
      // SurahApp's own bundled ReciterInfo.recitationDirectory
      // values — exact case matters (Husary, not husary).
      final expected = <String, String>{
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
      expect(reciters.length, 16);
      var mapped = 0;
      for (final reciter in reciters) {
        final folder = expected[reciter.everyayah];
        if (folder == null) continue;
        mapped++;
        expect(surahpediaAyahUrl(reciter, 2, 255),
            'https://resources.surahpedia.com/$folder/002255.mp3',
            reason: reciter.name);
        // 7:1 pins the same folder with the other file name —
        // the pattern, not just one ayah, is what the player
        // relies on.
        expect(surahpediaAyahUrl(reciter, 7, 1),
            'https://resources.surahpedia.com/$folder/007001.mp3',
            reason: '${reciter.name} 7:1');
      }
      expect(mapped, 15);
    });

    test('Ajmi: NO SurahPedia URL — no folder is invented', () {
      // Full bucket listing checked 2026-11-18: no Ajmi folder;
      // guesses Ajmi / Ahmed_Ajami / Ahmad_Ajami / Ajamy /
      // Ahmed_bin_Ali_Al-Ajmi all 404 for 002001.mp3.
      expect(surahpediaAyahUrl(ajmi, 2, 255), isNull);
      expect(surahpediaAyahUrl(ajmi, 7, 1), isNull);
      expect(surahpediaAyahUrl(ajmi, 2, 1), isNull);
    });
  });

  group('ayahStreamUrlsInOrder — SurahPedia first (v13.13)', () {
    test('order pins: SurahPedia, www, alternates, islamic, bare',
        () {
      // Husary (islamic.network mapped): 6 hosts.
      expect(ayahStreamUrlsInOrder(husary, 2, 255), [
        'https://resources.surahpedia.com/Husary/002255.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002255.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/002255.mp3',
        'https://cdn.islamic.network/quran/audio/64/ar.husary/262.mp3',
        'https://everyayah.com/data/Husary_64kbps/002255.mp3',
      ]);
      // Minshawi (NO islamic.network step — murattal under a
      // mujawwad name): 5 hosts, Maqra then Al Furqan.
      expect(ayahStreamUrlsInOrder(minshawi, 2, 255), [
        'https://resources.surahpedia.com/Minshawy_Mujawwad/002255.mp3',
        'http://www.everyayah.com/data/Minshawy_Mujawwad_64kbps/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/mohamed-siddiq-al-minshawi-mujawwad-64kbps/resolve/main/002255.mp3',
        'https://alfurqan.online/api/v1/audio/minshawy-mujawwad/surah/2/ayah/255',
        'https://everyayah.com/data/Minshawy_Mujawwad_64kbps/002255.mp3',
      ]);
      // Tunaiji (no islamic.network per-ayah): 5 hosts.
      expect(ayahStreamUrlsInOrder(tunaiji, 7, 1), [
        'https://resources.surahpedia.com/Khalefa_Al-Tunaiji/007001.mp3',
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/007001.mp3',
        'https://verses.quran.com/Tunaiji/mp3/007001.mp3',
        'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/007001.mp3',
        'https://everyayah.com/data/khalefa_al_tunaiji_64kbps/007001.mp3',
      ]);
      // Ajmi: NO SurahPedia step — the v13.12 order unchanged
      // (www first), 5 hosts.
      expect(ayahStreamUrlsInOrder(ajmi, 2, 255), [
        'http://www.everyayah.com/data/ahmed_ibn_ali_al_ajamy_128kbps/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/ahmed-al-ajmi-128kbps/resolve/main/002255.mp3',
        'https://alfurqan.online/api/v1/audio/ahmed-al-ajamy/surah/2/ayah/255',
        'https://cdn.islamic.network/quran/audio/64/ar.ahmedajamy/262.mp3',
        'https://everyayah.com/data/ahmed_ibn_ali_al_ajamy_128kbps/002255.mp3',
      ]);
      // Every mapped reciter streams from SurahPedia first;
      // every reciter ends at the bare file.
      for (final reciter in reciters) {
        final urls = ayahStreamUrlsInOrder(reciter, 2, 255);
        final sp = surahpediaAyahUrl(reciter, 2, 255);
        if (sp == null) {
          expect(urls.first,
              startsWith('http://www.everyayah.com/'),
              reason: reciter.name);
          expect(urls.length, 5, reason: reciter.name);
        } else {
          expect(urls.first, sp, reason: reciter.name);
          expect(urls.length,
              islamicNetworkUrl(reciter, 2, 255) == null ? 5 : 6,
              reason: reciter.name);
        }
        expect(urls.last,
            startsWith('https://everyayah.com/'),
            reason: reciter.name);
      }
    });
  });

  group('cacheAyahFile — SurahPedia first (v13.13)', () {
    late Directory tempDir;

    Future<AudioDownloadService> makeService(
        http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v1313-sp');
      final s = AudioDownloadService(
        client: client,
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await s.init();
      return s;
    }

    tearDown(() async {
      AudioDownloadService.fetchAttempts = 2;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Husary: SurahPedia serves it, nothing else requested',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'resources.surahpedia.com') {
          return http.Response.bytes(fakeMp3Bytes(fill: 1), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(husary, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 1));
      expect(requested, [
        'https://resources.surahpedia.com/Husary/002255.mp3',
      ]);
    });

    test('Husary: SurahPedia 404s, www serves it next', () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'resources.surahpedia.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes(fakeMp3Bytes(fill: 2), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(husary, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 2));
      expect(requested, [
        'https://resources.surahpedia.com/Husary/002255.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002255.mp3',
      ]);
    });

    test('Hani: SurahPedia serves page-151 ayah 7:1', () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'resources.surahpedia.com') {
          return http.Response.bytes(fakeMp3Bytes(fill: 7), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(hani, 7, 1);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 7));
      expect(requested, [
        'https://resources.surahpedia.com/Hani_Rifai/007001.mp3',
      ]);
    });

    test('Ajmi: NO SurahPedia request — v13.12 chain unchanged',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'cdn.islamic.network') {
          return http.Response.bytes(fakeMp3Bytes(fill: 6), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(ajmi, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 6));
      expect(requested, [
        'http://www.everyayah.com/data/ahmed_ibn_ali_al_ajamy_128kbps/002255.mp3',
        'https://cdn.islamic.network/quran/audio/64/ar.ahmedajamy/262.mp3',
      ]);
      expect(requested.any((u) => u.contains('surahpedia.com')),
          isFalse);
    });
  });

  group('live SurahPedia check (v13.13)', () {
    test('SurahPedia URL answers 200 for 2:255 (skips offline)',
        () async {
      // One real GET per content-verified reciter, built by the
      // app's own URL builder — not a copy of the report's
      // strings. A network failure skips the test instead of
      // failing the suite (the files were already verified by
      // content 2026-11-18 — SHA256 vs everyayah; this only
      // re-checks they still answer).
      for (final reciter in [husary, hani, tunaiji]) {
        final url = surahpediaAyahUrl(reciter, 2, 255)!;
        try {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));
          expect(response.statusCode, 200, reason: url);
          expect(response.bodyBytes.length, greaterThan(10000),
              reason: url);
        } on Exception {
          markTestSkipped('network unavailable for $url');
          return;
        }
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
