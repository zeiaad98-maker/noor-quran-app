import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/ayah_notes.dart';
import 'package:noor_quran/data/word_meanings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('word data loads and matches known words', () async {
    await QuranWordData.ensureLoaded();

    // 2:7 — خَتَمَ: v13.11, the Tafsir Center meaning (first source),
    // shown in full — the dictionary-style entry on the ختم root.
    // (v13.6: مخلوف glossed the phrase «خَتَمَ اللَّهُ» as «طبع الله»;
    // that gloss is now fallback-only.)
    final m1 = await QuranWordData.meaningForWord(2, 7, 'خَتَمَ');
    expect(m1, isNotNull);
    expect(
        m1,
        'الخاء والتاء والميم أصلٌ واحد، وهو بلوغ آخر الشيء. '
        'يُقال ختمت العمل، وختم القارئ السورة. فأما الختم، وهو الطبع '
        'على الشيء، فذلك من الباب أيضا; لأن الطبع على الشيء لا يكون '
        'إلا بعد بلوغ آخره، والمراد: طبع عليها وجعلها لا تعقل شيئاً، '
        'ولا ينفذ إليها الإيمان.');
    expect(await QuranWordData.glossSourceForWord(2, 7, 'خَتَمَ'),
        'tafsircenter');

    final m2 = await QuranWordData.meaningForWord(2, 7, 'غِشَاوَةٌ');
    expect(m2, isNotNull);

    // v13.11: عَلَىٰ has a Tafsir Center meaning too («حرف جر، يفيد
    // معنى الاستعلاء») — it no longer falls through to null.
    final m3 = await QuranWordData.meaningForWord(2, 7, 'عَلَىٰ');
    expect(m3, 'حرف جر، يفيد معنى الاستعلاء');

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
