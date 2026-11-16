import 'package:flutter_test/flutter_test.dart';
import 'package:noor_quran/data/quran_audio.dart';

void main() {
  test('15 reciters, unique names, all fields filled', () {
    expect(reciters.length, 15);
    final names = reciters.map((r) => r.name).toSet();
    expect(names.length, 15);
    for (final r in reciters) {
      expect(r.server, isNotEmpty);
      expect(r.everyayah, isNotEmpty);
    }
    // No Muhammad Ayyub: he has no everyayah folder, so he stays out.
    expect(names.contains('محمد أيوب'), isFalse);
  });

  test('everyayah + mp3quran URL builders', () {
    final husary = reciters.firstWhere((r) => r.name == 'محمود الحصري');
    expect(everyayahUrl(husary, 2, 7),
        'https://everyayah.com/data/Husary_64kbps/002007.mp3');
    expect(mp3quranSurahUrl(husary, 1),
        'https://cdn.mp3quran.net/audio/mahmoud-husary/r1/001.mp3');
    final suwaid = reciters.firstWhere((r) => r.name == 'أيمن سويد');
    expect(mp3quranSurahUrl(suwaid, 1),
        'https://server15.mp3quran.net/a-rushdi/Almusshaf-Al-Mo-lim/001.mp3');
    // Ibrahim Akhdar uses the working 32kbps folder, not the broken 64kbps.
    final akhdar = reciters.firstWhere((r) => r.name == 'إبراهيم الأخضر');
    expect(akhdar.everyayah, 'Ibrahim_Akhdar_32kbps');
  });

  test('Quran.com ayah audio URLs (word-segment source)', () {
    final afasy = reciters.firstWhere((r) => r.name == 'مشاري العفاسي');
    expect(quranComAyahUrl(afasy, 2, 7),
        'https://verses.quran.com/Alafasy/mp3/002007.mp3');
    final husary = reciters.firstWhere((r) => r.name == 'محمود الحصري');
    expect(quranComAyahUrl(husary, 2, 7),
        'https://mirrors.quranicaudio.com/everyayah/Husary_64kbps/002007.mp3');
    // Reciters without a Quran.com recitation have no segments URL.
    final maher = reciters.firstWhere((r) => r.name == 'ماهر المعيقلي');
    expect(maher.quranComRecitationId, isNull);
    expect(quranComAyahUrl(maher, 2, 7), isNull);
    expect(wbwWordUrl(2, 7, 1),
        'https://verses.quran.com/wbw/002_007_001.mp3');
  });

  test('page / surah ayah lists', () {
    // Page 1: Fatiha 1-7.
    expect(ayahsOfPage(1).length, 7);
    expect(ayahsOfPage(1).first, (1, 1));
    expect(ayahsOfPage(1).last, (1, 7));
    expect(ayahsOfSurah(112).length, 4);
    expect(ayahsOfPages(1, 1).length, 7);
  });
}
