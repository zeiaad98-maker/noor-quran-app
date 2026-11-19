import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/adhkar_data.dart';
import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/ayah_marks.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/screens/adhkar_tasbeeh_screen.dart';

import 'fake_just_audio.dart';
import 'zip_fixture.dart';

/// v13.3 — the four fixes, pinned:
///
/// * FIX A — downloads on weak internet: streamed, stall timeout
///   only (no wall-clock limit), resume + retry, honest progress,
///   cancel. The "strong internet" message is gone (checked via the
///   controller's real failure path, and by grep in the report).
/// * FIX B — word-popup marks: bookmark / highlight persist and
///   round-trip (the reader's الفواصل section reads the same store).
/// * FIX C — Adhkar redesign: the morning/evening split comes from
///   the real باب 27 data (23 / 21, 20 shared), counts worded.
/// * FIX D — cosmetic: no wordPart anywhere starts/ends with
///   U+00A0 or a newline (37:24 word 3's trailing \n included).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fake = installFakeJustAudio();
  SharedPreferences.setMockInitialValues({});

  group('ayah marks (FIX B)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('bookmark toggle / is / remove persist', () async {
      expect(await AyahBookmarks.isBookmarked(2, 33), isFalse);
      expect(await AyahBookmarks.toggle(2, 33), isTrue);
      expect(await AyahBookmarks.isBookmarked(2, 33), isTrue);
      expect(await AyahBookmarks.ids(), {'2:33'});
      expect(await AyahBookmarks.toggle(2, 33), isFalse);
      expect(await AyahBookmarks.ids(), isEmpty);

      await AyahBookmarks.toggle(2, 33);
      await AyahBookmarks.toggle(1, 1);
      await AyahBookmarks.remove(2, 33);
      expect(await AyahBookmarks.ids(), {'1:1'});
    });

    test('highlight toggle / is / remove persist', () async {
      expect(await AyahHighlights.isHighlighted(37, 24), isFalse);
      expect(await AyahHighlights.toggle(37, 24), isTrue);
      expect(await AyahHighlights.isHighlighted(37, 24), isTrue);
      expect(await AyahHighlights.ids(), {'37:24'});
      await AyahHighlights.remove(37, 24);
      expect(await AyahHighlights.ids(), isEmpty);
    });

    test('bookmark and highlight are independent stores', () async {
      await AyahBookmarks.toggle(2, 33);
      expect(await AyahHighlights.isHighlighted(2, 33), isFalse);
      await AyahHighlights.toggle(2, 33);
      expect(await AyahBookmarks.isBookmarked(2, 33), isTrue);
    });
  });

  group('downloads on weak internet (FIX A)', () {
    late Directory tempDir;
    late AudioDownloadService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v133-dl');
    });

    tearDown(() async {
      service.dispose();
      await tempDir.delete(recursive: true);
      AudioDownloadService.stallTimeout = const Duration(seconds: 30);
      AudioDownloadService.fetchAttempts = 2;
      AudioDownloadService.retryBackoff = const Duration(seconds: 2);
    });

    Future<AudioDownloadService> buildService(http.Client client) async {
      service = AudioDownloadService(
        client: client,
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await service.init();
      return service;
    }

    test('slow download succeeds even when it outlasts the stall window',
        () async {
      // 1,000 bytes in 100-byte chunks, 250 ms apart: 2.5 s total,
      // while the stall window is only 1 s. Bytes keep arriving,
      // so no stall fires — and there is no wall-clock timeout to
      // kill it. (The old code's 15 s per-attempt timeout is gone.)
      AudioDownloadService.stallTimeout = const Duration(seconds: 1);
      final bytes = List<int>.generate(1000, (i) => i % 256);
      final zipBytes =
          buildSurahZip({'002033.mp3': bytes}, stored: true);
      final client = _FakeSlowClient(
        bytes: bytes,
        zipBytes: zipBytes,
        chunkGap: const Duration(milliseconds: 250),
      );
      await buildService(client);
      final progress = <(int, int?)>[];
      final file = await service.cacheAyahFile(
        reciters[0],
        2,
        33,
        onProgress: (r, t) => progress.add((r, t)),
      );
      expect(file, isNotNull);
      expect(await file!.length(), 1000);
      // v13.7: progress runs over the per-ayah file now (it is
      // tried first) — one download, so it is monotonic and ends
      // at the file's own total.
      expect(progress.last, (1000, 1000));
      // Progress really moved (not one jump at the end).
      expect(progress.map((p) => p.$1).toSet().length, greaterThan(5));
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].$1, greaterThanOrEqualTo(progress[i - 1].$1));
      }
    });

    test('slow alternate-host download succeeds when the www '
        'per-ayah file is unavailable', () async {
      // Same slow stream, but the www per-ayah file 404s — and
      // islamic.network + the bare host 404 too — so the MIRROR
      // alternate host (v13.12) serves the slow file: progress
      // ends at the file's own total, not a ZIP total (there is
      // no ZIP in the playback path any more).
      AudioDownloadService.stallTimeout = const Duration(seconds: 1);
      final bytes = List<int>.generate(1000, (i) => i % 256);
      final zipBytes =
          buildSurahZip({'002033.mp3': bytes}, stored: true);
      final client = _FakeSlowClient(
        bytes: bytes,
        zipBytes: zipBytes,
        failWww: true,
        failFallbackHosts: true,
        serveMirror: true,
        chunkGap: const Duration(milliseconds: 250),
      );
      await buildService(client);
      final progress = <(int, int?)>[];
      final file = await service.cacheAyahFile(
        reciters[0],
        2,
        33,
        onProgress: (r, t) => progress.add((r, t)),
      );
      expect(file, isNotNull);
      expect(await file!.length(), 1000);
      expect(progress.last, (1000, 1000));
      expect(progress.map((p) => p.$1).toSet().length, greaterThan(5));
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i].$1, greaterThanOrEqualTo(progress[i - 1].$1));
      }
    });

    test('a stalled download fails instead of spinning forever',
        () async {
      AudioDownloadService.stallTimeout =
          const Duration(milliseconds: 300);
      AudioDownloadService.fetchAttempts = 1;
      final client = _FakeSlowClient(
        bytes: List<int>.generate(500, (i) => i % 256),
        stall: true,
      );
      await buildService(client);
      final file = await service.cacheAyahFile(reciters[0], 2, 33);
      expect(file, isNull,
          reason: 'no bytes for one stall window → failure, not a hang');
    });

    test('an interrupted download resumes from the partial file',
        () async {
      AudioDownloadService.retryBackoff = const Duration(milliseconds: 10);
      final bytes = List<int>.generate(1000, (i) => i % 256);
      final client = _FakeSlowClient(
        bytes: bytes,
        zipBytes: buildSurahZip({'002033.mp3': bytes}, stored: true),
        // First attempt sends only the first half, then closes
        // early (size != total → failure, tmp kept for resume).
        cutAfterFraction: 0.5,
        cutOnlyFirstAttempt: true,
      );
      await buildService(client);
      final file = await service.cacheAyahFile(reciters[0], 2, 33);
      expect(file, isNotNull);
      expect(await file!.length(), 1000);
      expect(client.attempts, 2,
          reason: 'attempt 1 cut short, attempt 2 resumed via Range');
      expect(client.sawRange, isTrue);
    });

    test('a 500 on the first attempt is retried and then succeeds',
        () async {
      AudioDownloadService.retryBackoff = const Duration(milliseconds: 10);
      final bytes = List<int>.generate(400, (i) => i % 256);
      final client = _FakeSlowClient(
        bytes: bytes,
        zipBytes: buildSurahZip({'002033.mp3': bytes}, stored: true),
        failAttempts: 1,
      );
      await buildService(client);
      final file = await service.cacheAyahFile(reciters[0], 2, 33);
      expect(file, isNotNull);
      expect(await file!.length(), 400);
      expect(client.attempts, 2);
    });

    test('cancel aborts the download and caches nothing', () async {
      AudioDownloadService.retryBackoff = const Duration(milliseconds: 10);
      final client = _FakeSlowClient(
        bytes: List<int>.generate(1000, (i) => i % 256),
        chunkGap: const Duration(milliseconds: 100),
      );
      await buildService(client);
      // Immediate cancel.
      final cancelled = await service.cacheAyahFile(
        reciters[0],
        2,
        33,
        isCancelled: () => true,
      );
      expect(cancelled, isNull);
      expect(service.localAyahFile(reciters[0], 2, 33), isNull);

      // Mid-download cancel (after the first progress report).
      var cancel = false;
      final mid = await service.cacheAyahFile(
        reciters[0],
        2,
        34,
        onProgress: (_, __) => cancel = true,
        isCancelled: () => cancel,
      );
      expect(mid, isNull);
      expect(service.localAyahFile(reciters[0], 2, 34), isNull);
    });

    test('a cached file is reused — no second download', () async {
      final bytes = List<int>.generate(200, (i) => i % 256);
      final client = _FakeSlowClient(
        bytes: bytes,
        zipBytes: buildSurahZip({'002033.mp3': bytes}, stored: true),
      );
      await buildService(client);
      final first = await service.cacheAyahFile(reciters[0], 2, 33);
      expect(first, isNotNull);
      expect(client.attempts, 1);
      final second = await service.cacheAyahFile(reciters[0], 2, 33);
      expect(second, isNotNull);
      expect(client.attempts, 1, reason: 'served from disk, offline');
    });
  });

  group('failure message (FIX A)', () {
    test('a failed load reports the plain message, never the old one',
        () async {
      fake.autoFinish = false;
      fake.failLoadSubstrings.clear();
      fake.loadDelay = Duration.zero;
      // v13.13: the ayah stream tries EVERY host in order
      // (SurahPedia, www, the alternates, islamic.network, bare)
      // — all of them must fail for the error to show (Tunaiji:
      // SurahPedia + www + verses + Maqra + bare).
      fake.failLoadSubstrings.addAll([
        'surahpedia',
        'everyayah',
        'verses.quran.com',
        'huggingface.co',
      ]);
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      controller.reciterIndex = 12;

      await controller.playAyah(2, 33);
      expect(controller.lastError,
          'تعذّر تحميل الصوت — تحقق من الاتصال وحاول مجدداً');
      expect(controller.lastError, isNot(contains('قوي')));
      expect(controller.isLoading, isFalse);
      expect(controller.isPlaying, isFalse);
    });
  });

  group('Adhkar morning/evening split (FIX C)', () {
    late AdhkarCategory combined;

    setUp(() {
      combined = adhkarCategories.firstWhere(
        (c) => c.title == 'أذكار الصباح والمساء',
      );
    });

    test('the book has 132 chapters and 267 adhkar (banner counts)',
        () {
      expect(adhkarCategories.length, 132);
      var total = 0;
      for (final c in adhkarCategories) {
        total += c.items.length;
      }
      expect(total, 267);
    });

    test('combined باب 27 has exactly 24 items', () {
      expect(combined.items.length, 24);
    });

    test('morning 23 / evening 21 / 20 shared, from the real texts',
        () {
      final morning = morningAdhkar(combined);
      final evening = eveningAdhkar(combined);
      expect(morning.title, 'أذكار الصباح');
      expect(evening.title, 'أذكار المساء');
      expect(morning.items.length, 23);
      expect(evening.items.length, 21);

      final morningTexts = morning.items.map((i) => i.text).toSet();
      final eveningTexts = evening.items.map((i) => i.text).toSet();
      expect(morningTexts.intersection(eveningTexts).length, 20);

      // Morning-only items say "(إذا أصبحَ)" — they are in the
      // morning list and NOT in the evening list.
      final morningOnly =
          combined.items.where((i) => i.text.contains('إذا أصبحَ'));
      expect(morningOnly.length, 3);
      for (final item in morningOnly) {
        expect(morning.items.contains(item), isTrue);
        expect(evening.items.contains(item), isFalse);
      }
      // Evening-only item says "(إذا أمسى)".
      final eveningOnly =
          combined.items.where((i) => i.text.contains('إذا أمسى'));
      expect(eveningOnly.length, 1);
      for (final item in eveningOnly) {
        expect(evening.items.contains(item), isTrue);
        expect(morning.items.contains(item), isFalse);
      }
      // No list ever carries the other time's wording.
      for (final item in morning.items) {
        expect(item.text.contains('إذا أمسى'), isFalse);
      }
      for (final item in evening.items) {
        expect(item.text.contains('إذا أصبحَ'), isFalse);
      }
      // Exact positions: morning drops only old item 23 (index 22);
      // evening drops only old items 19–21 (indices 18–20).
      expect(morning.items[22], combined.items[23]);
      expect(evening.items[18], combined.items[21]);
      // Texts, counts and sources are verbatim (same objects).
      expect(morning.items[0], combined.items[0]);
      expect(evening.items[0], combined.items[0]);
    });

    test('display list: morning + evening first, combined chapter gone',
        () {
      final list = displayAdhkarCategories();
      expect(list.length, adhkarCategories.length + 1);
      expect(list[0].title, 'أذكار الصباح');
      expect(list[1].title, 'أذكار المساء');
      expect(list.any((c) => c.title == 'أذكار الصباح والمساء'), isFalse);
      expect(
        list.sublist(2).map((c) => c.title).toList(),
        adhkarCategories
            .where((c) => c.title != 'أذكار الصباح والمساء')
            .map((c) => c.title)
            .toList(),
        reason: 'the rest of the book stays in book order',
      );
    });

    test('count words cover every count in the book', () {
      expect(countWords(1), 'مرة واحدة');
      expect(countWords(3), 'ثلاث مرات');
      expect(countWords(4), 'أربع مرات');
      expect(countWords(7), 'سبع مرات');
      expect(countWords(10), 'عشر مرات');
      expect(countWords(33), 'ثلاثاً وثلاثين مرة');
      expect(countWords(100), 'مائة مرة');
      const known = {1, 3, 4, 7, 10, 33, 100};
      for (final cat in adhkarCategories) {
        for (final item in cat.items) {
          expect(known.contains(item.count), isTrue,
              reason: '${cat.title}: count ${item.count} has no wording');
        }
      }
    });

    test('dhikr count labels match the sample (٢٣ ذكراً، ٤ أذكار)',
        () {
      expect(dhikrCountLabel(1), 'ذكر واحد');
      expect(dhikrCountLabel(2), 'ذكران');
      expect(dhikrCountLabel(4), '٤ أذكار');
      expect(dhikrCountLabel(8), '٨ أذكار');
      expect(dhikrCountLabel(13), '١٣ ذكراً');
      expect(dhikrCountLabel(23), '٢٣ ذكراً');
      expect(dhikrCountLabel(21), '٢١ ذكراً');
    });
  });

  group('word padding stripped (FIX D)', () {
    test('37:24 word 3 has no trailing newline', () {
      final map = buildQcfWordMap(37, 24);
      expect(map.wordCount, 3);
      expect(map.words[2].text, isNot(contains('\n')));
      expect(map.words[2].text, isNot(contains('\r')));
    });

    test('no word anywhere starts/ends with U+00A0 or a newline', () {
      var checked = 0;
      for (var s = 1; s <= 114; s++) {
        for (var a = 1; a <= quran.getVerseCount(s); a++) {
          final map = buildQcfWordMap(s, a);
          for (final w in map.words) {
            checked++;
            expect(
              w.text.isEmpty ||
                  _isWordPartPadding(w.text.codeUnitAt(0)) ||
                  _isWordPartPadding(
                      w.text.codeUnitAt(w.text.length - 1)),
              isFalse,
              reason: '$s:$a word ${w.text}',
            );
          }
        }
      }
      expect(checked, greaterThan(77000));
    });
  });
}

bool _isWordPartPadding(int c) => c == 0x00A0 || c == 0x0A || c == 0x0D;

/// A fake HTTP client serving one fixed payload, with knobs for the
/// weak-internet cases: slow chunked delivery, stalls, early closes
/// (resume), and failing first attempts (retry). Range requests are
/// honoured with a 206 + the remaining bytes.
class _FakeSlowClient extends http.BaseClient {
  final List<int> bytes;

  /// Full per-surah ZIP bytes, served for ZIP URLs only (v13.5:
  /// the explicit bulk download fetches the ZIP; v13.12:
  /// playback never requests it). When null, [bytes] is served
  /// for every URL (the old behaviour).
  final List<int>? zipBytes;

  /// When true, the www per-ayah host 404s (v13.7: the www file is
  /// tried first, so this forces the fallback hosts).
  final bool failWww;

  /// When true, the small fallback hosts 404 too (v13.11: the bare
  /// per-ayah host and islamic.network are tried before the bare
  /// file; v13.12: the alternate hosts sit between them in the
  /// chain, so they 404 here as well — unless [serveMirror] lets
  /// the mirror host serve the slow file).
  final bool failFallbackHosts;

  /// When true (with [failFallbackHosts]), the mirror host
  /// (mirrors.quranicaudio.com) still serves the slow file —
  /// the v13.12 alternate-host path when www is unavailable.
  final bool serveMirror;
  final Duration chunkGap;
  final int failAttempts;
  final bool stall;
  final double? cutAfterFraction;
  final bool cutOnlyFirstAttempt;

  int attempts = 0;
  bool sawRange = false;

  _FakeSlowClient({
    required this.bytes,
    this.zipBytes,
    this.failWww = false,
    this.failFallbackHosts = false,
    this.serveMirror = false,
    this.chunkGap = Duration.zero,
    this.failAttempts = 0,
    this.stall = false,
    this.cutAfterFraction,
    this.cutOnlyFirstAttempt = false,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    attempts++;
    if (attempts <= failAttempts) {
      return http.StreamedResponse(const Stream.empty(), 500);
    }
    if (failWww &&
        request.url.host == 'www.everyayah.com' &&
        !request.url.path.endsWith('.zip')) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    if (failFallbackHosts &&
        (request.url.host == 'cdn.islamic.network' ||
            request.url.host == 'everyayah.com' ||
            request.url.host == 'mirrors.quranicaudio.com' ||
            request.url.host == 'huggingface.co') &&
        !request.url.path.endsWith('.zip') &&
        !(serveMirror &&
            request.url.host == 'mirrors.quranicaudio.com')) {
      return http.StreamedResponse(const Stream.empty(), 404);
    }
    // v13.7: the www per-ayah URL gets the raw per-ayah bytes (so
    // the per-ayah path succeeds first); the ZIP URL gets the real
    // ZIP bytes (so the bulk download succeeds when it requests it).
    final serveBytes = (zipBytes != null &&
            request.url.toString().contains('/zips/'))
        ? zipBytes!
        : bytes;
    final range = request.headers['Range'];
    var start = 0;
    var status = 200;
    if (range != null) {
      final m = RegExp(r'bytes=(\d+)-').firstMatch(range);
      if (m != null) {
        start = int.parse(m.group(1)!);
        status = 206;
        sawRange = true;
      }
    }
    final remaining = serveBytes.sublist(start);
    if (stall) {
      // A stream that never emits and never closes: the stall
      // timer must fire. (Stream has no .never() constructor.)
      final never = StreamController<List<int>>();
      return http.StreamedResponse(
        never.stream,
        status,
        contentLength: remaining.length,
      );
    }
    var toSend = remaining;
    if (cutAfterFraction != null &&
        (!cutOnlyFirstAttempt || attempts == 1)) {
      toSend = remaining.sublist(
          0, (remaining.length * cutAfterFraction!).floor());
    }
    Stream<List<int>> stream() async* {
      const chunkSize = 100;
      for (var i = 0; i < toSend.length; i += chunkSize) {
        if (chunkGap > Duration.zero) {
          await Future.delayed(chunkGap);
        }
        final end = (i + chunkSize).clamp(0, toSend.length);
        yield toSend.sublist(i, end);
      }
    }

    return http.StreamedResponse(
      stream(),
      status,
      contentLength: remaining.length,
    );
  }
}
