import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;

import 'surah_name_image.dart';

/// v13.20 — in-reader jump pickers.
///
/// The user asked (Fri 2026-11-20) for SurahApp-style navigation
/// inside the reader: tap the surah name in the header to pick any
/// of the 114 surahs, tap the page chip to pick any of the 604 pages.
/// Both sheets stay inside the reader — they close and jump the
/// CURRENT reader via [onSelect]; they never push a new screen and
/// never leave the app.

/// Total Mushaf pages (Madina Mushaf).
const int mushafPageCount = 604;

/// Total surahs.
const int surahCount = 114;

const Color _emerald = Color(0xFF0D6E52);

/// True when [page] is a real Mushaf page (1..604). The reader's
/// `_jumpToPage` uses this as its guard.
bool isValidMushafPage(int page) => page >= 1 && page <= mushafPageCount;

/// First page of [surah] (1..114).
int surahStartPage(int surah) => quran.getPageNumber(surah, 1);

/// Western digits → Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩), the style the
/// reader already uses for its page number.
String arabicDigits(int number) => '$number'.replaceAllMapped(
      RegExp(r'\d'),
      (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)],
    );

/// Small drag handle shown at the top of both sheets.
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 6),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Bottom sheet listing all 114 surahs.
///
/// Row: number circle, calligraphy name, "مكية/مدنية • N آية •
/// صفحة M". A search field filters by name or number (same rule as
/// the surah-list tab). The current surah is highlighted and the
/// list opens scrolled to it. Tapping a row calls [onSelect] with
/// the surah number — the caller pops the sheet and jumps.
class SurahJumpSheet extends StatefulWidget {
  final int currentSurah;
  final void Function(int surah) onSelect;

  const SurahJumpSheet({
    super.key,
    required this.currentSurah,
    required this.onSelect,
  });

  @override
  State<SurahJumpSheet> createState() => _SurahJumpSheetState();
}

class _SurahJumpSheetState extends State<SurahJumpSheet> {
  static const double _rowHeight = 76;

  String _searchQuery = '';
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Open scrolled to the current surah (rows are a fixed height,
    // so the offset is exact).
    _scrollController = ScrollController(
      initialScrollOffset: (widget.currentSurah - 1) * _rowHeight,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final allSurahs = List.generate(surahCount, (index) => index + 1);
    final filteredSurahs = allSurahs.where((surahNum) {
      if (_searchQuery.isEmpty) return true;
      final nameAr = quran.getSurahNameArabic(surahNum);
      return nameAr.contains(_searchQuery) ||
          surahNum.toString() == _searchQuery;
    }).toList();

    return Column(
      children: [
        const _SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'اختر السورة',
            style: GoogleFonts.amiri(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: _emerald,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'ابحث باسم السورة أو رقمها...',
              prefixIcon: const Icon(Icons.search_rounded, color: _emerald),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _emerald, width: 1.8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
        ),
        Expanded(
          child: filteredSurahs.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد سورة مطابقة',
                    style: TextStyle(fontSize: 15),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: filteredSurahs.length,
                  itemBuilder: (context, index) {
                    final surahNum = filteredSurahs[index];
                    final verseCount = quran.getVerseCount(surahNum);
                    final pageNum = surahStartPage(surahNum);
                    final place =
                        quran.getPlaceOfRevelation(surahNum) == 'Makkah'
                            ? 'مكية'
                            : 'مدنية';
                    final isCurrent = surahNum == widget.currentSurah;
                    return Container(
                      key: ValueKey('surahRow_$surahNum'),
                      height: _rowHeight,
                      color: isCurrent
                          ? _emerald.withValues(alpha: 0.10)
                          : null,
                      child: InkWell(
                        onTap: () => widget.onSelect(surahNum),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    _emerald.withValues(alpha: 0.15),
                                child: Text(
                                  '$surahNum',
                                  style: const TextStyle(
                                    color: _emerald,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SurahNameImage(
                                      surahNumber: surahNum,
                                      height: 48,
                                      cropPadding: true,
                                      isDark: isDark,
                                    ),
                                    Text(
                                      '$place • $verseCount آية • صفحة $pageNum',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isCurrent)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: _emerald,
                                ),
                            ],
                          ),
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

/// Bottom sheet with a grid of all 604 Mushaf page numbers.
///
/// The current page cell is filled green; the grid opens scrolled so
/// the current page is visible. Tapping a cell calls [onSelect] with
/// the page number — the caller pops the sheet and jumps.
class PageJumpSheet extends StatefulWidget {
  final int currentPage;
  final void Function(int page) onSelect;

  const PageJumpSheet({
    super.key,
    required this.currentPage,
    required this.onSelect,
  });

  @override
  State<PageJumpSheet> createState() => _PageJumpSheetState();
}

class _PageJumpSheetState extends State<PageJumpSheet> {
  static const int _columns = 6;
  static const double _cellHeight = 52;
  static const double _spacing = 8;
  static const double _padding = 12;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Rows are a fixed pitch (cell + spacing), so the offset that
    // puts the current page's row at the top is exact. The scroll
    // position clamps itself when the last rows cannot reach the top.
    final row = (widget.currentPage - 1) ~/ _columns;
    _scrollController = ScrollController(
      initialScrollOffset: _padding + row * (_cellHeight + _spacing),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'اختر الصفحة',
            style: GoogleFonts.amiri(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: _emerald,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(_padding),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _columns,
              mainAxisExtent: _cellHeight,
              crossAxisSpacing: _spacing,
              mainAxisSpacing: _spacing,
            ),
            itemCount: mushafPageCount,
            itemBuilder: (context, index) {
              final page = index + 1;
              final isCurrent = page == widget.currentPage;
              return Ink(
                key: ValueKey('pageCell_$page'),
                decoration: BoxDecoration(
                  color: isCurrent ? _emerald : null,
                  border: Border.all(
                    color: isCurrent ? _emerald : Colors.grey.withValues(
                        alpha: 0.5,
                      ),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => widget.onSelect(page),
                  child: Center(
                    child: Text(
                      arabicDigits(page),
                      style: GoogleFonts.amiri(
                        fontSize: 17,
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
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
