import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/adhkar_data.dart';
import 'tasbeeh_screen.dart';

/// شاشة الأذكار والمسبحة — تبويبان:
/// 0 = الأذكار (حصن المسلم كاملاً: 132 باباً، 267 ذكراً ودعاءً)
/// 1 = المسبحة (عداد التسبيح)
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
    const emerald = Color(0xFF0C6E52);
    return Column(
      children: [
        Container(
          color: emerald,
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFC7A35F),
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
            tabs: const [
              Tab(icon: Icon(Icons.menu_book_rounded), text: 'الأذكار'),
              Tab(icon: Icon(Icons.blur_circular_rounded), text: 'المسبحة'),
            ],
          ),
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

String _toArabicDigits(String input) {
  const en = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const ar = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  String res = input;
  for (int i = 0; i < 10; i++) {
    res = res.replaceAll(en[i], ar[i]);
  }
  return res;
}

/// قائمة أبواب حصن المسلم مع بحث بالاسم.
class AdhkarCategoriesView extends StatefulWidget {
  const AdhkarCategoriesView({super.key});

  @override
  State<AdhkarCategoriesView> createState() => _AdhkarCategoriesViewState();
}

class _AdhkarCategoriesViewState extends State<AdhkarCategoriesView> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFC7A35F);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _query.isEmpty
        ? adhkarCategories
        : adhkarCategories
            .where((c) => c.title.contains(_query))
            .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'ابحث عن باب من الأذكار...',
              prefixIcon: const Icon(Icons.search_rounded, color: emerald),
              filled: true,
              fillColor: isDark ? const Color(0xFF1E2421) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: gold.withValues(alpha: 0.4)),
              ),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                'حصن المسلم — ${_toArabicDigits('${adhkarCategories.length}')} باباً، ${_toArabicDigits('267')} ذكراً',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('لا توجد نتائج مطابقة'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final cat = filtered[index];
                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: gold.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: emerald.withValues(alpha: 0.12),
                          child: Text(
                            _toArabicDigits('${adhkarCategories.indexOf(cat) + 1}'),
                            style: const TextStyle(
                              color: emerald,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        title: Text(
                          cat.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: Text(
                          '${_toArabicDigits('${cat.items.length}')} ${cat.items.length == 1 ? 'ذكر' : 'أذكار'}',
                        ),
                        trailing: const Icon(Icons.chevron_left_rounded, color: gold),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdhkarCategoryScreen(category: cat),
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

/// شاشة باب واحد: أذكاره مع عدد التكرار والمرجع، وعدّاد باللمس لكل ذكر.
class AdhkarCategoryScreen extends StatefulWidget {
  final AdhkarCategory category;

  const AdhkarCategoryScreen({super.key, required this.category});

  @override
  State<AdhkarCategoryScreen> createState() => _AdhkarCategoryScreenState();
}

class _AdhkarCategoryScreenState extends State<AdhkarCategoryScreen> {
  /// عدد المرات التي أكملها المستخدم لكل ذكر (حسب ترتيبه في الباب).
  final Map<int, int> _done = {};

  void _resetAll() {
    setState(() => _done.clear());
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    const emerald = Color(0xFF0C6E52);
    const gold = Color(0xFFC7A35F);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(cat.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تصفير العدّادات',
            onPressed: _resetAll,
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: cat.items.length + (cat.intro != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (cat.intro != null && index == 0) {
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: emerald.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Text(
                    cat.intro!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: gold,
                      height: 1.6,
                    ),
                  ),
                  if (cat.introSource != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      cat.introSource!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }
          final itemIndex = cat.intro != null ? index - 1 : index;
          final item = cat.items[itemIndex];
          final done = _done[itemIndex] ?? 0;
          final completed = done >= item.count;
          return InkWell(
            onTap: () {
              setState(() {
                _done[itemIndex] = done < item.count ? done + 1 : 0;
              });
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A1F1D) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: completed ? emerald : gold.withValues(alpha: 0.3),
                  width: completed ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: completed ? emerald : gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          completed
                              ? '✓ تم'
                              : item.count > 1
                                  ? 'التكرار: ${_toArabicDigits('${item.count}')} مرات — ${_toArabicDigits('$done')}/${_toArabicDigits('${item.count}')}'
                                  : 'مرة واحدة',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: completed ? Colors.white : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                      ),
                      Text(
                        _toArabicDigits('${itemIndex + 1}'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.text,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 20,
                      height: 1.9,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.source,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
