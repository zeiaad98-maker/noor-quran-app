import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/main.dart';
import 'package:noor_quran/screens/surah_reader_screen.dart';
import 'package:noor_quran/widgets/word_card.dart';

import 'fake_just_audio.dart';

// v13.5 (user report 2026-11-17 21:17): tapping the ayah-end number
// glyph (﴿٧﴾) "messes up" — it opened the TAFSIR card. The world
// apps show the AYAH SHEET for an ayah tap, so the number tap must
// open the ayah sheet (play ayah, word chips, notes) and NOT the
// tafsir card (which stays reachable from the word card's التفسير
// button). End-to-end through the real reader: page 42 -> real
// tapAt on 2:255's number glyph (Ayat al-Kursi).
//
// v13.8 (one-card rule, the user's order 2026-11-18 12:31): the old
// ayah sheet is CANCELLED — the number tap now opens the WORD CARD
// on the ayah's first word, with the sheet's info line (الجزء •
// الربع • صفحة) and its note editor moved inside the card. The
// tafsir card still must NOT open.
//
// Page choice: page 42 (2:253-2:256) has NO surah header, so the
// test is not affected by a test-env artifact on header pages
// (page 50's HeaderWidget renders 100,000px tall in widget tests:
// its InkWell finds no Material ancestor in debug mode, the header
// blows up and pushes the text off-screen; release builds have no
// such assert, so the header is fine on the phone). The number-tap
// wiring is identical on every page.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    // The reader's download service resolves its storage dir via
    // path_provider at init; point it at the system temp dir.
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

  testWidgets('number tap on 2:255 opens the word card, not the tafsir card',
      (tester) async {
    await tester.pumpWidget(const NoorQuranApp());
    // The home screen builds after its async init; pump until the
    // navigation screen is there. (Note: the app is built on
    // material_ui, whose Scaffold/MaterialApp are its own types —
    // find.byType(Scaffold) from flutter/material.dart finds
    // nothing; use the app's own MainNavigationScreen as the
    // Navigator anchor instead.)
    for (var i = 0;
        i < 20 && find.byType(MainNavigationScreen).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MainNavigationScreen), findsOneWidget);

    // Push the reader straight onto page 42 (2:253-2:256).
    final context = tester.element(find.byType(MainNavigationScreen));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const SurahReaderScreen(surahNumber: 2, initialPage: 42),
      ),
    );

    // The reader is calibrated for a 411dp-wide screen: size the
    // viewport for it BEFORE its first frame renders.
    tester.view.physicalSize = const Size(411 * 2.63, 913 * 2.63);
    tester.view.devicePixelRatio = 2.63;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpFrames(tester, 8);

    // Drain the layout errors recorded while the tree first laid
    // out at 411dp (home screen + reader header overflow in the
    // test env: google_fonts cannot fetch Amiri offline, so the
    // fallback font is wider than the real one — the screens fit
    // on the phone). The takeException() check at the end then
    // catches only errors from the tap and the sheet itself.
    while (tester.takeException() != null) {}

    // The Mushaf paragraph is the RichText whose text contains
    // 2:255 (the PageView may also have neighbouring pages built).
    final verseText = getVerseQCF(2, 255, verseEndSymbol: false);
    RichText? mushafParagraph;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      final span = rt.text;
      if (span is TextSpan && span.toPlainText().contains(verseText)) {
        mushafParagraph = rt;
        break;
      }
    }
    expect(mushafParagraph, isNotNull,
        reason: 'page 42 paragraph with 2:255 must render');
    final plainText =
        (mushafParagraph!.text as TextSpan).toPlainText();
    final rp =
        tester.renderObject<RenderParagraph>(find.byWidget(mushafParagraph));

    // The number glyph sits directly after 2:255's own text —
    // word spans, then the number span.
    final verseStart = plainText.indexOf(verseText);
    expect(verseStart, greaterThanOrEqualTo(0),
        reason: '2:255 must appear on page 42');
    final numberOffset = verseStart + verseText.length;
    expect(
      plainText.codeUnitAt(numberOffset),
      getVerseNumberQCF(2, 255).codeUnitAt(0),
      reason: 'the char after 2:255 must be its number glyph',
    );
    final boxes = rp.getBoxesForSelection(
      TextSelection(
          baseOffset: numberOffset, extentOffset: numberOffset + 1),
    );
    expect(boxes, isNotEmpty,
        reason: '2:255 number glyph must have a box');
    await tester.tapAt(rp.localToGlobal(boxes.first.toRect().center));
    await pumpFrames(tester, 6);

    // The word card opens for 2:255 (first word) — and the tafsir
    // card does not. The card carries the old sheet's info line
    // ('الجزء 3' is unique to it — the reader's own header says
    // 'الجزء الأول').
    expect(find.byType(WordCard), findsOneWidget);
    expect(find.byKey(const ValueKey('ayahHeader')), findsOneWidget);
    expect(find.textContaining('الجزء 3'), findsOneWidget);
    expect(find.byType(TafsirCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
