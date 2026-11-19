import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/quran_audio.dart';

import 'fake_just_audio.dart';

/// v13.14: page-scope playback must NOT die at the preload gate.
///
/// The user's phone fails EVERY Dart http download (all hosts, all
/// versions), so v13.13's playPages — preload, else error — never
/// played a page at all, without ever trying the native player.
/// Now a failed preload falls through to _playCurrent(), which
/// streams each ayah through the native player (ExoPlayer), the
/// path SurahApp/Wahy use. This test proves it with a download
/// service that 404s every URL and a fake native player that loads
/// stream URLs fine: the page PLAYS (first ayah via the SurahPedia
/// stream URL) instead of reporting the error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  group('page fallback to native streaming (v13.14)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.resetCounts();
    });

    test('preload fails on every host: the page still plays via '
        'the native stream (Husary page 2)', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir =
          await Directory.systemTemp.createTemp('v1314-page');
      addTearDown(() => tempDir.delete(recursive: true));
      final downloads = AudioDownloadService(
        client: MockClient((request) async {
          return http.Response.bytes([], 404);
        }),
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await downloads.init();
      addTearDown(downloads.dispose);
      final controller = AudioPlayerController(downloads: downloads);
      addTearDown(controller.dispose);
      controller.reciterIndex = 0; // الحصري — the user's failing case

      await controller.playPages(2, 2);

      expect(controller.lastError, isNull);
      expect(fake.player.playing, isTrue);
      // The first ayah streams from SurahPedia first (v13.13
      // chain order) — the Dart downloads all failed, so no local
      // file exists and the native player is what plays.
      expect(fake.loadUris, [
        'https://resources.surahpedia.com/Husary/002001.mp3',
      ]);
      expect(downloads.localAyahFile(reciters[0], 2, 1), isNull);
      // Let the next-ayah prefetch (kicked off unawaited by
      // _playCurrent) settle before teardown deletes the temp dir.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });
}
