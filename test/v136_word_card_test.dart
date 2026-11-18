import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/qiraat_data.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/data/word_meanings.dart';

import 'fake_just_audio.dart';

/// v13.6 step 2 — the Wahy-style word card: what the card is built on.
///
/// - Word-audio order: SurahPedia FIRST, then the Quran.com hosts.
/// - Qiraat: REAL variants from the bundled trim (no invented data);
///   the شعبة/حفص trap (same imam عاصم, different readings) is pinned.
/// - Controller: the card's new actions — repeatWord, playFromAyah
///   (استمرار), wordAutoPlay persistence.
///
/// The card's own layout and buttons are widget-tested in
/// test/word_card_test.dart; the gloss priority is pinned in
/// test/v136_glosses_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();

  group('wbwWordUrlsInOrder (v13.6: SurahPedia first)', () {
    test('returns [SurahPedia, qurancdn, legacy] for 4:4 word 12', () {
      expect(
        wbwWordUrlsInOrder(4, 4, 12),
        [
          'https://resources.surahpedia.com/Word_by-Word/4/004004012.mp3',
          'https://audio.qurancdn.com/wbw/004_004_012.mp3',
          'https://verses.quran.com/wbw/004_004_012.mp3',
        ],
      );
    });

    test('same order for another ayah (1:4 word 1)', () {
      final urls = wbwWordUrlsInOrder(1, 4, 1);
      expect(urls, hasLength(3));
      expect(urls.first, startsWith('https://resources.surahpedia.com/'));
      expect(urls[1], startsWith('https://audio.qurancdn.com/'));
      expect(urls[2], startsWith('https://verses.quran.com/'));
    });
  });

  group('QiraatData — real variants only', () {
    test('1:4 مَالِكِ: Hafs is the Mushaf reading; مَلِكِ is real',
        () async {
      final variants = await QiraatData.variantsForWord(1, 4, 0, 'مَالِكِ');
      expect(variants, hasLength(1));
      final v = variants.single;
      expect(v.word, 'مَـٰلِكِ');
      final hafs = v.readings.firstWhere((r) => r.hafs);
      expect(hafs.text, 'مَالِكِ');
      expect(hafs.readers, contains('عاصم'));
      final other = v.readings.firstWhere((r) => r.text == 'مَلِكِ');
      expect(other.hafs, isFalse);
      expect(other.readers, contains('ابن عامر'));
    });

    test('21:4 قَالَ vs قُلْ: شعبة and حفص differ (same imam عاصم)',
        () async {
      final variants = await QiraatData.variantsForWord(21, 4, 0, 'قَالَ');
      expect(variants, isNotEmpty);
      final readings =
          variants.expand((v) => v.readings).toList();
      final qala = readings.firstWhere((r) => r.text == 'قَالَ');
      expect(qala.hafs, isTrue);
      expect(qala.readers, contains('عاصم'));
      // The قُلْ reading is attributed to شعبة عن عاصم — NOT folded
      // into حفص, even though both are transmissions of عاصم.
      final qul = readings.firstWhere((r) => r.text == 'قُلۡ');
      expect(qul.hafs, isFalse);
      expect(qul.readers, contains('شعبة عن عاصم'));
    });

    test('102:6 has variants (two readings, one is the Mushaf one)',
        () async {
      final variants = await QiraatData.variantsForWord(102, 6, 0, 'لَتَرَوُنَّ');
      expect(variants, isNotEmpty);
      final readings = variants.expand((v) => v.readings).toList();
      expect(readings, hasLength(2));
      // Exactly one reading is the Mushaf's (Hafs); the other is a
      // real variant (ابن عامر / الكسائي) — never invented.
      expect(readings.where((r) => r.hafs), hasLength(1));
      final other = readings.firstWhere((r) => !r.hafs);
      expect(other.readers, contains('ابن عامر'));
    });

    test('no variants → empty, never invented', () async {
      expect(await QiraatData.variantsForWord(2, 2, 0, 'ذَٰلِكَ'), isEmpty);
      expect(await QiraatData.variantsForAyah(2, 2), isEmpty);
      // 1:4 word 2 (يَوْمِ) has no variant either.
      expect(await QiraatData.variantsForWord(1, 4, 1, 'يَوْمِ'), isEmpty);
    });
  });

  group('controller — card actions (fake platform)', () {
    setUp(() {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.resetCounts();
      SharedPreferences.setMockInitialValues({});
    });

    Future<AudioPlayerController> makeController() async {
      final tempDir = await Directory.systemTemp.createTemp('v136-ctrl');
      addTearDown(() => tempDir.delete(recursive: true));
      final downloads = AudioDownloadService(
        client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await downloads.init();
      addTearDown(downloads.dispose);
      final controller = AudioPlayerController(downloads: downloads);
      addTearDown(controller.dispose);
      return controller;
    }

    test('playFromAyah queues the surah from this ayah onward', () async {
      final controller = await makeController();
      await controller.playFromAyah(3, 7);

      expect(controller.scope, PlayerScope.surah);
      expect(controller.queue.first, (3, 7));
      expect(controller.queue.last, (3, 200));
      expect(controller.queue.length, 194);
      expect(controller.lastError, isNull);
    });

    test('playFromAyah at the last ayah behaves like playAyah', () async {
      final controller = await makeController();
      await controller.playFromAyah(3, 200);

      expect(controller.queue, [(3, 200)]);
      expect(controller.lastError, isNull);
    });

    test('repeatWord repeats the word (count 1 → 3; count 3 stays)',
        () async {
      final controller = await makeController();
      controller.repeatCount = 1;
      await controller.repeatWord(3, 7, 7);
      expect(controller.repeatCount, 3);
      expect(controller.repeatItem, isTrue);
      expect(controller.scope, PlayerScope.word);
      expect(controller.wordIndex, 7);
      expect(controller.lastError, isNull);

      controller.setRepeatCount(3);
      await controller.repeatWord(3, 7, 7);
      expect(controller.repeatCount, 3);
      expect(controller.repeatItem, isTrue);
    });

    test('wordAutoPlay persists and restores', () async {
      final controller = await makeController();
      // v13.8: OFF by default — a tap opens the meaning only.
      expect(controller.wordAutoPlay, isFalse);
      controller.setWordAutoPlay(true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('word_autoplay'), isTrue);

      final restored = AudioPlayerController();
      addTearDown(restored.dispose);
      await restored.restorePlaybackSettings();
      expect(restored.wordAutoPlay, isTrue);
    });

    test('gloss priority still holds after the card rewrite (4:4)',
        () async {
      expect(
        await QuranWordData.wordGloss(4, 4, 'فَكُلُوهُ'),
        'فخذوه حلالاً.',
      );
      // v13.11: the Tafsir Center text is identical here, but it is
      // the first source now — 'tafsircenter', not 'addition'.
      expect(
        await QuranWordData.glossSourceForWord(4, 4, 'فَكُلُوهُ'),
        'tafsircenter',
      );
    });
  });
}
