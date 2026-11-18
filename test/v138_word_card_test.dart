import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/ayah_notes.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/word_meanings.dart';
import 'package:noor_quran/widgets/word_card.dart';

/// v13.8 — the two word-card changes the user ordered Wed 2026-11-18:
/// 1. A tap on a word opens its meaning ONLY — no audio download.
///    wordAutoPlay now defaults to OFF (the gear toggle stays, so he
///    can turn auto-play back on if he ever wants it).
/// 2. The words in the card's ayah header are tappable: tapping
///    another word switches the card to that word in place — meaning,
///    tabs and buttons follow — with no close/reopen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('wordAutoPlay default OFF (v13.8)', () {
    test('fresh controller: tap opens the meaning only', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = AudioPlayerController();
      addTearDown(controller.dispose);
      expect(controller.wordAutoPlay, isFalse);
      await controller.restorePlaybackSettings();
      expect(controller.wordAutoPlay, isFalse);
    });
  });

  group('header word tap switches the card in place (v13.8)', () {
    /// 411dp logical width, the user's phone.
    void set411(WidgetTester tester) {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    /// Same warm-up as word_card_test: the card loads its data from
    /// rootBundle in initState; alternate real-async windows with
    /// pumps until the spinner is gone.
    Future<void> warmUntilLoaded(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pump();
        if (i >= 4 &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> openCard(
      WidgetTester tester, {
      int surah = 3,
      int verse = 7,
      int wordIndex = 7,
      VoidCallback? onOpenNotesScreen,
    }) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showWordCard(
                  context: context,
                  surah: surah,
                  verse: verse,
                  wordIndex: wordIndex,
                  pageNumber: 3,
                  audioController: AudioPlayerController(),
                  onPlayWord: (_) {},
                  onRepeatWord: (_) {},
                  onPlayAyah: () {},
                  onPlayPage: () {},
                  onContinueFromAyah: () {},
                  onGoToLastReading: () {},
                  onOpenNotesScreen: onOpenNotesScreen ?? () {},
                  onOpenTafsir: () {},
                  onOpenReciterPicker: () {},
                  onOpenPlaybackSettings: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await warmUntilLoaded(tester);
    }

    /// The header's RichText (matched by content, like word_card_test:
    /// the medallion's own Text also builds a RichText).
    Finder headerRichText(String wordText) {
      return find.descendant(
        of: find.byKey(const ValueKey('ayahHeader')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text is TextSpan &&
              (w.text as TextSpan).children?.any((s) =>
                      s is TextSpan &&
                      s.text != null &&
                      QuranWordData.normalizeArabic(s.text!) ==
                          QuranWordData.normalizeArabic(wordText)) ==
                  true,
        ),
      );
    }

    /// The blue (tapped) word in the header.
    Finder blueWord(String wordText) {
      return find.descendant(
        of: find.byKey(const ValueKey('ayahHeader')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text is TextSpan &&
              (w.text as TextSpan).children?.any((s) =>
                      s is TextSpan &&
                      s.text != null &&
                      QuranWordData.normalizeArabic(s.text!) ==
                          QuranWordData.normalizeArabic(wordText) &&
                      s.style?.color == const Color(0xFF2E7FD1)) ==
                  true,
        ),
      );
    }

    /// Tap a header word by its glyph position (TextSpans are not
    /// widgets, so there is no Finder for them — tap the paragraph
    /// at the word's own box).
    Future<void> tapHeaderWord(
        WidgetTester tester, List<QcfWordInfo> words, int target) async {
      final header = headerRichText(words[target].text);
      expect(header, findsOneWidget);
      final render = tester.renderObject<RenderParagraph>(header);
      var offset = 0;
      for (var i = 0; i < target; i++) {
        offset += words[i].text.length + 1; // word + the space after it
      }
      final boxes = render.getBoxesForSelection(
        TextSelection(
          baseOffset: offset,
          extentOffset: offset + words[target].text.length,
        ),
      );
      expect(boxes, isNotEmpty);
      await tester.tapAt(render.localToGlobal(boxes.first.toRect().center));
      await tester.pump();
    }

    testWidgets('3:7: مُّحْكَمَاتٌ → آيَاتٌ, meaning follows, card stays',
        (tester) async {
      set411(tester);
      final words = buildQcfWordMap(3, 7).words;
      // Self-checking indices: 7 is مُّحْكَمَاتٌ; 6 is آيَاتٌ in its
      // QCF spelling (ءَايَاتٌ — hamza + alif, so compare loosely).
      expect(QuranWordData.normalizeArabic(words[7].text),
          QuranWordData.normalizeArabic('مُّحْكَمَاتٌ'));
      expect(QuranWordData.normalizeArabic(words[6].text), contains('ايات'));

      await openCard(tester);
      expect(blueWord(words[7].text), findsOneWidget);
      expect(find.textContaining('واضحات لا احتمال فيها ولا اشباه'),
          findsOneWidget);

      // Switch to the word before it, from inside the card.
      await tapHeaderWord(tester, words, 6);
      await warmUntilLoaded(tester);

      // The card is still open, now showing آيَاتٌ in blue.
      expect(find.byType(WordCard), findsOneWidget);
      expect(blueWord(words[6].text), findsOneWidget);
      expect(blueWord(words[7].text), findsNothing);
      // The old word's gloss is gone. آيَاتٌ has no short meaning in
      // any source — its wordGloss is the generic fallback — so since
      // v13.9 the المعنى tab says so honestly instead of showing the
      // generic fallback text (the old probe asserted that text).
      expect(find.textContaining('واضحات لا احتمال فيها ولا اشباه'),
          findsNothing);
      expect(await QuranWordData.wordGloss(3, 7, words[6].lookupText),
          'كلمة من كلمات القرآن الكريم');
      expect(
          find.text('لا يوجد معنى مختصر لهذه الكلمة في المصادر المتوفرة.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching resets to the المعنى tab', (tester) async {
      set411(tester);
      final words = buildQcfWordMap(3, 7).words;
      await openCard(tester);

      // Move off the meaning tab first (word 7's sarf).
      await tester.tap(find.byKey(const ValueKey('tabSarf')));
      await tester.pump();
      expect(find.textContaining('جمع مؤنث سالم'), findsOneWidget);

      // Switch words from the header.
      await tapHeaderWord(tester, words, 6);
      await warmUntilLoaded(tester);

      // Back on المعنى: its tab is green again, the sarf is gone.
      final tabContainer = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('tabMeaning')),
          matching: find.byType(Container),
        ),
      );
      final decoration = tabContainer.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF0D6E52));
      expect(find.textContaining('جمع مؤنث سالم'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the word already shown does nothing',
        (tester) async {
      set411(tester);
      final words = buildQcfWordMap(3, 7).words;
      await openCard(tester);

      await tapHeaderWord(tester, words, 7);
      await tester.pumpAndSettle();

      expect(find.byType(WordCard), findsOneWidget);
      expect(blueWord(words[7].text), findsOneWidget);
      expect(find.textContaining('واضحات لا احتمال فيها ولا اشباه'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    group('inline note editor (v13.8 merge — old ayah sheet is gone)',
        () {
      Future<void> openNoteEditor(WidgetTester tester) async {
        set411(tester);
        await openCard(tester);
        // The ملاحظة pill sits at the bottom of the scrollable
        // middle: scroll it into view, then open the editor.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('notesButton')),
          100,
        );
        await tester.tap(find.byKey(const ValueKey('notesButton')));
        await tester.pump();
        expect(find.byKey(const ValueKey('noteEditor')), findsOneWidget);
      }

      testWidgets('save: editor closes, yellow box shows, note persists',
          (tester) async {
        await openNoteEditor(tester);

        await tester.ensureVisible(
          find.byKey(const ValueKey('noteTextField')),
        );
        await tester.enterText(
            find.byKey(const ValueKey('noteTextField')), 'فائدة تجريبية');
        await tester.ensureVisible(
          find.byKey(const ValueKey('saveNoteButton')),
        );
        await tester.tap(find.byKey(const ValueKey('saveNoteButton')));
        await tester.pumpAndSettle();

        // The card stays open; the editor closes and the saved note
        // shows in the yellow box; the pill icon turns green.
        expect(find.byType(WordCard), findsOneWidget);
        expect(find.byKey(const ValueKey('noteEditor')), findsNothing);
        expect(find.byKey(const ValueKey('savedNoteBox')), findsOneWidget);
        expect(find.text('فائدة تجريبية'), findsOneWidget);
        expect(await AyahNotes.getNote(3, 7), 'فائدة تجريبية');
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('notesButton')),
            matching: find.byIcon(Icons.note_alt),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('delete: saved note removed, pill icon reverts',
          (tester) async {
        await openNoteEditor(tester);
        await tester.ensureVisible(
          find.byKey(const ValueKey('noteTextField')),
        );
        await tester.enterText(
            find.byKey(const ValueKey('noteTextField')), 'فائدة للحذف');
        await tester.ensureVisible(
          find.byKey(const ValueKey('saveNoteButton')),
        );
        await tester.tap(find.byKey(const ValueKey('saveNoteButton')));
        await tester.pumpAndSettle();
        expect(await AyahNotes.getNote(3, 7), 'فائدة للحذف');

        // Reopen the editor: the field is pre-filled with the note.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('notesButton')),
          100,
        );
        await tester.tap(find.byKey(const ValueKey('notesButton')));
        await tester.pump();
        final field = tester.widget<TextField>(
            find.byKey(const ValueKey('noteTextField')));
        expect(field.controller!.text, 'فائدة للحذف');

        await tester.ensureVisible(
          find.byKey(const ValueKey('deleteNoteButton')),
        );
        await tester.tap(find.byKey(const ValueKey('deleteNoteButton')));
        await tester.pumpAndSettle();
        expect(await AyahNotes.getNote(3, 7), isNull);
        expect(find.byKey(const ValueKey('savedNoteBox')), findsNothing);
        expect(find.byKey(const ValueKey('noteEditor')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('notesButton')),
            matching: find.byIcon(Icons.note_add_outlined),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('ملاحظاتي link: card pops, notes-list callback fires',
          (tester) async {
        var notesTaps = 0;
        set411(tester);
        await openCard(tester, onOpenNotesScreen: () => notesTaps++);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('notesButton')),
          100,
        );
        await tester.tap(find.byKey(const ValueKey('notesButton')));
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('myNotesButton')),
        );
        await tester.tap(find.byKey(const ValueKey('myNotesButton')));
        await tester.pumpAndSettle();
        expect(find.byType(WordCard), findsNothing);
        expect(notesTaps, 1);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
