import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/quran_audio.dart';

/// v12 reciter downloads: per-surah + full-Mushaf background
/// downloads with file-level resume, offline playback files on disk.
///
/// The downloads use the SAME everyayah URLs the player streams.
/// MockClient stands in for the network; no real HTTP is made.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AudioDownloadService service;
  var serviceCreated = false;

  MockClient okClient(List<String> requested) {
    return MockClient((request) async {
      requested.add(request.url.toString());
      return http.Response.bytes([1, 2, 3, 4], 200);
    });
  }

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
    service = await makeService(client: okClient(requested));
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
    // The exact everyayah URLs the player streams.
    expect(
      requested,
      [for (var a = 1; a <= 4; a++) everyayahUrl(husary, 112, a)],
    );
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
    service = await makeService(client: okClient(requested));
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
    expect(requested, hasLength(3));
    expect(requested, isNot(contains(everyayahUrl(husary, 112, 1))));
    expect(
        requested, contains(everyayahUrl(husary, 112, 4)));
    // The pre-existing file was kept untouched.
    expect(
      await File('${dir.path}/112001.mp3').readAsBytes(),
      [9, 9],
    );
  });

  test('failure pauses the job; retry resumes from the next file',
      () async {
    final requested = <String>[];
    var failOnce = true;
    final flaky = MockClient((request) async {
      requested.add(request.url.toString());
      if (failOnce && request.url.path.endsWith('112002.mp3')) {
        failOnce = false;
        return http.Response('boom', 500);
      }
      return http.Response.bytes([7], 200);
    });
    service = await makeService(client: flaky);

    expect(await service.downloadSurahs(0, [112]), isTrue);
    await waitForIdle(service);

    expect(service.activeJob!.status, DownloadStatus.failed);
    expect(service.activeJob!.error, isNotNull);
    expect(service.isSurahDownloaded(0, 112), isFalse);
    // 112001 completed before the failure and stays.
    expect(service.localAyahFile(reciters[0], 112, 1), isNotNull);

    // Retry: resumes after 112001, does not re-fetch it.
    requested.clear();
    expect(await service.downloadSurahs(0, [112]), isTrue);
    await waitForIdle(service);
    expect(service.activeJob!.status, DownloadStatus.done);
    expect(service.isSurahDownloaded(0, 112), isTrue);
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
    // Still running (6 files x 150ms): the second start is refused.
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
