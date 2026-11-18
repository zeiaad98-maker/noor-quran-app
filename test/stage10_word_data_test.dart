import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/ayah_notes.dart';
import 'package:noor_quran/data/word_meanings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('word data loads and matches known words', () async {
    await QuranWordData.ensureLoaded();

    // 2:7 — خَتَمَ: مخلوف (v13.6) glosses the phrase «خَتَمَ اللَّهُ»
    // as «طبع الله»; غِشَاوَةٌ too.
    final m1 = await QuranWordData.meaningForWord(2, 7, 'خَتَمَ');
    expect(m1, isNotNull);
    expect(m1, 'طبع الله');
    expect(await QuranWordData.glossSourceForWord(2, 7, 'خَتَمَ'),
        'makhloof');

    final m2 = await QuranWordData.meaningForWord(2, 7, 'غِشَاوَةٌ');
    expect(m2, isNotNull);

    // Common word with no special meaning -> null (fallback path).
    final m3 = await QuranWordData.meaningForWord(2, 7, 'عَلَىٰ');
    expect(m3, isNull);

    // Tafsir Muyassar covers every ayah.
    final t = await QuranWordData.tafsirForAyah(1, 1);
    expect(t, isNotNull);
    expect(t, contains('باسم الله'));

    // Simplified morphology for 2:7 خَتَمَ mentions its root.
    final morph = await QuranWordData.morphForWord(2, 7, 'خَتَمَ');
    expect(morph, isNotNull);
    expect(morph, contains('ختم'));
  });

  test('hizb quarter labels are correct', () async {
    expect(await QuranWordData.hizbQuarterLabel(1, 1),
        'الربع الأول من الحزب 1');
    // 2:26 starts the second quarter of juz 1 (hizb 1).
    expect(await QuranWordData.hizbQuarterLabel(2, 26),
        'الربع الثاني من الحزب 1');
    // 2:74 is the last ayah of the fourth quarter of hizb 1;
    // 2:75 starts hizb 2.
    expect(await QuranWordData.hizbQuarterLabel(2, 74),
        'الربع الرابع من الحزب 1');
    expect(await QuranWordData.hizbQuarterLabel(2, 75),
        'الربع الأول من الحزب 2');
  });

  test('ayah note key format', () {
    expect(AyahNotes.keyFor(2, 255), 'ayah_note_2_255');
    expect(AyahNotes.idFor(2, 255), '2:255');
  });
}
