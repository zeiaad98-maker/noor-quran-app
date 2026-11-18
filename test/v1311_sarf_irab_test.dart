import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:noor_quran/data/audio_player_controller.dart';
import 'package:noor_quran/data/qcf_word_map.dart';
import 'package:noor_quran/data/word_meanings.dart';
import 'package:noor_quran/widgets/word_card.dart';

/// v13.11 — Tafsir Center per-word sarf + per-word i'rab
/// (his order «ضيف الصرف والإعراب هلأ مع هالنسخة»): the same
/// CC BY 4.0 dataset as the meanings, wired as the FIRST source
/// for the التصريف/الإعراب tabs, shown in FULL (never
/// shortened) with the small approved credit line. The
/// simplified morphology stays as fallback-only. Whole-ayah
/// i'rab is NOT bundled (new feature needing design).
///
/// Pinned entries below are verbatim from the built assets
/// (this file is generated — see
/// sarf-irab-import/gen_sarf_irab_test.py); the 2:1 pin covers
/// the dataset's wordNo=5 Basmalah-count quirk, and the 15:7
/// pins cover the لَوْمَا combined-particle duplication.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  /// QCF word index of the word whose normalized form is [norm].
  int wordIndexOf(int surah, int verse, String norm) {
    final words = buildQcfWordMap(surah, verse).words;
    return words.indexWhere(
        (w) => QuranWordData.normalizeArabic(w.lookupText) == norm);
  }

  group('Tafsir Center sarf + irab — pinned entries (v13.11)', () {
    test('2:7 خَتَمَ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(2, 7, 'ختم');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(2, 7).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(2, 7, lookup),
          '{خَتَمَ}: فِعْلٌ مَاضٍ لِلْغَائِبِ، مَبْنِيٌّ لِلْمَعْلُومِ، مُتَصَرِّفٌ، صَحِيحٌ سَالِمٌ، ثُلَاثِيٌّ مُجَرَّدٌ، مِنْ بَابِ: (ضَرَبَ يَضْرِبُ)، عَلَى وَزْنِ: (فَعَلَ)، مِنْ مَادَّةِ: (ختم).');
      expect(await QuranWordData.irabForWord(2, 7, lookup),
          'فِعْلٌ مَاضٍ مَبْنِيٌّ عَلَى الْفَتْحِ.');
      expect(await QuranWordData.sarfSourceForWord(2, 7, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(2, 7, lookup),
          'tafsircenter');
    });

    test('3:7 عَلَيۡكَ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(3, 7, 'عليك');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(3, 7).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(3, 7, lookup),
          '{عَلَى}: حَرْفٌ مَبْنِيٌّ.');
      expect(await QuranWordData.irabForWord(3, 7, lookup),
          '﴿عَلَى﴾ حَرْفُ جَرٍّ مَبْنِيٌّ عَلَى السُّكُونِ، وَ(كَافُ الْمُخَاطَبِ) ضَمِيرٌ مُتَّصِلٌ مَبْنِيٌّ عَلَى الْفَتْحِ فِي مَحَلِّ جَرٍّ بِالْحَرْفِ.');
      expect(await QuranWordData.sarfSourceForWord(3, 7, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(3, 7, lookup),
          'tafsircenter');
    });

    test('3:7 آيَاتٌ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(3, 7, 'ايات');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(3, 7).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(3, 7, lookup),
          '{آيَاتٌ}: اسْمٌ، مُؤَنَّثٌ، جَمْعُ مُؤَنَّثٍ سَالِمٌ، مُفْرَدُهُ: (آيَةٌ)، جَامِدٌ، ثُلَاثِيٌّ مُجَرَّدٌ، أَصْلُهُ: (أَيَيٌ)، عَلَى وَزْنِ: (فَعَلٌ)، فِيهِ إِعْلَالٌ بِقَلْبِ حَرْفِ: الْيَاءِ أَلِفًا لِتَحَرُّكِهَا وَانْفِتَاحِ مَا قَبْلَهَا، مِنْ مَادَّةِ: (أيي).');
      expect(await QuranWordData.irabForWord(3, 7, lookup),
          'مُبْتَدَأٌ مُؤَخَّرٌ مَرْفُوعٌ وَعَلَامَةُ رَفْعِهِ الضَّمَّةُ الظَّاهِرَةُ، وَالْجُمْلَةُ فِي مَحَلِّ نَصْبٍ حَالٌ.');
      expect(await QuranWordData.sarfSourceForWord(3, 7, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(3, 7, lookup),
          'tafsircenter');
    });

    test('4:4 صَدُقَاتِهِنَّ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(4, 4, 'صدقاتهن');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(4, 4).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(4, 4, lookup),
          '{صَدُقَاتِ}: اسْمٌ، مُؤَنَّثٌ، جَمْعُ مُؤَنَّثٍ سَالِمٌ، مُفْرَدُهُ: (صَدُقَةٌ)، جَامِدٌ، ثُلَاثِيٌّ مُجَرَّدٌ، عَلَى وَزْنِ: (فَعُلٌ)، مِنْ مَادَّةِ: (صدق).');
      expect(await QuranWordData.irabForWord(4, 4, lookup),
          'مَفْعُولٌ بِهِ ثَانٍ مَنْصُوبٌ وَعَلَامَةُ نَصْبِهِ الْكَسْرَةُ الظَّاهِرَةُ لِأَنَّهُ جَمْعُ مُؤَنَّثٍ سَالِمٌ وَهُوَ مُضَافٌ، وَ(هَاءُ الْغَائِبِ) ضَمِيرٌ مُتَّصِلٌ مَبْنِيٌّ عَلَى الْكَسْرِ فِي مَحَلِّ جَرٍّ مُضَافٌ إِلَيْهِ، وَ(النُّونُ) لِلْجَمْعِ.');
      expect(await QuranWordData.sarfSourceForWord(4, 4, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(4, 4, lookup),
          'tafsircenter');
    });

    test('4:4 فَكُلُوهُ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(4, 4, 'فكلوه');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(4, 4).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(4, 4, lookup),
          '{كُلُوا}: فِعْلُ أَمْرٍ لِلْمُخَاطَبِينِ، مُتَصَرِّفٌ، صَحِيحٌ مَهْمُوزُ الْفَاءِ، ثُلَاثِيٌّ مُجَرَّدٌ، مِنْ بَابِ: (نَصَرَ يَنْصُرُ)، عَلَى وَزْنِ: (افْعُلْ)، مِنْ مَادَّةِ: (أكل).');
      expect(await QuranWordData.irabForWord(4, 4, lookup),
          '(الْفَاءُ) حَرْفٌ وَاقِعٌ فِي جَوَابِ الشَّرْطِ مَبْنِيٌّ عَلَى الْفَتْحِ، وَ﴿كُلُوا﴾ فِعْلُ أَمْرٍ مَبْنِيٌّ عَلَى حَذْفِ النُّونِ، وَ(وَاوُ الْجَمَاعَةِ) ضَمِيرٌ مُتَّصِلٌ مَبْنِيٌّ عَلَى السُّكُونِ فِي مَحَلِّ رَفْعٍ فَاعِلٌ، وَ(هَاءُ الْغَائِبِ) ضَمِيرٌ مُتَّصِلٌ مَبْنِيٌّ عَلَى الضَّمِّ فِي مَحَلِّ نَصْبٍ مَفْعُولٌ بِهِ، وَالْجُمْلَةُ فِي مَحَلِّ جَزْمٍ جَوَابُ الشَّرْطِ.');
      expect(await QuranWordData.sarfSourceForWord(4, 4, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(4, 4, lookup),
          'tafsircenter');
    });

    test('15:11 يَسۡتَهۡزِءُونَ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(15, 11, 'يستهزءون');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(15, 11).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(15, 11, lookup),
          '{يَسْتَهْزِئُونَ}: فِعْلٌ مُضَارِعٌ لِلْغَائِبِينِ، مَبْنِيٌّ لِلْمَعْلُومِ، مُتَصَرِّفٌ، صَحِيحٌ مَهْمُوزُ اللَّامِ، سُدَاسِيٌّ مَزِيدٌ بِثَلَاثَةِ أَحْرُفٍ: التَّاءِ وَالسِّينِ وَالْيَاءِ، مِنْ بَابِ: (اسْتَفْعَلَ)، عَلَى وَزْنِ: (يَسْتَفْعِلُ)، مِنْ مَادَّةِ: (هزأ).');
      expect(await QuranWordData.irabForWord(15, 11, lookup),
          'فِعْلٌ مُضَارِعٌ مَرْفُوعٌ وَعَلَامَةُ رَفْعِهِ ثُبُوتُ النُّونِ لِأَنَّهُ مِنَ الْأَفْعَالِ الْخَمْسَةِ، وَ(وَاوُ الْجَمَاعَةِ) ضَمِيرٌ مُتَّصِلٌ مَبْنِيٌّ عَلَى السُّكُونِ فِي مَحَلِّ رَفْعٍ فَاعِلٌ، وَالْجُمْلَةُ فِي مَحَلِّ نَصْبٍ خَبَرُ كَانَ.');
      expect(await QuranWordData.sarfSourceForWord(15, 11, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(15, 11, lookup),
          'tafsircenter');
    });

    test('2:255 ٱللَّهُ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(2, 255, 'الله');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(2, 255).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(2, 255, lookup),
          '{اللَّهُ}: اسْمٌ، مُذَكَّرٌ، مُفْرَدٌ، جَامِدٌ، مِنْ مَادَّةِ: (أله).');
      expect(await QuranWordData.irabForWord(2, 255, lookup),
          'اسْمُ الْجَلَالَةِ مُبْتَدَأٌ مَرْفُوعٌ وَعَلَامَةُ رَفْعِهِ الضَّمَّةُ الظَّاهِرَةُ.');
      expect(await QuranWordData.sarfSourceForWord(2, 255, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(2, 255, lookup),
          'tafsircenter');
    });

    test('2:1 الٓمٓ — sarf + irab (tafsircenter)', () async {
      final idx = wordIndexOf(2, 1, 'الم');
      expect(idx, isNot(-1));
      final lookup =
          buildQcfWordMap(2, 1).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(2, 1, lookup),
          '{الم}: حَرْفٌ مَبْنِيٌّ.');
      expect(await QuranWordData.irabForWord(2, 1, lookup),
          'حُرُوفٌ مُقَطَّعَةٌ لِلدَّلَالَةِ عَلَى إِعْجَازِ الْقُرْآنِ.');
      expect(await QuranWordData.sarfSourceForWord(2, 1, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(2, 1, lookup),
          'tafsircenter');
    });

    test('15:7 لَوۡ — combined لَوْمَا sarf + irab on both words', () async {
      final idx = wordIndexOf(15, 7, 'لو');
      expect(idx, isNot(-1));
      final lookup = buildQcfWordMap(15, 7).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(15, 7, lookup),
          '{لَوْمَا}: حَرْفٌ مَبْنِيٌّ.');
      expect(await QuranWordData.irabForWord(15, 7, lookup),
          'حَرْفُ عَرْضٍ مَبْنِيٌّ عَلَى السُّكُونِ.');
    });

    test('15:7 مَا — combined لَوْمَا sarf + irab on both words', () async {
      final idx = wordIndexOf(15, 7, 'ما');
      expect(idx, isNot(-1));
      final lookup = buildQcfWordMap(15, 7).words[idx].lookupText;
      expect(await QuranWordData.sarfForWord(15, 7, lookup),
          '{لَوْمَا}: حَرْفٌ مَبْنِيٌّ.');
      expect(await QuranWordData.irabForWord(15, 7, lookup),
          'حَرْفُ عَرْضٍ مَبْنِيٌّ عَلَى السُّكُونِ.');
    });

    test('sarf is shown FULL, never shortened (2:7 w9 > 160 chars)',
        () async {
      final idx = wordIndexOf(2, 7, 'غشاوه');
      expect(idx, isNot(-1));
      final lookup = buildQcfWordMap(2, 7).words[idx].lookupText;
      final text = await QuranWordData.sarfForWord(2, 7, lookup);
      expect(text, '{غِشَاوَةٌ}: اسْمٌ، مُؤَنَّثٌ، مُفْرَدٌ، جَامِدٌ، مَصْدَرٌ سَمَاعِيٌّ، مِنَ الْفِعْلِ الثُّلَاثِيِّ: (غَشِيَ يَغْشَى)، مِنْ بَابِ: (عَلِمَ يَعْلَمُ)، ثُلَاثِيٌّ مَزِيدٌ بِحَرْفَيْنِ: الْأَلِفِ وَالتَّاءِ، أَصْلُهُ: (غِشَايَةٌ)، عَلَى وَزْنِ: (فِعَالَةٌ)، فِيهِ إِعْلَالٌ بِقَلْبِ حَرْفِ: الْيَاءِ هَمْزَةً لِمَجِيئِهَا مُتَحَرِّكَةً بَعْدَ الْأَلِفِ، مِنْ مَادَّةِ: (غشي).');
      expect(text!.length, 372);
      expect(text.length, greaterThan(160));
    });

    test('entries: 2:7 has 12 pairs; 15:7 has 8 (لوما duplicated)',
        () async {
      expect(
          (await QuranWordData.tafsirCenterSarfEntriesForAyah(2, 7))
              .length,
          12);
      expect(
          (await QuranWordData.tafsirCenterIrabEntriesForAyah(2, 7))
              .length,
          12);
      expect(
          (await QuranWordData.tafsirCenterSarfEntriesForAyah(15, 7))
              .length,
          8);
      expect(
          (await QuranWordData.tafsirCenterIrabEntriesForAyah(15, 7))
              .length,
          8);
    });

    test('coverage: sarf + irab cover every display word (100%)',
        () async {
      final stats = await QuranWordData.sarfIrabCoverageStats();
      // Display words (QCF) = 77,433, not the 77,429 morphology
      // entries: the morphology file merges 4 phrases into one
      // entry each (see sarfIrabCoverageStats).
      expect(stats.total, 77433);
      expect(stats.withSarf, 77433);
      expect(stats.withIrab, 77433);
    });

    // Regression: 35:43 word 9 ٱلسَّيِّئُ — the last unmatched
    // display word in the Mushaf. The asset spells it with ya +
    // hamza-above (ئ) while the QCF text uses precomposed ئ;
    // normalizeArabic must unify them or the card shows the
    // fallback for this word. Found by the full-corpus coverage
    // scan (was 77,432/77,433 before the fix). Word 5 of the
    // same ayah is the SAME bare word in the genitive
    // (ٱلسَّيِّئِ) — the final-vowel tie-break in _matchWord
    // must pick THIS (nominative) entry, not word 5's.
    test('35:43 word 9: hamza-above seat (ئ) matches QCF ئ',
        () async {
      final words = buildQcfWordMap(35, 43).words;
      final lookup = words[8].lookupText;
      expect(QuranWordData.normalizeArabic(lookup), 'السيئ');
      final sarf = await QuranWordData.sarfForWord(35, 43, lookup);
      final irab = await QuranWordData.irabForWord(35, 43, lookup);
      expect(sarf, '{السَّيِّئُ}: اسْمٌ، مُذَكَّرٌ، مُفْرَدٌ، مُشْتَقٌّ، صِفَةٌ مُشَبَّهَةٌ، مِنَ الْفِعْلِ الثُّلَاثِيِّ: (سَاءَ يَسُوءُ)، مِنْ بَابِ: (نَصَرَ يَنْصُرُ)، ثُلَاثِيٌّ مَزِيدٌ بِحَرْفِ: الْيَاءِ، أَصْلُهُ: (سَيوِأٌ)، عَلَى وَزْنِ: (فَيْعِلٌ)، فِيهِ إِعْلَالٌ بِقَلْبِ حَرْفِ: الْوَاوِ يَاءً لِمَجِيءِ الْوَاوِ بَعْدَ يَاءٍ سَاكِنَةٍ، وَفِيهِ إِدْغَامُ حَرْفَيْنِ مُتَمَاثِلَيْنِ سَاكِنٍ وَمُتَحَرِّكٍ، مِنْ مَادَّةِ: (سوأ).');
      expect(irab, 'نَعْتٌ مَرْفُوعٌ وَعَلَامَةُ رَفْعِهِ الضَّمَّةُ الظَّاهِرَةُ.');
      expect(await QuranWordData.sarfSourceForWord(35, 43, lookup),
          'tafsircenter');
      expect(await QuranWordData.irabSourceForWord(35, 43, lookup),
          'tafsircenter');
    });
  });

  group('word card sarf/irab tabs (v13.11)', () {
    /// 411dp logical width, the user's phone.
    void set411(WidgetTester tester) {
      tester.view.physicalSize = const Size(411, 914);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

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
                  onOpenNotesScreen: () {},
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

    testWidgets('3:7 مُّحْكَمَاتٌ: التصريف + الإعراب show the TC texts '
        '+ credit line', (tester) async {
      set411(tester);
      await openCard(tester);
      await tester.tap(find.byKey(const ValueKey('tabSarf')));
      await tester.pump();
      expect(find.textContaining('مُفْرَدُهُ: (مُحْكَمَةٌ)'), findsOneWidget);
      expect(
          find.text('المصدر: مركز تفسير للدراسات القرآنية — tafsir.net'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tabIrab')));
      await tester.pump();
      expect(find.textContaining('نَعْتٌ مَرْفُوعٌ'), findsOneWidget);
      expect(
          find.text('المصدر: مركز تفسير للدراسات القرآنية — tafsir.net'),
          findsOneWidget);
      // The simplified disclaimer is gone for TC-covered words.
      expect(find.textContaining('الإعراب هنا مبسّط'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('15:11 يَسْتَهْزِئُونَ: التصريف + الإعراب show the TC '
        'texts', (tester) async {
      set411(tester);
      final idx = wordIndexOf(15, 11, 'يستهزءون');
      expect(idx, isNot(-1));
      await openCard(tester, surah: 15, verse: 11, wordIndex: idx);
      await tester.tap(find.byKey(const ValueKey('tabSarf')));
      await tester.pump();
      expect(find.textContaining('مِنْ بَابِ: (اسْتَفْعَلَ)'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tabIrab')));
      await tester.pump();
      expect(find.textContaining('فِعْلٌ مُضَارِعٌ مَرْفُوعٌ'), findsOneWidget);
      expect(
          find.text('المصدر: مركز تفسير للدراسات القرآنية — tafsir.net'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
