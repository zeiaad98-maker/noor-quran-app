import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/surah_sciences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('surah info: 114 surahs, Fatiha + Baqarah fields', () async {
    final fatiha = await SurahSciences.infoForSurah(1);
    expect(fatiha, isNotNull);
    expect(fatiha!.nameAr, 'الفاتحة');
    expect(fatiha.revelationPlaceAr, 'مكية');
    expect(fatiha.revelationOrder, 5);
    expect(fatiha.ayahCount, 7);
    expect(fatiha.pageStart, 1);
    expect(fatiha.pageEnd, 1);

    final baqarah = await SurahSciences.infoForSurah(2);
    expect(baqarah, isNotNull);
    expect(baqarah!.nameAr, 'البقرة');
    expect(baqarah.revelationPlaceAr, 'مدنية');
    expect(baqarah.revelationOrder, 87);
    expect(baqarah.ayahCount, 286);
    expect(baqarah.pageStart, 2);
    expect(baqarah.pageEnd, 49);

    // All 114 present.
    var count = 0;
    for (var s = 1; s <= 114; s++) {
      if (await SurahSciences.infoForSurah(s) != null) count++;
    }
    expect(count, 114);
  });

  test('surah sciences: all 114 surahs (Bug H)', () async {
    final fatiha = await SurahSciences.scienceForSurah(1);
    expect(fatiha, isNotNull);
    expect(fatiha!.names, contains('أم القرآن'));
    expect(fatiha.names!.length, 15);
    expect(fatiha.maqsadShort, 'مراقبة العباد لربهم');
    expect(fatiha.fadailHadith, contains('أَبشر بنورين'));

    final baqarah = await SurahSciences.scienceForSurah(2);
    expect(baqarah, isNotNull);
    expect(baqarah!.names, contains('الزهراء'));
    expect(baqarah.maqsadVerbatim, isNotNull);
    expect(baqarah.fadailHadith, contains('لا تجعلوا بيوتكم مقابر'));
    // Bug H fix: the sample headline swallowed raw page text; it is now
    // just the bullet text.
    expect(baqarah.fadailHeadline,
        'البيت الذي تقرأ فيه سورة البقرة لا يدخله الشيطان بل ينفر ويفر منه ويخرج إذا كان فيه');

    // Every surah now has an entry (no more "لم تستخرج" placeholder).
    var withNames = 0;
    var withMaqsad = 0;
    var withFadail = 0;
    for (var s = 1; s <= 114; s++) {
      final sci = await SurahSciences.scienceForSurah(s);
      expect(sci, isNotNull, reason: 'surah $s has no science entry');
      if (sci!.names != null && sci.names!.isNotEmpty) withNames++;
      if (sci.maqsadVerbatim != null && sci.maqsadVerbatim!.isNotEmpty) {
        withMaqsad++;
      }
      if (sci.fadailHeadline != null && sci.fadailHeadline!.isNotEmpty) {
        withFadail++;
      }
    }
    expect(withNames, 41);
    expect(withMaqsad, 114);
    expect(withFadail, 114);

    // Spot checks from the extraction.
    final imran = await SurahSciences.scienceForSurah(3);
    expect(imran!.names, contains('الزهراء'));
    expect(imran.maqsadShort, 'التوحيد');

    final tawbah = await SurahSciences.scienceForSurah(9);
    expect(tawbah!.names, contains('الفاضحة'));
    expect(tawbah.names, isNot(contains('الفاتحة')));

    final qaf = await SurahSciences.scienceForSurah(50);
    expect(qaf!.fadailHeadline, contains('يستحب قراءتها على المنبر'));

    // A باب whose whole content is "لم يصح ... سوى أنها من المفصل".
    final buruj = await SurahSciences.scienceForSurah(85);
    expect(buruj!.fadailHeadline, contains('لم يصح'));

    // A surah with no باب in the موسوعة carries the honest note.
    final naml = await SurahSciences.scienceForSurah(27);
    expect(naml!.fadailHeadline, contains('لم يفرد لها المؤلف باباً'));

    // A surah where Baqa'i lists no other names carries the honest note.
    final nas = await SurahSciences.scienceForSurah(114);
    expect(nas!.names, isEmpty);
    expect(nas.namesVerbatim, contains('لم يذكر البقاعي'));
    expect(nas.maqsadShort, 'الاعتصام بالِإله الحق، من شر الخلق الباطن');
  });

  test('asbab al-nuzul: 2:97 found, ayah with none is empty', () async {
    final asbab297 = await SurahSciences.asbabForAyah(2, 97);
    expect(asbab297, isNotEmpty);
    expect(asbab297.first, contains('جِبْرِيلُ'));
    // 2:1 has no recorded sabab in the dataset.
    expect(await SurahSciences.asbabForAyah(2, 1), isEmpty);
  });

  test('surah stats: Fatiha 29 words / 145 letters; total 77433', () {
    // Letters count the dagger alef (ٰ) as a letter, so Fatiha is
    // 145 here vs the commonly quoted 139 (which drops the 6 dagger
    // alefs). Words are the true Uthmani words (QCF map): Baqarah
    // is 6117 here vs the quoted 6121, which adds the 4 Basmalah
    // words — the Basmalah is a separate Mushaf line, not part of
    // 2:1 in the bundled text.
    final fatiha = SurahSciences.statsForSurah(1);
    expect(fatiha.ayahCount, 7);
    expect(fatiha.wordCount, 29);
    expect(fatiha.letterCount, 145);

    final baqarah = SurahSciences.statsForSurah(2);
    expect(baqarah.ayahCount, 286);
    expect(baqarah.wordCount, 6117);

    var total = 0;
    for (var s = 1; s <= 114; s++) {
      total += SurahSciences.statsForSurah(s).wordCount;
    }
    expect(total, 77433);
  });
}
