import 'package:flutter/material.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

class SurahReaderScreen extends StatefulWidget {
  final int surahNumber;

  const SurahReaderScreen({super.key, required this.surahNumber});

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  double _fontSize = 24.0;

  @override
  void initState() {
    super.initState();
    _saveLastRead();
  }

  Future<void> _saveLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_surah', widget.surahNumber);
  }

  String _toArabicNumbers(int number) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String numStr = number.toString();
    for (int i = 0; i < english.length; i++) {
      numStr = numStr.replaceAll(english[i], arabic[i]);
    }
    return numStr;
  }

  @override
  Widget build(BuildContext context) {
    final surahName = quran.getSurahNameArabic(widget.surahNumber);
    final verseCount = quran.getVerseCount(widget.surahNumber);
    final showBasmala = widget.surahNumber != 1 && widget.surahNumber != 9;

    return Scaffold(
      appBar: AppBar(
        title: Text('سورة $surahName', style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.text_decrease_rounded),
            tooltip: 'تصغير الخط',
            onPressed: () {
              if (_fontSize > 18) setState(() => _fontSize -= 2);
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_increase_rounded),
            tooltip: 'تكبير الخط',
            onPressed: () {
              if (_fontSize < 38) setState(() => _fontSize += 2);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          if (showBasmala)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                quran.basmala,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _fontSize + 2,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          RichText(
            textAlign: TextAlign.justify,
            textDirection: TextDirection.rtl,
            text: TextSpan(
              style: TextStyle(
                fontSize: _fontSize,
                height: 2.0,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              children: List.generate(verseCount, (index) {
                final verseNumber = index + 1;
                final verseText = quran.getVerse(widget.surahNumber, verseNumber);
                return TextSpan(
                  children: [
                    TextSpan(text: '$verseText '),
                    TextSpan(
                      text: '﴿${_toArabicNumbers(verseNumber)}﴾ ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: _fontSize * 0.85,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
