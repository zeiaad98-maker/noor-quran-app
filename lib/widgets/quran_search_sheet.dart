import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran/quran.dart' as quran;
import '../screens/surah_reader_screen.dart';

class QuranSearchView extends StatefulWidget {
  /// إذا مررنا هذه الدالة (من داخل القارئ) ينتقل للصفحة مباشرة، وإلا يفتح القارئ جديداً
  final void Function(int page)? onSelectPage;

  const QuranSearchView({super.key, this.onSelectPage});

  @override
  State<QuranSearchView> createState() => _QuranSearchViewState();
}

class _QuranSearchViewState extends State<QuranSearchView> {
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _hasSearched = false;

  /// إزالة التشكيل وتوحيد الحروف العربية لتسهيل البحث بدون تشكيل
  String _normalizeArabic(String text) {
    return text
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '') // إزالة التشكيل وعلامات الوقف
        .replaceAll('ٱ', 'ا')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه')
        .trim();
  }

  void _performSearch(String rawQuery) {
    final query = _normalizeArabic(rawQuery);
    if (query.length < 2) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    final List<Map<String, dynamic>> matches = [];
    for (int surah = 1; surah <= 114; surah++) {
      final verseCount = quran.getVerseCount(surah);
      for (int verse = 1; verse <= verseCount; verse++) {
        final originalVerse = quran.getVerse(surah, verse);
        if (_normalizeArabic(originalVerse).contains(query)) {
          matches.add({
            'surah': surah,
            'verse': verse,
            'text': originalVerse,
            'page': quran.getPageNumber(surah, verse),
          });
          if (matches.length >= 100) break; // حد أقصى 100 نتيجة لسرعة الأداء
        }
      }
      if (matches.length >= 100) break;
    }

    setState(() {
      _results = matches;
      _hasSearched = true;
    });
  }

  String _toArabicDigits(int number) {
    const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    String res = number.toString();
    for (int i = 0; i < 10; i++) {
      res = res.replaceAll(en[i], ar[i]);
    }
    return res;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFB8934A);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: TextField(
            controller: _controller,
            autofocus: widget.onSelectPage != null,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'اكتب كلمة أو جزءاً من آية (بدون تشكيل)...',
              prefixIcon: const Icon(Icons.search_rounded, color: emerald),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _controller.clear();
                        _performSearch('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: emerald, width: 1.8),
              ),
            ),
            onChanged: _performSearch,
          ),
        ),
        if (_hasSearched)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              children: [
                Text(
                  _results.isEmpty
                      ? 'لا توجد نتائج مطابقة'
                      : 'النتائج المطابقة: ${_toArabicDigits(_results.length)}${_results.length == 100 ? '+' : ''}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: gold),
                ),
              ],
            ),
          ),
        Expanded(
          child: !_hasSearched
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.manage_search_rounded, size: 64, color: gold.withValues(alpha: 0.6)),
                      const SizedBox(height: 10),
                      const Text(
                        'ابحث في آيات القرآن الكريم بالكلمة',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final int surah = item['surah'];
                    final int verse = item['verse'];
                    final int page = item['page'];
                    final String text = item['text'];

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        if (widget.onSelectPage != null) {
                          widget.onSelectPage!(page);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SurahReaderScreen(
                                surahNumber: surah,
                                initialPage: page,
                              ),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: emerald.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'سورة ${quran.getSurahNameArabic(surah)} • آية ${_toArabicDigits(verse)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: emerald,
                                    ),
                                  ),
                                ),
                                Text(
                                  'صفحة ${_toArabicDigits(page)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: gold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              text,
                              textDirection: TextDirection.rtl,
                              style: GoogleFonts.amiriQuran(
                                fontSize: 19,
                                height: 1.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
