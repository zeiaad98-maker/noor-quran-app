import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class SurahReaderScreen extends StatefulWidget {
  final int surahNumber;
  final int? initialPage;

  const SurahReaderScreen({
    super.key,
    required this.surahNumber,
    this.initialPage,
  });

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  late PageController _pageController;
  late int _currentPage;
  double _fontSize = 21.5;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage ?? quran.getPageNumber(widget.surahNumber, 1);
    _pageController = PageController(initialPage: _currentPage - 1);
    _saveLastRead(_currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _saveLastRead(int page) async {
    final prefs = await SharedPreferences.getInstance();
    final pageData = quran.getPageData(page);
    final firstSurahOnPage = pageData.isNotEmpty ? pageData.first['surah'] as int : widget.surahNumber;
    await prefs.setInt('last_page', page);
    await prefs.setInt('last_surah', firstSurahOnPage);
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
    final appState = NoorQuranApp.of(context);
    final isDark = appState?.isDarkMode ?? false;
    final pageData = quran.getPageData(_currentPage);
    final currentSurah = pageData.isNotEmpty ? pageData.first['surah'] as int : widget.surahNumber;
    final currentJuz = pageData.isNotEmpty
        ? quran.getJuzNumber(currentSurah, pageData.first['start'] as int)
        : 1;

    final paperColor = isDark ? const Color(0xFF171C1A) : const Color(0xFFFFFDF7);
    final borderColor = isDark ? const Color(0xFF2E6F5B) : const Color(0xFFC5A059);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              'سورة ${quran.getSurahNameArabic(currentSurah)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'الجزء ${_toArabicNumbers(currentJuz)}  •  صفحة ${_toArabicNumbers(_currentPage)} من ٦٠٤',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () => appState?.toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.text_decrease_rounded),
            onPressed: () {
              if (_fontSize > 16) setState(() => _fontSize -= 1.5);
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_increase_rounded),
            onPressed: () {
              if (_fontSize < 30) setState(() => _fontSize += 1.5);
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: 604,
        onPageChanged: (index) {
          final newPage = index + 1;
          setState(() => _currentPage = newPage);
          _saveLastRead(newPage);
        },
        itemBuilder: (context, index) {
          final pageNumber = index + 1;
          return _buildMushafPage(context, pageNumber, paperColor, borderColor, isDark);
        },
      ),
    );
  }

  Widget _buildMushafPage(
    BuildContext context,
    int pageNumber,
    Color paperColor,
    Color borderColor,
    bool isDark,
  ) {
    final segments = quran.getPageData(pageNumber);
    final isCenteredPage = pageNumber == 1 || pageNumber == 2; // الفاتحة وأول البقرة في المنتصف

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Container(
          decoration: BoxDecoration(
            color: paperColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 2.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor.withValues(alpha: 0.5), width: 1),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Column(
                        mainAxisAlignment: isCenteredPage ? MainAxisAlignment.center : MainAxisAlignment.start,
                        children: segments.map((seg) {
                          final int surah = seg['surah'];
                          final int startVerse = seg['start'];
                          final int endVerse = seg['end'];
                          final bool isSurahStart = startVerse == 1;
                          final bool showBasmala = isSurahStart && surah != 1 && surah != 9;

                          return Column(
                            children: [
                              if (isSurahStart) _buildSurahHeaderBanner(surah, borderColor, isDark),
                              if (showBasmala)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                                  child: Text(
                                    quran.basmala,
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.amiriQuran(
                                      fontSize: _fontSize + 1,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? const Color(0xFF4FD1A5) : const Color(0xFF0D6E52),
                                    ),
                                  ),
                                ),
                              RichText(
                                textAlign: isCenteredPage ? TextAlign.center : TextAlign.justify,
                                textDirection: TextDirection.rtl,
                                text: TextSpan(
                                  style: GoogleFonts.amiriQuran(
                                    fontSize: isCenteredPage ? _fontSize + 2 : _fontSize,
                                    height: 2.05,
                                    color: isDark ? const Color(0xFFECECEC) : const Color(0xFF1A1A1A),
                                  ),
                                  children: List.generate(endVerse - startVerse + 1, (i) {
                                    final verseNum = startVerse + i;
                                    final verseText = quran.getVerse(surah, verseNum);
                                    return TextSpan(
                                      children: [
                                        TextSpan(text: '$verseText '),
                                        TextSpan(
                                          text: '﴿${_toArabicNumbers(verseNum)}﴾ ',
                                          style: TextStyle(
                                            fontFamily: 'sans-serif',
                                            fontSize: _fontSize * 0.78,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF0D6E52),
                                          ),
                                        ),
                                      ],
                                    );
                                  }),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                // تذييل رقم الصفحة أسفل إطار المصحف
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: borderColor.withValues(alpha: 0.35))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '— ${_toArabicNumbers(pageNumber)} —',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF0D6E52),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSurahHeaderBanner(int surah, Color borderColor, bool isDark) {
    final surahName = quran.getSurahNameArabic(surah);
    final place = quran.getPlaceOfRevelation(surah) == 'Makkah' ? 'مكية' : 'مدنية';
    final count = _toArabicNumbers(quran.getVerseCount(surah));

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6, bottom: 10),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1F3A32), const Color(0xFF152923)]
              : [const Color(0xFFF3EAD3), const Color(0xFFE9DCB9)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'آياتها: $count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF4A3B1C),
            ),
          ),
          Text(
            'سُورَةُ $surahName',
            style: GoogleFonts.amiriQuran(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF0D6E52),
            ),
          ),
          Text(
            place,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF4A3B1C),
            ),
          ),
        ],
      ),
    );
  }
}
