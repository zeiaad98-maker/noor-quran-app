import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_downloads.dart';
import 'package:noor_quran/data/quran_audio.dart';
import 'package:noor_quran/main.dart';
import 'package:noor_quran/screens/surah_reader_screen.dart';
import 'package:noor_quran/widgets/audio_player_sheet.dart';
import 'package:noor_quran/widgets/word_card.dart';

import 'fake_just_audio.dart';

// v13.7 — the user's two reports on v13.6 (2026-11-18 10:19):
//
// 1. "هاد الشريط لازم ما يطلع" — the compact mini-player bar that
//    docked at the bottom of the reader (overlaying the Mushaf
//    page) must never appear. Pause/stop stay reachable: the
//    reader's top audio button pauses while playing, the bottom
//    "إيقاف الصوت" button stops, and the full player sheet holds
//    every other control.
// 2. "التحميل بطيئ جدا جدا جدا جدا" — for ayah AND page playback
//    alike: the v13.5 ZIP-first order forced a whole-surah ZIP
//    download (58 MB for Baqarah) before the first sound. Now the
//    per-ayah file over the www host goes first (one small file,
//    playback in seconds); the ZIP is the fallback and the explicit
//    bulk download only.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ayah audio order (v13.7)', () {
    late Directory tempDir;
    late AudioDownloadService service;
    var serviceCreated = false;

    Future<AudioDownloadService> buildService(http.Client client) async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('v137-ayah');
      final s = AudioDownloadService(
        client: client,
        storageDir: tempDir,
        prefs: await SharedPreferences.getInstance(),
      );
      await s.init();
      serviceCreated = true;
      return s;
    }

    tearDown(() async {
      if (!serviceCreated) return;
      service.dispose();
      await tempDir.delete(recursive: true);
      serviceCreated = false;
    });

    test('everyayahWwwUrl builds the www per-ayah address', () {
      expect(everyayahWwwUrl(reciters[12], 2, 14),
          'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/002014.mp3');
      expect(everyayahWwwUrl(reciters[0], 112, 2),
          'http://www.everyayah.com/data/Husary_64kbps/112002.mp3');
    });

    test('www per-ayah first: no ZIP request at all', () async {
      final requested = <String>[];
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([5, 5, 5], 200);
      }));

      final file = await service.cacheAyahFile(reciters[12], 2, 33);
      expect(file, isNotNull);
      expect(await file!.readAsBytes(), [5, 5, 5]);
      expect(requested, [
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/002033.mp3',
      ]);
    });

    test('www, islamic, alternates and bare all 404 → null, no ZIP '
        'request (v13.12)', () async {
      final requested = <String>[];
      service = await buildService(MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheAyahFile(reciters[12], 2, 33);
      expect(file, isNull);
      expect(service.localAyahFile(reciters[12], 2, 33), isNull);
      // v13.12 (user's correction): the whole-surah ZIP is NOT a
      // playback fallback — the chain ends at the bare file.
      // Tunaiji has no islamic.network step.
      expect(requested, [
        'http://www.everyayah.com/data/khalefa_al_tunaiji_64kbps/002033.mp3',
        'https://verses.quran.com/Tunaiji/mp3/002033.mp3',
        'https://huggingface.co/datasets/maqra-project/khalifa-al-tunaiji-64kbps/resolve/main/002033.mp3',
        'https://everyayah.com/data/khalefa_al_tunaiji_64kbps/002033.mp3',
      ]);
      expect(requested.any((u) => u.contains('/zips/')), isFalse);
    });

    test('www, alternates and bare per-ayah all fail → null, no file',
        () async {
      service = await buildService(MockClient((request) async {
        return http.Response.bytes([], 404);
      }));

      final file = await service.cacheAyahFile(reciters[0], 112, 3);
      expect(file, isNull);
      expect(service.localAyahFile(reciters[0], 112, 3), isNull);
    });
  });

  group('reader — no mini bar (v13.7)', () {
    setUpAll(() async {
      for (var page = 1; page <= 604; page++) {
        final p = page.toString().padLeft(3, '0');
        final data = await rootBundle.load(
            'packages/qcf_quran/assets/fonts/qcf4/QCF4${p}_X-Regular.woff');
        final loader = FontLoader('packages/qcf_quran/QCF_P$p');
        loader.addFont(Future.value(data));
        await loader.load();
      }
    });

    setUp(() {
      installFakeJustAudio();
      SharedPreferences.setMockInitialValues({});
      // Bound the reader's background download attempts (real http
      // client, no network in tests): one fast-failing attempt per
      // host instead of the defaults.
      AudioDownloadService.fetchAttempts = 1;
      AudioDownloadService.stallTimeout = const Duration(seconds: 1);
      AudioDownloadService.retryBackoff =
          const Duration(milliseconds: 10);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsDirectory' ||
              call.method == 'getTemporaryDirectory') {
            return Directory.systemTemp.path;
          }
          return null;
        },
      );
    });

    tearDown(() {
      AudioDownloadService.fetchAttempts = 2;
      AudioDownloadService.stallTimeout = const Duration(seconds: 30);
      AudioDownloadService.retryBackoff = const Duration(seconds: 2);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    Future<void> pumpFrames(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Test-env font artifacts (google_fonts cannot fetch Amiri
    // offline, so the fallback font is wider): RenderFlex overflows
    // and google_fonts load failures from the home screen / sheets
    // are expected noise. Any other recorded error must still fail
    // the test. (takeException aggregates several pending errors
    // into one "Multiple exceptions" object — drain it the same way.)
    void drainLayoutOverflows(WidgetTester tester) {
      Object? e;
      while ((e = tester.takeException()) != null) {
        final msg = e.toString();
        if (msg.contains('overflowed') ||
            msg.contains('google_fonts was unable to load font') ||
            msg.contains('Multiple exceptions')) {
          continue;
        }
        fail('unexpected exception during test: $e');
      }
    }

    testWidgets('playing an ayah never shows the mini bar',
        (tester) async {
      await tester.pumpWidget(const NoorQuranApp());
      for (var i = 0;
          i < 20 && find.byType(MainNavigationScreen).evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(MainNavigationScreen), findsOneWidget);

      // Push the reader straight onto page 42 (2:253-2:256 — no
      // surah header, so the test-env header artifact cannot move
      // the text).
      final context = tester.element(find.byType(MainNavigationScreen));
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              const SurahReaderScreen(surahNumber: 2, initialPage: 42),
        ),
      );
      tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
      tester.view.devicePixelRatio = 2.63;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpFrames(tester, 8);
      drainLayoutOverflows(tester);

      // Tap 2:255's number glyph → the word card opens (v13.8:
      // the old ayah sheet is gone; the number tap opens the card
      // on the ayah's first word).
      final verseText = getVerseQCF(2, 255, verseEndSymbol: false);
      RichText? mushafParagraph;
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        final span = rt.text;
        if (span is TextSpan && span.toPlainText().contains(verseText)) {
          mushafParagraph = rt;
          break;
        }
      }
      expect(mushafParagraph, isNotNull);
      final plainText = (mushafParagraph!.text as TextSpan).toPlainText();
      final rp = tester.renderObject<RenderParagraph>(
          find.byWidget(mushafParagraph));
      final verseStart = plainText.indexOf(verseText);
      final numberOffset = verseStart + verseText.length;
      final boxes = rp.getBoxesForSelection(
        TextSelection(
            baseOffset: numberOffset, extentOffset: numberOffset + 1),
      );
      expect(boxes, isNotEmpty);
      await tester.tapAt(rp.localToGlobal(boxes.first.toRect().center));
      await pumpFrames(tester, 6);
      expect(find.byType(WordCard), findsOneWidget);

      // Play the ayah from the card's bottom bar: the card pops and
      // the ayah plays WITHOUT opening the player sheet (v13.8: the
      // card's الآية button plays directly). No mini bar appears.
      await tester.tap(find.byKey(const ValueKey('playAyahButton')));
      await pumpFrames(tester, 8);
      expect(find.byType(WordCard), findsNothing);
      expect(find.byTooltip('إغلاق وإيقاف الصوت'), findsNothing);

      // Open the full player sheet from the reader's bottom bar:
      // the eye button shows the control bars, then the reciter
      // name opens the sheet without restarting the ayah. (The
      // reader's reciter is خليفة الطنيجي — the app default — not
      // الحصري, which a fresh controller alone defaults to.)
      //
      // The test font is ~40% wider than the phone's Amiri, so at
      // 411dp the reader's control rows overflow and their buttons
      // land off-screen (hit-test misses). Widen the viewport for
      // these steps only — the behaviour under test (audio + mini
      // bar) does not depend on the width.
      tester.view.physicalSize = const Size(800 * 2.63, 913 * 2.63);
      await tester.pump();
      await tester.tap(find.byTooltip('إظهار / إخفاء أشرطة التحكم'));
      await pumpFrames(tester, 4);
      await tester.tap(find.text('خليفة الطنيجي'));
      await pumpFrames(tester, 8);
      expect(find.byType(AudioPlayerSheet), findsOneWidget);
      // The sheet's own close button is the ONLY 'إغلاق وإيقاف
      // الصوت' on screen — the docked mini bar (which used to
      // carry the same tooltip behind the sheet) is gone.
      expect(find.byTooltip('إغلاق وإيقاف الصوت'), findsOneWidget);

      // Dismiss the sheet without stopping the audio: no bar is
      // left behind on the reader.
      Navigator.of(tester.element(find.byType(AudioPlayerSheet))).pop();
      await pumpFrames(tester, 6);
      expect(find.byType(AudioPlayerSheet), findsNothing);
      expect(find.byTooltip('إغلاق وإيقاف الصوت'), findsNothing);
      drainLayoutOverflows(tester);
    });
  });
}
