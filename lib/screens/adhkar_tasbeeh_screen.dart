import 'dart:math' as math;

import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import '../data/adhkar_data.dart';
import 'tasbeeh_screen.dart';

/// شاشة الأذكار والمسبحة — تبويبان:
/// 0 = الأذكار (حصن المسلم كاملاً: 132 باباً، 267 ذكراً ودعاءً)
/// 1 = المسبحة (عداد التسبيح)
///
/// v13.3 (FIX C): التصميم الجديد كما في العينات المعتمدة
/// (sample-v133-adhkar-list.png و sample-v133-adhkar-dhikr.png):
/// * ترويسة كحلية (حصن المسلم بالذهبي) وتبويبان نصيّان.
/// * أذكار الصباح وأذكار المساء بابان منفصلان، أوّل القائمة.
/// * كل ذكر لحاله (صفحة واحدة، تمرير أفقي + السابق/التالي)،
///   والضغط عليه يُظهر العدّ (منجز/العدد) بدائرة كبيرة.
/// المحتوى نفسه من حصن المسلم حرفياً — لم يتغير منه حرف.

const _navy = Color(0xFF1A365D);
const _gold = Color(0xFFC59B27);
const _emerald = Color(0xFF0D6E52);
const _ivory = Color(0xFFFAF8F5);

class AdhkarTasbeehScreen extends StatefulWidget {
  final int initialTab;

  const AdhkarTasbeehScreen({super.key, this.initialTab = 0});

  @override
  State<AdhkarTasbeehScreen> createState() => _AdhkarTasbeehScreenState();
}

class _AdhkarTasbeehScreenState extends State<AdhkarTasbeehScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Navy banner (sample): حصن المسلم in gold + the book's counts.
        // Kept compact on purpose: the المسبحة tab is a fixed-height
        // column, and a tall banner pushes its vibration row behind
        // the bottom nav on a 411x919 phone (tasbeeh_fit_test).
        Container(
          width: double.infinity,
          color: _navy,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            children: [
              Text(
                'حصن المسلم',
                style: GoogleFonts.amiri(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: _gold,
                ),
              ),
              Text(
                '${_toArabicDigits('${adhkarCategories.length}')} باباً و ${_toArabicDigits('267')} ذكراً',
                style: GoogleFonts.amiri(
                    fontSize: 15, color: Colors.white),
              ),
              const SizedBox(height: 6),
              _goldDivider(),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          indicatorColor: _gold,
          indicatorWeight: 3,
          labelColor: isDark ? Colors.white : _navy,
          unselectedLabelColor: Colors.grey,
          labelStyle: GoogleFonts.amiri(
              fontSize: 17, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.amiri(fontSize: 17),
          tabs: const [
            Tab(text: 'الأذكار'),
            Tab(text: 'المسبحة'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              AdhkarCategoriesView(),
              TasbeehScreen(),
            ],
          ),
        ),
      ],
    );
  }
}

/// Gold divider with a centre diamond (the sample's ornament).
Widget _goldDivider() {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 60, height: 2, color: _gold),
      const SizedBox(width: 8),
      Transform.rotate(
        angle: math.pi / 4,
        child: Container(width: 8, height: 8, color: _gold),
      ),
      const SizedBox(width: 8),
      Container(width: 60, height: 2, color: _gold),
    ],
  );
}

String _toArabicDigits(String input) {
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  String res = input;
  for (int i = 0; i < 10; i++) {
    res = res.replaceAll(en[i], ar[i]);
  }
  return res;
}

/// The repetition count as words (v13.3, FIX C — the sample renders
/// the count under the dhikr as "(ثلاث مرات)"). Only the counts that
/// actually occur in حصن المسلم are worded; anything else falls back
/// to digits.
String countWords(int count) {
  switch (count) {
    case 1:
      return 'مرة واحدة';
    case 3:
      return 'ثلاث مرات';
    case 4:
      return 'أربع مرات';
    case 7:
      return 'سبع مرات';
    case 10:
      return 'عشر مرات';
    case 33:
      return 'ثلاثاً وثلاثين مرة';
    case 100:
      return 'مائة مرة';
    default:
      return '${_toArabicDigits('$count')} مرات';
  }
}

/// The dhikr count label (sample: ٢٣ ذكراً، ٤ أذكار، ١٣ ذكراً):
/// 1 ذكر واحد، 2 ذكران، 3–10 أذكار، 11+ ذكراً.
String dhikrCountLabel(int count) {
  if (count == 1) return 'ذكر واحد';
  if (count == 2) return 'ذكران';
  if (count >= 3 && count <= 10) {
    return '${_toArabicDigits('$count')} أذكار';
  }
  return '${_toArabicDigits('$count')} ذكراً';
}

// ---------------------------------------------------------------------
// Morning / evening split of باب 27 (pure — pinned by tests)
// ---------------------------------------------------------------------

/// The morning/evening split of باب 27 "أذكار الصباح والمساء"
/// (v13.3, FIX C). Decided item-by-item from the REAL text/source of
/// each of the 24 items — nothing invented:
/// * BOTH (14): the text or source says "حين يصبح وحين يمسي" (or
///   gives the evening wording alongside the morning one): items
///   1, 2, 3, 4, 5, 6, 7, 9, 12, 13, 15, 16, 17, 24.
/// * NO EXPLICIT TIME (6): the text/source names no time at all
///   (items 8, 10, 11, 14, 18, 22) — they go in BOTH lists only
///   because the chapter itself is "أذكار الصباح والمساء".
/// * MORNING-ONLY (3): the text says "(إذا أصبحَ)" — items 19, 20, 21.
/// * EVENING-ONLY (1): the text says "(إذا أمسى)" — item 23.
/// Result: morning 23, evening 21 (20 shared in both). The chapter's
/// intro (a general hamd + a hadith covering Fajr-to-sunrise AND
/// Asr-to-sunset) belongs to both split views.
AdhkarCategory morningAdhkar(AdhkarCategory combined) {
  final items = <DhikrItem>[];
  for (var i = 0; i < combined.items.length; i++) {
    if (i == 22) continue; // item 23: "(ثلاثَ مرَّاتٍ إذا أمسى)"
    items.add(combined.items[i]);
  }
  return AdhkarCategory(
    title: 'أذكار الصباح',
    intro: combined.intro,
    introSource: combined.introSource,
    items: items,
  );
}

AdhkarCategory eveningAdhkar(AdhkarCategory combined) {
  final items = <DhikrItem>[];
  for (var i = 0; i < combined.items.length; i++) {
    // items 19–21: "(مائةَ مرَّةٍ إذا أصبحَ)" / "(ثلاثَ مرَّاتٍ
    // إذا أصبحَ)" / "(إذا أصبحَ)".
    if (i == 18 || i == 19 || i == 20) continue;
    items.add(combined.items[i]);
  }
  return AdhkarCategory(
    title: 'أذكار المساء',
    intro: combined.intro,
    introSource: combined.introSource,
    items: items,
  );
}

/// The categories as displayed: morning + evening FIRST (two
/// separate entries), then the rest of the book in order — the
/// combined باب 27 itself is not shown (its items live in the two
/// split entries above).
List<AdhkarCategory> displayAdhkarCategories() {
  final combined = adhkarCategories.firstWhere(
    (c) => c.title == 'أذكار الصباح والمساء',
  );
  return [
    morningAdhkar(combined),
    eveningAdhkar(combined),
    for (final c in adhkarCategories)
      if (c.title != 'أذكار الصباح والمساء') c,
  ];
}

// ---------------------------------------------------------------------
// Categories list
// ---------------------------------------------------------------------

/// قائمة أبواب حصن المسلم مع بحث بالاسم — الصباح والمساء أوّلاً.
class AdhkarCategoriesView extends StatefulWidget {
  const AdhkarCategoriesView({super.key});

  @override
  State<AdhkarCategoriesView> createState() => _AdhkarCategoriesViewState();
}

class _AdhkarCategoriesViewState extends State<AdhkarCategoriesView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayed = displayAdhkarCategories();
    final filtered = _query.isEmpty
        ? displayed
        : displayed
            .where((c) => c.title.contains(_query))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'ابحث في الأذكار...',
              prefixIcon: const Icon(Icons.search_rounded, color: _emerald),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E2421) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _gold.withValues(alpha: 0.4)),
              ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('لا توجد نتائج مطابقة'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final cat = filtered[index];
                    final isFeatured = cat.title == 'أذكار الصباح' ||
                        cat.title == 'أذكار المساء';
                    return Card(
                      color: isDark ? const Color(0xFF1E2421) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isFeatured
                              ? _gold
                              : _gold.withValues(alpha: 0.35),
                          width: isFeatured ? 1.5 : 1,
                        ),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.transparent,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _gold, width: 1.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _toArabicDigits('${index + 1}'),
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          cat.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : _navy,
                          ),
                        ),
                        subtitle: Text(
                          dhikrCountLabel(cat.items.length),
                          style: const TextStyle(
                            fontSize: 13,
                            color: _gold,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cat.title == 'أذكار الصباح')
                              const Icon(Icons.wb_sunny,
                                  color: _gold, size: 22),
                            if (cat.title == 'أذكار المساء')
                              const Icon(Icons.nightlight_round,
                                  color: _gold, size: 22),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_left_rounded,
                                color: _gold),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AdhkarReaderScreen(category: cat),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// One dhikr at a time (paging)
// ---------------------------------------------------------------------

/// شاشة باب واحد: كل ذكر لحاله (v13.3, FIX C — العينة
/// sample-v133-adhkar-dhikr.png). تمرير أفقي بين الأذكار + زرّا
/// السابق/التالي، والضغط على الذكر يزيد العدّاد (منجز/العدد) في
/// الدائرة الكبيرة. المقدمة (إن وجدت) صفحة أولى بعنوان "المقدمة".
class AdhkarReaderScreen extends StatefulWidget {
  final AdhkarCategory category;

  const AdhkarReaderScreen({super.key, required this.category});

  @override
  State<AdhkarReaderScreen> createState() => _AdhkarReaderScreenState();
}

class _AdhkarReaderScreenState extends State<AdhkarReaderScreen> {
  late final PageController _pageController;

  /// عدد المرات التي أكملها المستخدم لكل ذكر (حسب ترتيبه في الباب).
  final Map<int, int> _done = {};
  int _page = 0;

  /// الأذكار التي فتح المستخدم مصدرها/فضلها (مخفية افتراضياً — v13.6).
  final Set<int> _sourceExpanded = {};

  /// Token يلغي تقدّماً تلقائياً معلّقاً: كل تنقّل يدوي أو تصفير
  /// يرفعه، فيتجاهل المؤقّت القديم نفسه (لا تقدّم مزدوج — v13.6).
  int _advanceToken = 0;

  /// ScrollController لكل صفحة ذكر — عند الانتقال لذكر نعيد تمريره
  /// إلى أول سطر (v13.6: لا يبقى الذكر مقصوصاً من الأعلى بعد
  /// تمرير سابق).
  final Map<int, ScrollController> _scrollControllers = {};

  bool get _hasIntro => widget.category.intro != null;
  int get _dhikrCount => widget.category.items.length;
  int get _totalPages => _dhikrCount + (_hasIntro ? 1 : 0);

  /// Dhikr index for a page, or null for the intro page.
  int? _dhikrIndexForPage(int page) =>
      _hasIntro ? (page == 0 ? null : page - 1) : page;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _totalPages) return;
    // تنقّل يدوي — يلغي أي تقدّم تلقائي معلّق.
    _advanceToken++;
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _incrementCurrent() {
    final di = _dhikrIndexForPage(_page);
    if (di == null) return;
    final item = widget.category.items[di];
    final wasCompleted = (_done[di] ?? 0) >= item.count;
    setState(() {
      final done = _done[di] ?? 0;
      _done[di] = done < item.count ? done + 1 : 0;
    });
    // تقدّم تلقائي (v13.6): إذا اكتمل العدّ، انتقل للذكر التالي
    // بعد ثانية واحدة — يبقى العدّ المكتمل ظاهراً قليلاً. على آخر
    // ذكر لا تقدّم (تظهر رسالة الإتمام بدلاً منه). المؤقّت يتحقق
    // من الـ token والصفحة والإكمال، فلا يقدّم مرتين ولا بعد
    // تنقّل يدوي أو تصفير أو إعادة العدّ.
    final justCompleted = (_done[di] ?? 0) >= item.count;
    if (!justCompleted || wasCompleted) return;
    final token = ++_advanceToken;
    final page = _page;
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (token != _advanceToken) return;
      if (_page != page) return;
      final d = _dhikrIndexForPage(_page);
      if (d == null) return;
      if ((_done[d] ?? 0) < widget.category.items[d].count) return;
      if (_page < _totalPages - 1) _goToPage(_page + 1);
    });
  }

  void _resetAll() {
    // التصفير يلغي أي تقدّم تلقائي معلّق.
    _advanceToken++;
    setState(() => _done.clear());
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final di = _dhikrIndexForPage(_page);
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121413) : _ivory,
      body: SafeArea(
        child: Column(
          children: [
            _header(cat, di, isDark),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _totalPages,
                onPageChanged: (p) {
                  setState(() => _page = p);
                  // تنقّل (يدوي أو تلقائي) — يلغي أي تقدّم معلّق،
                  // ويعيد الذكر الجديد إلى أول سطر (v13.6).
                  _advanceToken++;
                  final d = _dhikrIndexForPage(p);
                  final c = d == null ? null : _scrollControllers[d];
                  if (c != null && c.hasClients) c.jumpTo(0);
                },
                itemBuilder: (context, page) {
                  final d = _dhikrIndexForPage(page);
                  if (d == null) return _introPage(cat, isDark);
                  return _dhikrPage(cat.items[d], d, isDark);
                },
              ),
            ),
            _bottomNav(isDark),
          ],
        ),
      ),
    );
  }

  /// Navy header (sample): back chevron, gold title, "الذكر N من M"
  /// (or "المقدمة") + a small reset button.
  Widget _header(AdhkarCategory cat, int? dhikrIndex, bool isDark) {
    return Container(
      color: _navy,
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right, color: _gold, size: 28),
            tooltip: 'رجوع',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              cat.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _gold,
              ),
            ),
          ),
          if (dhikrIndex == null)
            const Text(
              'المقدمة',
              style: TextStyle(fontSize: 14, color: Colors.white),
            )
          else
            Text(
              'الذكر ${_toArabicDigits('${dhikrIndex + 1}')} من ${_toArabicDigits('$_dhikrCount')}',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Colors.white70, size: 20),
            tooltip: 'تصفير العدّادات',
            onPressed: _resetAll,
          ),
        ],
      ),
    );
  }

  Widget _introPage(AdhkarCategory cat, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: _goldFrame(
        isDark: isDark,
        child: Column(
          children: [
            Text(
              cat.intro!,
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _gold,
                height: 1.8,
              ),
            ),
            if (cat.introSource != null) ...[
              const SizedBox(height: 12),
              _goldDivider(),
              const SizedBox(height: 12),
              Text(
                cat.introSource!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dhikrPage(DhikrItem item, int index, bool isDark) {
    final done = _done[index] ?? 0;
    final completed = done >= item.count;
    final isLast = index == widget.category.items.length - 1;
    final sourceOpen = _sourceExpanded.contains(index);
    final scrollController =
        _scrollControllers.putIfAbsent(index, () => ScrollController());
    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        children: [
          GestureDetector(
            onTap: _incrementCurrent,
            child: _goldFrame(
              isDark: isDark,
              child: Column(
                children: [
                  Text(
                    item.text,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 22,
                      height: 1.9,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '(${countWords(item.count)})',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _gold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _goldDivider(),
                  const SizedBox(height: 4),
                  // المصدر والفضل مخفيان افتراضياً (v13.6): زر
                  // يظهرهما عند الضغط ويخفيهما عند الضغط مجدداً،
                  // في مكان النص نفسه داخل الإطار الذهبي — إخفاؤهما
                  // يقصّر الصفحة فلا يضطر المستخدم للتمرير ليصل
                  // إلى دائرة العدّ (وهو ما كان يقصّ أول الذكر).
                  TextButton.icon(
                    key: ValueKey('sourceToggleButton_$index'),
                    onPressed: () => setState(() {
                      if (sourceOpen) {
                        _sourceExpanded.remove(index);
                      } else {
                        _sourceExpanded.add(index);
                      }
                    }),
                    icon: Icon(
                      sourceOpen
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: _gold,
                      size: 18,
                    ),
                    label: Text(
                      'المصدر والفضل',
                      style: GoogleFonts.amiri(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _gold,
                      ),
                    ),
                  ),
                  if (sourceOpen) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.source,
                      key: ValueKey('sourceText_$index'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          // Big circular counter: tap the dhikr (or the circle) to count.
          GestureDetector(
            onTap: _incrementCurrent,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: completed ? _emerald : Colors.transparent,
                border: Border.all(
                    color: completed ? _emerald : _gold, width: 2.5),
              ),
              alignment: Alignment.center,
              child: Text(
                completed
                    ? '✓'
                    : '${_toArabicDigits('$done')}/${_toArabicDigits('${item.count}')}',
                style: GoogleFonts.amiri(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: completed
                      ? Colors.white
                      : (isDark ? Colors.white : _navy),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            // آخر ذكر مكتمل: رسالة إتمام الباب كله بدلاً من التقدّم
            // (لا تقدّم بعد الأخير — v13.6).
            completed
                ? (isLast
                    ? 'تمت ${widget.category.title} ✓ — بارك الله فيك'
                    : 'تم ✓ — سأنتقل للذكر التالي')
                : 'اضغط على الذكر للعدّ',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          // Repetition progress: segments for small counts, a bar
          // for large ones (33 / 100 segments would not fit).
          if (item.count <= 10)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < item.count; i++)
                  Container(
                    width: 44,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i < done
                          ? _gold
                          : _gold.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            )
          else
            SizedBox(
              width: 220,
              child: LinearProgressIndicator(
                value: done / item.count,
                backgroundColor: _gold.withValues(alpha: 0.25),
                color: _gold,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }

  /// Double gold frame with corner diamonds (sample).
  Widget _goldFrame({required Widget child, required bool isDark}) {
    const diamond = 10.0;
    Widget corner({double? left, double? right, double? top, double? bottom}) =>
        Positioned(
          left: left,
          right: right,
          top: top,
          bottom: bottom,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(width: diamond, height: diamond, color: _gold),
          ),
        );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: _gold, width: 1.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1F1D) : Colors.white,
              border: Border.all(
                  color: _gold.withValues(alpha: 0.6), width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: child,
          ),
        ),
        corner(left: -diamond / 2, top: -diamond / 2),
        corner(right: -diamond / 2, top: -diamond / 2),
        corner(left: -diamond / 2, bottom: -diamond / 2),
        corner(right: -diamond / 2, bottom: -diamond / 2),
      ],
    );
  }

  Widget _bottomNav(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed:
                  _page > 0 ? () => _goToPage(_page - 1) : null,
              icon: const Icon(Icons.chevron_right, size: 20),
              label: Text('السابق',
                  style: GoogleFonts.amiri(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: const BorderSide(color: _gold, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _page < _totalPages - 1
                  ? () => _goToPage(_page + 1)
                  : null,
              icon: const Icon(Icons.chevron_left, size: 20),
              label: Text('التالي',
                  style: GoogleFonts.amiri(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
