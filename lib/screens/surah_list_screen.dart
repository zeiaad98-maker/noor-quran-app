import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/surah_name_image.dart';
import 'surah_reader_screen.dart';

class SurahListScreen extends StatefulWidget {
  const SurahListScreen({super.key});

  @override
  State<SurahListScreen> createState() => _SurahListScreenState();
}

class _SurahListScreenState extends State<SurahListScreen> {
  String _searchQuery = '';
  int? _lastSurah;
  int? _lastPage;

  @override
  void initState() {
    super.initState();
    _loadLastRead();
  }

  Future<void> _loadLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastSurah = prefs.getInt('last_surah');
      _lastPage = prefs.getInt('last_page');
    });
  }

  void _openSurah(int surahNumber, {int? page}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurahReaderScreen(surahNumber: surahNumber, initialPage: page),
      ),
    );
    _loadLastRead();
  }

  @override
  Widget build(BuildContext context) {
    final allSurahs = List.generate(114, (index) => index + 1);
    final filteredSurahs = allSurahs.where((surahNum) {
      if (_searchQuery.isEmpty) return true;
      final nameAr = quran.getSurahNameArabic(surahNum);
      return nameAr.contains(_searchQuery) || surahNum.toString() == _searchQuery;
    }).toList();

    return Column(
      children: [
        if (_lastSurah != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: ListTile(
                leading: Icon(Icons.bookmark_rounded, color: Theme.of(context).colorScheme.primary),
                title: const Text('متابعة القراءة', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'سورة ${quran.getSurahNameArabic(_lastSurah!)} ${_lastPage != null ? "• صفحة $_lastPage" : ""}',
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () => _openSurah(_lastSurah!, page: _lastPage),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'ابحث باسم السورة أو رقمها...',
              prefixIcon: const Icon(Icons.search_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: filteredSurahs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final surahNum = filteredSurahs[index];
              final verseCount = quran.getVerseCount(surahNum);
              final pageNum = quran.getPageNumber(surahNum, 1);
              final place = quran.getPlaceOfRevelation(surahNum) == 'Makkah' ? 'مكية' : 'مدنية';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    '$surahNum',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Align(
                  alignment: Alignment.centerRight,
                  child: SurahNameImage(
                    surahNumber: surahNum,
                    height: 30,
                    isDark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                subtitle: Text('$place • $verseCount آية • صفحة $pageNum'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openSurah(surahNum),
              );
            },
          ),
        ),
      ],
    );
  }
}
