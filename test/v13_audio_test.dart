import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/widgets/noor_qcf_page.dart';

/// v13 audio (the user's top priority): pronunciation must be clear,
/// pure and complete — for the WORD and the AYAH.
///
/// * Default reciter: خليفة الطنيجي, with migration of the old
///   default (0 = الحصري).
/// * Cache-on-play: ayah and wbw files are downloaded once and played
///   from disk after that — no streaming stutter on a weak connection.
/// * Zoom: the Mushaf caps at 0.98 (see noor_qcf_page).
///
/// NOTE (v13.2): the segment subsystem (parseWordSegments,
/// paddedWordWindow) was DELETED — the word plays ONLY its wbw file,
/// never a cut from an ayah recording. The segment groups that lived
/// here are gone with it; the wbw tests are in v132_audio_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();


  group('resolveDefaultReciterIndex', () {
    test('absent or old default migrates to الطنيجي (12)', () {
      expect(resolveDefaultReciterIndex(null), 12);
      expect(resolveDefaultReciterIndex(0), 12);
      expect(reciters[12].name, 'خليفة الطنيجي');
      expect(reciters[12].everyayah, 'khalefa_al_tunaiji_64kbps');
    });

    test('a reciter the user chose himself is kept', () {
      expect(resolveDefaultReciterIndex(5), 5);
      expect(resolveDefaultReciterIndex(12), 12);
    });

    test('out-of-range values clamp to the list', () {
      expect(resolveDefaultReciterIndex(99), reciters.length - 1);
      expect(resolveDefaultReciterIndex(-3), 0);
    });
  });

  group('clampMushafZoom', () {
    test('anything above 0.98 clamps to 0.98', () {
      expect(clampMushafZoom(1.04), 0.98);
      expect(clampMushafZoom(1.08), 0.98);
      expect(clampMushafZoom(1.0), 0.98);
    });

    test('the allowed range 0.92-0.98 passes through', () {
      expect(clampMushafZoom(0.92), 0.92);
      expect(clampMushafZoom(0.96), 0.96);
      expect(clampMushafZoom(0.98), 0.98);
    });

    test('anything below 0.92 clamps to 0.92', () {
      expect(clampMushafZoom(0.5), 0.92);
    });
  });

  group('cache-on-play (AudioDownloadService)', () {
    Directory? tempDir;

    Future<AudioDownloadService> makeService(http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('audio-v13-test');
      final s = AudioDownloadService(
        client: client,
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await s.init();
      return s;
    }

    tearDown(() async {
      final dir = tempDir;
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
      tempDir = null;
    });

    test('cacheAyahFile downloads once, replays from disk', () async {
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([9, 8, 7, 6], 200);
      }));
      addTearDown(service.dispose);
      final tunaiji = reciters[12];

      final first = await service.cacheAyahFile(tunaiji, 2, 33);
      expect(first, isNotNull);
      expect(await first!.readAsBytes(), [9, 8, 7, 6]);
      expect(requested, [
        'https://everyayah.com/data/khalefa_al_tunaiji_64kbps/002033.mp3',
      ]);
      // The player sees the same file through the sync accessor.
      expect(service.localAyahFile(tunaiji, 2, 33)?.path, first.path);

      final second = await service.cacheAyahFile(tunaiji, 2, 33);
      expect(second?.path, first.path);
      expect(requested.length, 1, reason: 'no second download');
    });

    test('cacheAyahFile failure leaves no file and returns null', () async {
      final service = await makeService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));
      addTearDown(service.dispose);
      final file = await service.cacheAyahFile(reciters[12], 2, 33);
      expect(file, isNull);
      expect(service.localAyahFile(reciters[12], 2, 33), isNull);
      // No partial file on disk either.
      final dir = Directory('${tempDir!.path}/${reciters[12].everyayah}');
      expect(await dir.exists(), isFalse);
    });

    test('cacheWbwFile downloads once, replays from disk', () async {
      final requested = <String>[];
      final service = await makeService(MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([1, 2, 3], 200);
      }));
      addTearDown(service.dispose);

      final first = await service.cacheWbwFile(2, 33, 4);
      expect(first, isNotNull);
      expect(await first!.readAsBytes(), [1, 2, 3]);
      expect(requested, [
        'https://audio.qurancdn.com/wbw/002_033_004.mp3',
      ]);
      expect(service.localWbwFile(2, 33, 4)?.path, first.path);

      final second = await service.cacheWbwFile(2, 33, 4);
      expect(second?.path, first.path);
      expect(requested.length, 1, reason: 'no second download');
    });
  });
}
