import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';
import 'fake_mp3.dart';

/// v13.12 — the RADICAL audio fix (user order 2026-11-18, "root
/// fix, not a workaround", corrected the same day): v13.11 still
/// failed on his phone (Husary, page 2) because the app downloads
/// every ayah one-by-one on demand over flaky mobile data with a
/// 30 s stall timeout, and the whole-page preload failed the WHOLE
/// page on the FIRST failed ayah. The correction: Wahy plays a
/// single ayah or a single word alone WITHOUT downloading the
/// whole surah — so there is NO whole-surah ZIP anywhere in the
/// playback path. One page plays by itself, complete, from
/// per-ayah files only; the ZIP lives only in the explicit bulk
/// download the user starts from «تحميل التلاوات».
///
/// Three parts, all pinned here:
/// * Part 1 — alternate per-ayah hosts for ALL 16 reciters (the
///   v13.12 wiring covered only Tunaiji/Tablawi/Dosari): two
///   content-verified hosts each (mirrors / Maqra / verses /
///   Al Furqan — reports at ~/workspace/noor-quran-v1/
///   reciter-alt-servers/REPORT.md, REPORT-group-a.md,
///   REPORT-group-b.md), slotted at step 2b (after www +
///   islamic.network, before bare). URL pins for 2:255 + 7:1 per
///   reciter, plus fallback-order assertions.
/// * Part 2 — page preload ([AudioDownloadService.preloadAyahs]):
///   the fast path collects the missing ayahs instead of failing
///   on the first one, then the full per-ayah chain runs ONCE MORE
///   for the missing ayahs only; only ayahs STILL missing fail
///   the preload (the service still returns false then). v13.14:
///   a failed preload no longer GATES playPages — it falls through
///   to _playCurrent and streams ayah-by-ayah through the native
///   player (the user's phone fails every Dart download). The
///   "all hosts fail on both passes" playPages test pins the new
///   behaviour; the preloadAyahs service test still pins false.
///   No ZIP in playback, ever.
/// * Part 3 — single-ayah streaming fallback, mirroring the word
///   path ([ayahStreamUrlsInOrder]): on a cache failure the ayah
///   streams from www, then the alternates, then islamic.network,
///   bare last — instead of only the bare URL (blocked from Syria).
///   v13.13: SurahPedia is now first in this list too, for the 15
///   mapped reciters (العجمي unchanged) — the pins below were
///   updated to the new order; their substance is untouched.
/// No real HTTP is made except the one live test at the bottom,
/// which skips gracefully when the network is unavailable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  final husary = reciters.firstWhere((r) => r.name == 'محمود الحصري');
  final minshawi =
      reciters.firstWhere((r) => r.name == 'محمد صديق المنشاوي');

  group('altAyahUrls URL pins — all 16 reciters (v13.12)', () {
    test('every reciter: 2 hosts, pinned for 2:255 and 7:1', () {
      // (everyayah folder, primary 2:255, secondary 2:255).
      // Primary = the first host in the task's exact orders;
      // every primary was re-verified 2026-11-18 by SHA256 vs
      // the everyayah reference, built by the app's own URL
      // builder (16/16 identical). Secondaries return 200 with
      // the report's sizes (re-encodes where the report says so).
      final expected = <String, (String, String)>{
        'Husary_64kbps': (
          'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/002255.mp3',
          'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/002255.mp3',
        ),
        'Alafasy_64kbps': (
          'https://huggingface.co/datasets/maqra-project/mishari-alafasy-64kbps/resolve/main/002255.mp3',
          'https://verses.quran.com/Alafasy/mp3/002255.mp3',
        ),
        'Minshawy_Mujawwad_64kbps': (
          'https://huggingface.co/datasets/maqra-project/mohamed-siddiq-al-minshawi-mujawwad-64kbps/resolve/main/002255.mp3',
          'https://alfurqan.online/api/v1/audio/minshawy-mujawwad/surah/2/ayah/255',
        ),
        'Abdul_Basit_Murattal_64kbps': (
          'https://mirrors.quranicaudio.com/everyayah/Abdul_Basit_Murattal_64kbps/002255.mp3',
          'https://huggingface.co/datasets/maqra-project/abdul-basit-murattal-64kbps/resolve/main/002255.mp3',
        ),
        'Maher_AlMuaiqly_64kbps': (
          'https://mirrors.quranicaudio.com/everyayah/Maher_AlMuaiqly_64kbps/002255.mp3',
          'https://huggingface.co/datasets/maqra-project/maher-al-muaiqly-64kbps/resolve/main/002255.mp3',
        ),
        'Hudhaify_64kbps': (
          'https://huggingface.co/datasets/maqra-project/ali-al-hudhaifi-64kbps/resolve/main/002255.mp3',
          'https://mirrors.quranicaudio.com/everyayah/Hudhaify_128kbps/002255.mp3',
        ),
        'Abu_Bakr_Ash-Shaatree_64kbps': (
          'https://huggingface.co/datasets/maqra-project/abu-bakr-ash-shatri-64kbps/resolve/main/002255.mp3',
          'https://verses.quran.com/Shatri/mp3/002255.mp3',
        ),
        'Ayman_Sowaid_64kbps': (
          'https://mirrors.quranicaudio.com/everyayah/Ayman_Sowaid_64kbps/002255.mp3',
          'https://huggingface.co/datasets/maqra-project/ayman-swaid-64kbps/resolve/main/002255.mp3',
        ),
        'Saood_ash-Shuraym_64kbps': (
          'https://huggingface.co/datasets/maqra-project/saud-ash-shuraim-64kbps/resolve/main/002255.mp3',
          'https://verses.quran.com/Shuraym/mp3/002255.mp3',
        ),
        'Abdurrahmaan_As-Sudais_64kbps': (
          'https://huggingface.co/datasets/maqra-project/abdurrahman-as-sudais-64kbps/resolve/main/002255.mp3',
          'https://verses.quran.com/Sudais/mp3/002255.mp3',
        ),
        'Hani_Rifai_64kbps': (
          'https://huggingface.co/datasets/maqra-project/hani-ar-rifai-64kbps/resolve/main/002255.mp3',
          'https://verses.quran.com/Rifai/mp3/002255.mp3',
        ),
        'Ibrahim_Akhdar_32kbps': (
          'https://huggingface.co/datasets/maqra-project/ibrahim-al-akhdar-32kbps/resolve/main/002255.mp3',
          'https://alfurqan.online/api/v1/audio/ibrahim-akhdar/surah/2/ayah/255',
        ),
        'khalefa_al_tunaiji_64kbps': (
          'https://verses.quran.com/Tunaiji/mp3/002255.mp3',
          'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/002255.mp3',
        ),
        'Mohammad_al_Tablaway_64kbps': (
          'https://huggingface.co/datasets/maqra-project/mohammad-al-tablawi-64kbps/resolve/main/002255.mp3',
          'https://mirrors.quranicaudio.com/everyayah/Mohammad_al_Tablaway_128kbps/002255.mp3',
        ),
        'Yasser_Ad-Dussary_128kbps': (
          'https://mirrors.quranicaudio.com/everyayah/Yasser_Ad-Dussary_128kbps/002255.mp3',
          'https://huggingface.co/datasets/maqra-project/yasser-ad-dossari-128kbps/resolve/main/002255.mp3',
        ),
        'ahmed_ibn_ali_al_ajamy_128kbps': (
          'https://huggingface.co/datasets/maqra-project/ahmed-al-ajmi-128kbps/resolve/main/002255.mp3',
          'https://alfurqan.online/api/v1/audio/ahmed-al-ajamy/surah/2/ayah/255',
        ),
      };
      expect(reciters.length, 16);
      for (final reciter in reciters) {
        final urls = altAyahUrls(reciter, 2, 255);
        expect(urls.length, 2, reason: reciter.name);
        final (primary, secondary) = expected[reciter.everyayah]!;
        expect(urls[0], primary, reason: reciter.name);
        expect(urls[1], secondary, reason: reciter.name);
        // 7:1 pins the same two hosts with the other file name —
        // the pattern, not just one ayah, is what the player
        // relies on.
        final urls71 = altAyahUrls(reciter, 7, 1);
        expect(urls71[0], primary.replaceAll('002255', '007001'),
            reason: '${reciter.name} 7:1 primary');
        expect(urls71[1],
            secondary.replaceAll('002255', '007001').replaceAll(
                '/surah/2/ayah/255', '/surah/7/ayah/1'),
            reason: '${reciter.name} 7:1 secondary');
      }
      // Al Furqan uses unpadded surah/ayah numbers.
      expect(alFurqanAyahUrl('ibrahim-akhdar', 2, 255),
          'https://alfurqan.online/api/v1/audio/ibrahim-akhdar/surah/2/ayah/255');
      expect(alFurqanAyahUrl('ahmed-al-ajamy', 112, 2),
          'https://alfurqan.online/api/v1/audio/ahmed-al-ajamy/surah/112/ayah/2');
    });
  });

  group('cacheAyahFile fallback order — all 16 (v13.12)', () {
    late Directory tempDir;

    Future<AudioDownloadService> makeService(
        http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v1312-all');
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
      AudioDownloadService.stallTimeout = const Duration(seconds: 30);
      AudioDownloadService.retryBackoff = const Duration(seconds: 2);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Minshawi: no islamic.network step, Maqra then Al Furqan',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'huggingface.co') {
          return http.Response.bytes(fakeMp3Bytes(fill: 9), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(minshawi, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 9));
      expect(requested, [
        'https://resources.surahpedia.com/Minshawy_Mujawwad/002255.mp3',
        'http://www.everyayah.com/data/Minshawy_Mujawwad_64kbps/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/mohamed-siddiq-al-minshawi-mujawwad-64kbps/resolve/main/002255.mp3',
      ]);
      // The murattal-under-a-mujawwad-name edition is never
      // requested, and neither is the bare file (Maqra served it).
      expect(requested.any((u) => u.contains('islamic.network')),
          isFalse);
      expect(requested.any((u) => u.contains('alfurqan.online')),
          isFalse);
    });

    test('Minshawi: Maqra fails, Al Furqan serves it', () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com' ||
            request.url.host == 'huggingface.co') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'alfurqan.online') {
          return http.Response.bytes(fakeMp3Bytes(fill: 4), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(minshawi, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 4));
      expect(requested, [
        'https://resources.surahpedia.com/Minshawy_Mujawwad/002255.mp3',
        'http://www.everyayah.com/data/Minshawy_Mujawwad_64kbps/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/mohamed-siddiq-al-minshawi-mujawwad-64kbps/resolve/main/002255.mp3',
        'https://alfurqan.online/api/v1/audio/minshawy-mujawwad/surah/2/ayah/255',
      ]);
    });

    test('Husary: full chain order, no ZIP in the playback path',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'everyayah.com') {
          return http.Response.bytes(fakeMp3Bytes(fill: 2), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(husary, 112, 2);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), fakeMp3Bytes(fill: 2));
      expect(requested, [
        'https://resources.surahpedia.com/Husary/112002.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/112002.mp3',
        'https://cdn.islamic.network/quran/audio/64/ar.husary/6223.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/112002.mp3',
        'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/112002.mp3',
        'https://everyayah.com/data/Husary_64kbps/112002.mp3',
      ]);
      // v13.12 (user's correction): the whole-surah ZIP is NOT a
      // playback fallback — the chain ends at the bare file.
      expect(requested.any((u) => u.contains('/zips/')), isFalse);
    });
  });

  group('preloadAyahs — retry pass, no ZIP (v13.12)', () {
    late Directory tempDir;

    Future<AudioDownloadService> makeService(
        http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v1312-pre');
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
      AudioDownloadService.stallTimeout = const Duration(seconds: 30);
      AudioDownloadService.retryBackoff = const Duration(seconds: 2);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('page 2: first pass fails, retry pass fills all 5 ayahs',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final counts = <String, int>{};
      final service = await makeService(MockClient((request) async {
        final url = request.url.toString();
        requested.add(url);
        counts[url] = (counts[url] ?? 0) + 1;
        // The www file 404s on its FIRST request (transient
        // failure) and serves on the SECOND — every other host
        // 404s always, so only the retry pass can fill the page.
        if (request.url.host == 'www.everyayah.com' &&
            counts[url] == 2) {
          final name = request.url.pathSegments.last;
          final ayah = int.parse(name.substring(3, 6));
          return http.Response.bytes(fakeMp3Bytes(fill: ayah), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final pageAyahs = ayahsOfPages(2, 2);
      expect(pageAyahs.length, 5, reason: 'Baqarah 1–5');

      final ok = await service.preloadAyahs(husary, pageAyahs);

      expect(ok, isTrue);
      // No whole-surah ZIP anywhere in the playback path.
      expect(requested.any((u) => u.contains('/zips/')), isFalse);
      // Each ayah's www file was requested exactly twice: once
      // in the fast path, once in the retry pass.
      for (final (s, a) in pageAyahs) {
        final url =
            'http://www.everyayah.com/data/Husary_64kbps/${ayahFileName(s, a)}.mp3';
        expect(counts[url], 2, reason: 'ayah $s:$a retried once');
        final cached = service.localAyahFile(husary, s, a);
        expect(cached, isNotNull, reason: 'ayah $s:$a cached');
        expect(await cached!.readAsBytes(), fakeMp3Bytes(fill: a));
      }
    });

    test('all hosts fail on both passes: preload returns false, '
        'nothing cached', () async {
      AudioDownloadService.fetchAttempts = 1;
      final service = await makeService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final ok =
          await service.preloadAyahs(husary, ayahsOfPages(2, 2));

      expect(ok, isFalse);
      for (final (s, a) in ayahsOfPages(2, 2)) {
        expect(service.localAyahFile(husary, s, a), isNull);
      }
    });
  });

  group('playPages with the retry pass (v13.12)', () {
    late Directory tempDir;

    Future<AudioDownloadService> makeService(
        http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v1312-play');
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
      AudioDownloadService.stallTimeout = const Duration(seconds: 30);
      AudioDownloadService.retryBackoff = const Duration(seconds: 2);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('page 2: first pass fails, retry pass fills it, page plays',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final counts = <String, int>{};
      final service = await makeService(MockClient((request) async {
        final url = request.url.toString();
        requested.add(url);
        counts[url] = (counts[url] ?? 0) + 1;
        // The www file 404s on its FIRST request (transient
        // failure) and serves on the SECOND — every other host
        // 404s always, so only the retry pass can fill the page.
        if (request.url.host == 'www.everyayah.com' &&
            counts[url] == 2) {
          final name = request.url.pathSegments.last;
          final ayah = int.parse(name.substring(3, 6));
          return http.Response.bytes(fakeMp3Bytes(fill: ayah), 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      final loadsBefore = fake.loadCount;
      await controller.playPages(2, 2);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(controller.currentAyah, (2, 1));
      expect(fake.loadCount, loadsBefore + 1);
      expect(fake.loadUris.last.endsWith('002001.mp3'), isTrue);
      expect(fake.loadUris.last.startsWith('http'), isFalse);
      // No whole-surah ZIP anywhere in the playback path.
      expect(requested.any((u) => u.contains('/zips/')), isFalse);
    });

    test('page 2: all hosts fail on both passes — preload fails, '
        'page still plays via the native stream (v13.14)', () async {
      AudioDownloadService.fetchAttempts = 1;
      final service = await makeService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري

      final loadsBefore = fake.loadCount;
      await controller.playPages(2, 2);

      // v13.14: the failed preload no longer gates playback — the
      // page falls through to _playCurrent, which streams the
      // first ayah through the native player (every Dart download
      // failed, so nothing is cached).
      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(controller.currentAyah, (2, 1));
      expect(fake.loadCount, loadsBefore + 1);
      expect(fake.loadUris.last,
          'https://resources.surahpedia.com/Husary/002001.mp3');
    });
  });

  group('ayahStreamUrlsInOrder — single-ayah stream (v13.12)', () {
    test('order pins: SurahPedia, www, alternates, islamic.network, '
        'bare', () {
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
      final tunaiji =
          reciters.firstWhere((r) => r.name == 'خليفة الطنيجي');
      expect(ayahStreamUrlsInOrder(tunaiji, 7, 1), [
        'https://resources.surahpedia.com/Khalefa_Al-Tunaiji/007001.mp3',
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/007001.mp3',
        'https://verses.quran.com/Tunaiji/mp3/007001.mp3',
        'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/007001.mp3',
        'https://everyayah.com/data/khalefa_al_tunaiji_64kbps/007001.mp3',
      ]);
      // Every mapped reciter streams from SurahPedia first, then
      // www + 2 alternates + bare (5 hosts), plus islamic.network
      // when mapped (6). العجمي has no SurahPedia folder: www
      // first, 5 hosts (v13.12 order unchanged).
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

  group('playAyah stream fallback (v13.12)', () {
    late Directory tempDir;

    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.resetCounts();
    });

    Future<AudioDownloadService> makeService(
        http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v1312-stream');
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
      AudioDownloadService.stallTimeout = const Duration(seconds: 30);
      AudioDownloadService.retryBackoff = const Duration(seconds: 2);
      fake.failLoadSubstrings.clear();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('cache fails: streams SurahPedia, www, then alts in order',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      // The cache fails on every host (all 404s).
      final service = await makeService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      // SurahPedia + www + mirror loads fail at the fake platform;
      // Maqra plays.
      fake.failLoadSubstrings.addAll([
        'resources.surahpedia.com',
        'www.everyayah.com',
        'mirrors.quranicaudio.com',
      ]);

      await controller.playAyah(2, 33);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002033.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002033.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/002033.mp3',
        'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/002033.mp3',
      ]);
    });

    test('cache fails and every stream host fails: error, no sound',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final service = await makeService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final controller = AudioPlayerController(downloads: service);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري
      fake.failLoadSubstrings.addAll([
        'surahpedia',
        'everyayah',
        'mirrors.quranicaudio.com',
        'huggingface.co',
        'islamic.network',
      ]);

      final loadsBefore = fake.loadCount;
      await controller.playAyah(2, 33);

      expect(controller.lastError, isNotNull);
      expect(controller.isPlaying, isFalse);
      // All 6 hosts were attempted, none played.
      expect(fake.loadCount, loadsBefore + 6);
      expect(fake.loadUris.sublist(fake.loadUris.length - 6), [
        'https://resources.surahpedia.com/Husary/002033.mp3',
        'http://www.everyayah.com/data/Husary_64kbps/002033.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/002033.mp3',
        'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/002033.mp3',
        'https://cdn.islamic.network/quran/audio/64/ar.husary/40.mp3',
        'https://everyayah.com/data/Husary_64kbps/002033.mp3',
      ]);
    });
  });

  group('live primary-host check (v13.12)', () {
    test('each primary URL answers 200 for 2:255 (skips offline)',
        () async {
      // One real GET per primary host, built by the app's own
      // URL builder — not a copy of the reports' strings. A
      // network failure skips the test instead of failing the
      // suite (the hosts were already verified by content
      // 2026-11-18 — SHA256 vs everyayah, 16/16 identical; this
      // only re-checks they still answer).
      for (final reciter in reciters) {
        final url = altAyahUrls(reciter, 2, 255).first;
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
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
