import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'zip_fixture.dart';

/// v12 reciter downloads: per-surah + full-Mushaf background
/// downloads with surah-level resume, offline playback files on disk.
///
/// v13.5: the downloads fetch one per-surah ZIP
/// (everyayahSurahZipUrl — Wahy's exact method) and unzip it into
/// the per-ayah layout the player streams. MockClient stands in for
/// the network; no real HTTP is made. Real ZIPs are built in-memory
/// with test/zip_fixture.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AudioDownloadService service;
  var serviceCreated = false;

  Future<AudioDownloadService> makeService({
    required http.Client client,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('audio-dl-test');
    final s = AudioDownloadService(
      client: client,
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
    );
    await s.init();
    serviceCreated = true;
    return s;
  }

  /// Wait (real async) until the service has no running job.
  Future<void> waitForIdle(AudioDownloadService s) async {
    for (var i = 0; i < 200; i++) {
      if (!s.isDownloading) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('download did not finish in time');
  }

  tearDown(() async {
    // The counting test creates no service/temp dir.
    if (!serviceCreated) return;
    service.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
    serviceCreated = false;
  });

  test('download one surah: files on disk, manifest, مثبّت', () async {
    final requested = <String>[];
    // v13.5: one surah ZIP (stored, like the real everyayah ZIPs)
    // instead of one request per ayah.
    final zipBytes = buildSurahZip(
      {for (var a = 1; a <= 4; a++) '11200$a.mp3': [1, 2, 3, 4]},
      stored: true,
    );
    service = await makeService(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes(zipBytes, 200);
        }
        return http.Response.bytes([1, 2, 3, 4], 200);
      }),
    );
    final husary = reciters[0];

    expect(await service.downloadSurahs(0, [112]), isTrue);
    await waitForIdle(service);

    final job = service.activeJob!;
    expect(job.status, DownloadStatus.done);
    expect(job.totalFiles, 4); // Al-Ikhlas has 4 ayahs
    expect(job.doneFiles, 4);
    expect(job.progress, 1.0);
    expect(service.isSurahDownloaded(0, 112), isTrue);
    expect(service.downloadedSurahsOf(0), contains(112));
    // Exactly one request: the surah ZIP (the player streams the
    // per-ayah URL only as a fallback).
    expect(requested, [everyayahSurahZipUrl(husary, 112)]);
    for (var a = 1; a <= 4; a++) {
      final file = service.localAyahFile(husary, 112, a);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [1, 2, 3, 4]);
    }
    // Not downloaded: no local file.
    expect(service.localAyahFile(husary, 112, 5), isNull);
    expect(service.localAyahFile(husary, 113, 1), isNull);
  });

  test('resume: completed files are NOT re-requested', () async {
    final requested = <String>[];
    // v13.5: the job downloads the surah ZIP once and extracts only
    // the missing ayahs — the pre-existing file is left untouched.
    final zipBytes = buildSurahZip(
      {for (var a = 1; a <= 4; a++) '11200$a.mp3': [1, 2, 3, 4]},
      stored: true,
    );
    service = await makeService(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.endsWith('.zip')) {
          return http.Response.bytes(zipBytes, 200);
        }
        return http.Response.bytes([1, 2, 3, 4], 200);
      }),
    );
    final husary = reciters[0];
    final dir = Directory('${tempDir.path}/${husary.everyayah}');
    await dir.create(recursive: true);
    // Pretend 112001 was already downloaded in an earlier run.
    await File('${dir.path}/112001.mp3').writeAsBytes([9, 9]);
    await File('${dir.path}/manifest.json')
        .writeAsString(jsonEncode(['112001']));

    expect(await service.downloadSurahs(0, [112]), isTrue);
    await waitForIdle(service);

    expect(service.activeJob!.status, DownloadStatus.done);
    // Exactly one request (the ZIP); no per-ayah request at all,
    // and 112001 was never re-requested.
    expect(requested, [everyayahSurahZipUrl(husary, 112)]);
    expect(
        requested, isNot(contains(everyayahUrl(husary, 112, 1))));
    // The pre-existing file was kept untouched (not overwritten by
    // the ZIP's copy).
    expect(
      await File('${dir.path}/112001.mp3').readAsBytes(),
      [9, 9],
    );
    // The missing ayahs came from the ZIP.
    for (var a = 2; a <= 4; a++) {
      expect(
        await File('${dir.path}/11200$a.mp3').readAsBytes(),
        [1, 2, 3, 4],
      );
    }
  });

  test('failure pauses the job; retry resumes from the next file',
      () async {
    final requested = <String>[];
    // v13.5 (ZIP jobs): the failure that pauses the job is a failed
    // surah-ZIP download — fail the ZIP in phase 1, allow it for
    // the retry run. (v13.3, FIX A: _fetchToFile retries transient
    // failures, so a failure that happens ONCE is absorbed and the
    // job completes — the job pauses only on a HARD failure.)
    final zipBytes = buildSurahZip(
      {for (var a = 1; a <= 4; a++) '11200$a.mp3': [7]},
      stored: true,
    );
    var failZip = true;
    final flaky = MockClient((request) async {
      requested.add(request.url.toString());
      if (failZip && request.url.path.endsWith('112.zip')) {
        return http.Response('boom', 500);
      }
      if (request.url.path.endsWith('.zip')) {
        return http.Response.bytes(zipBytes, 200);
      }
      return http.Response.bytes([7], 200);
    });
    service = await makeService(client: flaky);

    expect(await service.downloadSurahs(0, [112]), isTrue);
    await waitForIdle(service);

    expect(service.activeJob!.status, DownloadStatus.failed);
    expect(service.activeJob!.error, isNotNull);
    expect(service.isSurahDownloaded(0, 112), isFalse);
    // Nothing was extracted — the ZIP failed before extraction.
    expect(service.localAyahFile(reciters[0], 112, 1), isNull);

    // Retry: the ZIP downloads and the surah completes.
    failZip = false;
    requested.clear();
    expect(await service.downloadSurahs(0, [112]), isTrue);
    await waitForIdle(service);
    expect(service.activeJob!.status, DownloadStatus.done);
    expect(service.isSurahDownloaded(0, 112), isTrue);
    expect(requested, [everyayahSurahZipUrl(reciters[0], 112)]);
    expect(
        requested, isNot(contains(everyayahUrl(reciters[0], 112, 1))));
  });

  test('a second download while one runs is refused', () async {
    final slow = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return http.Response.bytes([1], 200);
    });
    service = await makeService(client: slow);

    expect(await service.downloadSurahs(0, [114]), isTrue);
    // Still running (one ZIP request x 150ms, plus the per-ayah
    // fallback the bad 1-byte ZIP triggers): the second start is
    // refused.
    expect(await service.downloadSurahs(1, [112]), isFalse);
    await waitForIdle(service);
    expect(service.isSurahDownloaded(0, 114), isTrue);
    // After it finishes, a new download is accepted.
    expect(await service.downloadSurahs(1, [112]), isTrue);
    await waitForIdle(service);
    expect(service.isSurahDownloaded(1, 112), isTrue);
  });

  test('full Mushaf counts 6,236 files (job total only)', () {
    // No download is started here: just the arithmetic the UI shows
    // before the job runs (114 surahs, 6,236 ayahs).
    var total = 0;
    for (var s = 1; s <= 114; s++) {
      total += quran.getVerseCount(s);
    }
    expect(total, 6236);
  });
}
