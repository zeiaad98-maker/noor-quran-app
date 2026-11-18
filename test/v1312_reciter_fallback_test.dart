import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/quran_audio.dart';

/// v13.12 — alternate per-ayah hosts for the 3 reciters
/// islamic.network does not carry (Tunaiji, Tablawi, Dosari),
/// content-verified byte-identical vs everyayah 2026-11-18
/// (full report: ~/workspace/noor-quran-v1/reciter-alt-servers/
/// REPORT.md). The alternates slot into [AudioDownloadService.
/// cacheAyahFile] after the www per-ayah file and the
/// islamic.network attempt, before the bare per-ayah file — the
/// same position islamic.network occupies for the 12. The
/// radical fix extends the same mechanism to ALL 16 reciters —
/// see test/v1312_all_reciters_fallback_test.dart for the full
/// pins. No real HTTP is made in the chain tests (MockClient);
/// the one live test at the bottom skips gracefully when the
/// network is unavailable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tunaiji =
      reciters.firstWhere((r) => r.name == 'خليفة الطنيجي');
  final tablawi =
      reciters.firstWhere((r) => r.name == 'محمد الطبلاوي');
  final dossari =
      reciters.firstWhere((r) => r.name == 'ياسر الدوسري');

  group('altAyahUrls URL patterns (v13.12)', () {
    test('Tunaiji: verses.quran.com first, Maqra/HF second', () {
      // 2:255 = 002255 (Ayat al-Kursi, the long ayah the report
      // verified byte-identical on both hosts).
      expect(altAyahUrls(tunaiji, 2, 255), [
        'https://verses.quran.com/Tunaiji/mp3/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/002255.mp3',
      ]);
      expect(altAyahUrls(tunaiji, 7, 1), [
        'https://verses.quran.com/Tunaiji/mp3/007001.mp3',
        'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/007001.mp3',
      ]);
    });

    test('Tablawi: Maqra/HF first, mirror 128k second', () {
      // Spelling is mohammad, not muhammad (muhammad-* 401s).
      expect(altAyahUrls(tablawi, 2, 255), [
        'https://huggingface.co/datasets/maqra-project/mohammad-al-tablawi-64kbps/resolve/main/002255.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Mohammad_al_Tablaway_128kbps/002255.mp3',
      ]);
      expect(altAyahUrls(tablawi, 7, 1), [
        'https://huggingface.co/datasets/maqra-project/mohammad-al-tablawi-64kbps/resolve/main/007001.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Mohammad_al_Tablaway_128kbps/007001.mp3',
      ]);
    });

    test('Dosari: mirror first, Maqra/HF second', () {
      // Spelling is ad-dossari (al-dosari / ad-dussary 401).
      expect(altAyahUrls(dossari, 2, 255), [
        'https://mirrors.quranicaudio.com/everyayah/Yasser_Ad-Dussary_128kbps/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/yasser-ad-dossari-128kbps/resolve/main/002255.mp3',
      ]);
      expect(altAyahUrls(dossari, 7, 1), [
        'https://mirrors.quranicaudio.com/everyayah/Yasser_Ad-Dussary_128kbps/007001.mp3',
        'https://huggingface.co/datasets/maqra-project/yasser-ad-dossari-128kbps/resolve/main/007001.mp3',
      ]);
    });

    test('every reciter has exactly two alternate hosts (v13.12)', () {
      // All 16 reciters have 2 verified alternate hosts now
      // (REPORT.md + REPORT-group-a.md + REPORT-group-b.md) —
      // the v13.12 wiring covered only Tunaiji/Tablawi/Dosari;
      // the radical fix extends the same mechanism to all 16.
      for (final reciter in reciters) {
        expect(altAyahUrls(reciter, 2, 255).length, 2,
            reason: reciter.name);
      }
      expect(reciters.length, 16);
      // المنشاوي: he HAS alternate hosts (genuine mujawwad —
      // Maqra + Al Furqan) but still NO islamic.network step:
      // the edition there is murattal under a mujawwad name.
      final minshawi = reciters.firstWhere(
          (r) => r.name == 'محمد صديق المنشاوي');
      expect(altAyahUrls(minshawi, 2, 255).length, 2);
      expect(islamicNetworkUrl(minshawi, 2, 255), isNull);
    });
  });

  group('cacheAyahFile alternate-host chain (v13.12)', () {
    late Directory tempDir;

    Future<AudioDownloadService> makeService(
        http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v1312-alt');
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

    test('Tunaiji: www fails, primary alt serves the file', () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'verses.quran.com') {
          return http.Response.bytes([2, 2], 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(tunaiji, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [2, 2]);
      expect(requested, [
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/002255.mp3',
        'https://verses.quran.com/Tunaiji/mp3/002255.mp3',
      ]);
    });

    test('Tunaiji: primary alt fails, second alt serves it', () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'verses.quran.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'huggingface.co') {
          return http.Response.bytes([3, 3], 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(tunaiji, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [3, 3]);
      expect(requested, [
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/002255.mp3',
        'https://verses.quran.com/Tunaiji/mp3/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/002255.mp3',
      ]);
    });

    test('Tablawi: both alts fail, bare per-ayah serves it (no ZIP)',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'huggingface.co' ||
            request.url.host == 'mirrors.quranicaudio.com') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([5, 5], 200);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(tablawi, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [5, 5]);
      expect(requested, [
        'http://www.everyayah.com/data/Mohammad_al_Tablaway_64kbps/002255.mp3',
        'https://huggingface.co/datasets/maqra-project/mohammad-al-tablawi-64kbps/resolve/main/002255.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Mohammad_al_Tablaway_128kbps/002255.mp3',
        'https://everyayah.com/data/Mohammad_al_Tablaway_64kbps/002255.mp3',
      ]);
      expect(requested.any((u) => u.contains('/zips/')), isFalse,
          reason: 'the ZIP must not run before the small bare file');
    });

    test('Dosari: primary alt serves it, bare never requested',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'mirrors.quranicaudio.com') {
          return http.Response.bytes([8, 8], 200);
        }
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(dossari, 2, 255);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [8, 8]);
      expect(requested, [
        'http://www.everyayah.com/data/Yasser_Ad-Dussary_128kbps/002255.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Yasser_Ad-Dussary_128kbps/002255.mp3',
      ]);
    });

    test('Husary: mirror then Maqra then bare (v13.12, all 16)',
        () async {
      AudioDownloadService.fetchAttempts = 1;
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.host == 'www.everyayah.com') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'cdn.islamic.network') {
          return http.Response.bytes([], 404);
        }
        if (request.url.host == 'mirrors.quranicaudio.com' ||
            request.url.host == 'huggingface.co') {
          return http.Response.bytes([], 404);
        }
        return http.Response.bytes([7, 7], 200);
      }));
      addTearDown(service.dispose);

      final file = await service.cacheAyahFile(reciters[0], 112, 2);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [7, 7]);
      expect(requested, [
        'http://www.everyayah.com/data/Husary_64kbps/112002.mp3',
        'https://cdn.islamic.network/quran/audio/64/ar.husary/6223.mp3',
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/112002.mp3',
        'https://huggingface.co/datasets/maqra-project/mahmoud-al-husary-murattal-64kbps/resolve/main/112002.mp3',
        'https://everyayah.com/data/Husary_64kbps/112002.mp3',
      ]);
    });
  });

  group('live primary-host check (v13.12)', () {
    test('each primary URL answers 200 for 2:255 (skips offline)',
        () async {
      // One real GET per primary host, built by the app's own
      // URL builder — not a copy of the report's strings. A
      // network failure skips the test instead of failing the
      // suite (the hosts were already verified by content
      // 2026-11-18; this only re-checks they still answer).
      for (final reciter in [tunaiji, tablawi, dossari]) {
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
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
