import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/quran_audio.dart';

/// v13.10 — prefetch/foreground race (user report 2026-11-18):
/// page 3, هاني الرفاعي, ayah 6 played, ayah 7 failed with
/// "تعذّر تحميل الصوت". While ayah 6 plays the player prefetches
/// ayah 7 in the background; when ayah 6 ends the foreground load
/// starts the SAME file again. Two concurrent [_fetchOnce] calls
/// wrote the same tmp file (same URL, same tmp path) and corrupted
/// it. The fix: [_fetchToFile] shares one in-flight future per
/// target file path — a second caller awaits the first instead of
/// starting a duplicate download.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AudioDownloadService service;

  Future<AudioDownloadService> makeService({
    required http.Client client,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('audio-race-test');
    final s = AudioDownloadService(
      client: client,
      storageDir: tempDir,
      prefs: await SharedPreferences.getInstance(),
    );
    await s.init();
    return s;
  }

  tearDown(() async {
    service.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// A slow server: the body arrives in chunks with gaps, so two
  /// concurrent downloads of the same file genuinely overlap (a
  /// MockClient that answers instantly would let the first finish
  /// before the second starts and hide the race).
  test(
      'concurrent prefetch + foreground fetch of the same ayah downloads once',
      () async {
    // v13.16: the served bytes must be a VALID mp3 (>= 1 KB + ID3
    // header) or the cache validation rejects them as poisoned.
    final served = List<int>.generate(8000, (i) => i % 251);
    served[0] = 0x49; // 'I'
    served[1] = 0x44; // 'D'
    served[2] = 0x33; // '3'
    final client = SlowClient(served);
    service = await makeService(client: client);
    final rifai =
        reciters.firstWhere((r) => r.name == 'هاني الرفاعي');

    // The prefetch (no cancel check, like the player's background
    // prefetch) and the foreground load (with a cancel check, like
    // _playCurrent) start together while the download is still
    // running — exactly the user's page-3 report.
    final results = await Future.wait([
      service.cacheAyahFile(rifai, 2, 7),
      service.cacheAyahFile(rifai, 2, 7, isCancelled: () => false),
    ]);

    // One download, not two racing writes to the same tmp file.
    expect(client.requests, 1);
    expect(results[0], isNotNull);
    expect(results[1], isNotNull);
    expect(results[0]!.path, results[1]!.path);
    // The cached file is the served bytes exactly — no interleaved
    // garbage from two writers.
    expect(await results[0]!.readAsBytes(), served);
    expect(service.localAyahFile(rifai, 2, 7), isNotNull);
  });
}

/// A slow server: the body arrives in chunks with gaps, so two
/// concurrent downloads of the same file genuinely overlap (a
/// MockClient that answers instantly would let the first finish
/// before the second starts and hide the race).
class SlowClient extends http.BaseClient {
  SlowClient(this.bytes);

  final List<int> bytes;
  var requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (!request.url.path.endsWith('002007.mp3')) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    final chunkSize = (bytes.length / 4).ceil();
    final chunks = <List<int>>[];
    for (var i = 0; i < bytes.length; i += chunkSize) {
      chunks.add(
        bytes.sublist(i, math.min(i + chunkSize, bytes.length)),
      );
    }
    final stream =
        Stream<List<int>>.fromIterable(chunks).asyncMap((chunk) async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      return chunk;
    });
    return http.StreamedResponse(stream, 200,
        contentLength: bytes.length);
  }
}
