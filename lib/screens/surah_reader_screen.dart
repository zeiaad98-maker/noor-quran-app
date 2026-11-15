import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../widgets/quran_search_sheet.dart';

/// Full-screen Mushaf reader — QCF text rendering (Madina Mushaf font),
/// works fully offline (fonts are bundled in the qcf_quran package).
class SurahReaderScreen extends StatefulWidget {
  final int? surahNumber;
  final int? initialPage;
  const SurahReaderScreen({super.key, this.surahNumber, this.initialPage = 1});

  @override
  State<SurahReaderScreen> createState() => _SurahReaderScreenState();
}

class _SurahReaderScreenState extends State<SurahReaderScreen> {
  late final PageController _pageController;
  int _currentPage = 1;
  bool _showControls = false;
  bool _isBookmarked = false;
  double _pageZoom = 1.12;
  late final AudioPlayer _audioPlayer;
  bool _isPlayingAudio = false;
  int _currentReciterIndex = 0;
  Timer? _clockTimer;
  String _currentTime = '';

  static const List<Map<String, String>> _reciters = [
    {'name': 'محمود الحصري', 'server': 'server13.mp3quran.net/husr'},
    {'name': 'مشاري العفاسي', 'server': 'server8.mp3quran.net/afs'},
    {'name': 'محمد صديق المنشاوي', 'server': 'server10.mp3quran.net/minsh'},
    {'name': 'عبد الباسط عبد الصمد', 'server': 'server7.mp3quran.net/basit'},
    {'name': 'ماهر المعيقلي', 'server': 'server12.mp3quran.net/maher'},
  ];

  static const List<String> _juzNamesArabic = [
    'الجزء الأول',
    'الجزء الثاني',
    'الجزء الثالث',
    'الجزء الرابع',
    'الجزء الخامس',
    'الجزء السادس',
    'الجزء السابع',
    'الجزء الثامن',
    'الجزء التاسع',
    'الجزء العاشر',
    'الجزء الحادي عشر',
    'الجزء الثاني عشر',
    'الجزء الثالث عشر',
    'الجزء الرابع عشر',
    'الجزء الخامس عشر',
    'الجزء السادس عشر',
    'الجزء السابع عشر',
    'الجزء الثامن عشر',
    'الجزء التاسع عشر',
    'الجزء العشرون',
    'الجزء الحادي والعشرون',
    'الجزء الثاني والعشرون',
    'الجزء الثالث والعشرون',
    'الجزء الرابع والعشرون',
    'الجزء الخامس والعشرون',
    'الجزء السادس والعشرون',
    'الجزء السابع والعشرون',
    'الجزء الثامن والعشرون',
    'الجزء التاسع والعشرون',
    'الجزء الثلاثون',
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage ??
        (widget.surahNumber != null
            ? quran.getPageNumber(widget.surahNumber!, 1)
            : 1);
    _pageController = PageController(initialPage: _currentPage - 1);
    _audioPlayer = AudioPlayer();
    _loadSettings();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _audioPlayer.playerStateStream.listen((state) {
      if (mounted && state.processingState == ProcessingState.completed) {
        setState(() => _isPlayingAudio = false);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pageController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'م' : 'ص';
    if (mounted) setState(() => _currentTime = '$h:$m:$s $period');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isBookmarked = prefs.getInt('bookmarked_page') == _currentPage;
      _pageZoom = prefs.getDouble('mushaf_page_zoom') ?? 1.12;
    });
  }

  Future<void> _saveZoom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('mushaf_page_zoom', _pageZoom);
  }

  Future<void> _saveLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    final surah = quran.getPageData(_currentPage).isNotEmpty
        ? quran.getPageData(_currentPage)[0]['surah'] as int
        : 1;
    await prefs.setInt('last_page', _currentPage);
    await prefs.setInt('last_surah', surah);
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
      _showControls = false;
    });
    _saveLastRead();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() => _isBookmarked = prefs.getInt('bookmarked_page') == page);
      }
    });
  }

  void _jumpToPage(int page) {
    if (page < 1 || page > 604) return;
    _pageController.jumpToPage(page - 1);
  }

  Future<void> _toggleBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isBookmarked) {
      await prefs.remove('bookmarked_page');
    } else {
      await prefs.setInt('bookmarked_page', _currentPage);
    }
    if (mounted) setState(() => _isBookmarked = !_isBookmarked);
  }

  void _openInMushafSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuranSearchView(
        onSelectPage: (page) {
          Navigator.of(context).pop();
          _jumpToPage(page);
        },
      ),
    );
  }

  void _showMushafSettingsSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final isDark = NoorQuranApp.of(context)!.isDarkMode;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1F1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'إعدادات المصحف',
                style: GoogleFonts.amiri(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF2D2A26),
                ),
              ),
              const SizedBox(height: 20),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('ورقي كريمي', style: GoogleFonts.amiri(fontSize: 14)),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('ليلي مريح', style: GoogleFonts.amiri(fontSize: 14)),
                  ),
                ],
                selected: <bool>{isDark},
                onSelectionChanged: (Set<bool> selected) {
                  if (selected.first != isDark) {
                    NoorQuranApp.of(context)!.toggleTheme();
                  }
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'حجم الخط',
                    style: GoogleFonts.amiri(
                      fontSize: 18,
                      color: isDark ? Colors.white : const Color(0xFF2D2A26),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          setState(() {
                            _pageZoom = (_pageZoom - 0.04) < 1.0 ? 1.0 : _pageZoom - 0.04;
                          });
                          _saveZoom();
                        },
                      ),
                      SizedBox(
                        width: 56,
                        child: Text(
                          '${(_pageZoom * 100).round()}%',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.amiri(fontSize: 16),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          setState(() {
                            _pageZoom = (_pageZoom + 0.04) > 1.28 ? 1.28 : _pageZoom + 0.04;
                          });
                          _saveZoom();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'الخط يعمل بدون إنترنت — لا حاجة لتحميل الصفحات',
                style: GoogleFonts.amiri(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleAudioPlay() async {
    if (_isPlayingAudio) {
      await _audioPlayer.pause();
      setState(() => _isPlayingAudio = false);
      return;
    }
    try {
      final pageData = quran.getPageData(_currentPage);
      final surah = pageData.isNotEmpty ? pageData[0]['surah'] as int : 1;
      final server = _reciters[_currentReciterIndex]['server']!;
      final url =
          'https://$server/${surah.toString().padLeft(3, '0')}.mp3';
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
      setState(() => _isPlayingAudio = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تشغيل الصوت — تحقق من الإنترنت')),
        );
      }
    }
  }

  void _pickReciter() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _reciters.length; i++)
              ListTile(
                title: Text(_reciters[i]['name']!),
                trailing: i == _currentReciterIndex
                    ? const Icon(Icons.check, color: Color(0xFF0D6E52))
                    : null,
                onTap: () {
                  setState(() => _currentReciterIndex = i);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NoorQuranApp.of(context)!.isDarkMode;
    final bgColor = isDark ? const Color(0xFF121413) : const Color(0xFFFAF6EE);
    final goldColor = const Color(0xFF8A723D);
    final pageData = quran.getPageData(_currentPage);
    final surahNumber = pageData.isNotEmpty ? pageData[0]['surah'] as int : 1;
    final surahName = quran.getSurahNameArabic(surahNumber);
    final juzNumber = quran.getJuzNumber(surahNumber, 1);
    final juzName = _juzNamesArabic[juzNumber - 1];
    final pageSide = _currentPage % 2 == 0 ? 'يسرى' : 'يمنى';

    final qcfTheme = isDark
        ? QcfThemeData.dark().copyWith(
            pageBackgroundColor: bgColor,
            verseNumberColor: const Color(0xFFD2BA80),
          )
        : QcfThemeData(
            pageBackgroundColor: bgColor,
            verseTextColor: const Color(0xFF1A1A1A),
            verseNumberColor: goldColor,
            basmalaColor: const Color(0xFF1A1A1A),
            headerTextColor: const Color(0xFF1A1A1A),
          );

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      enableScaleText: () => false,
      minTextAdapt: true,
      builder: (_, __) => Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Column(
            children: [
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        bgColor,
                        bgColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        color: goldColor,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              surahName,
                              style: GoogleFonts.amiri(
                                fontSize: 17.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF2D2A26),
                              ),
                            ),
                            Text(
                              '$juzName • الصفحة $_currentPage من 604',
                              style: GoogleFonts.amiri(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                        ),
                        color: _isBookmarked ? goldColor : Colors.grey,
                        onPressed: _toggleBookmark,
                      ),
                      IconButton(
                        icon: const Icon(Icons.search),
                        color: goldColor,
                        onPressed: _openInMushafSearch,
                      ),
                      IconButton(
                        icon: Icon(
                          _isPlayingAudio ? Icons.pause : Icons.play_arrow,
                        ),
                        color: goldColor,
                        onPressed: _toggleAudioPlay,
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings),
                        color: goldColor,
                        onPressed: _showMushafSettingsSheet,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            juzName,
                            style: GoogleFonts.amiri(
                              fontSize: 16.5,
                              color: goldColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _currentTime,
                            style: GoogleFonts.amiri(
                              fontSize: 16.5,
                              color: Colors.grey,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                surahName,
                                style: GoogleFonts.amiri(
                                  fontSize: 16.5,
                                  color: goldColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '($pageSide)',
                                style: GoogleFonts.amiri(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageviewQuran(
                        controller: _pageController,
                        initialPageNumber: _currentPage,
                        sp: _pageZoom.sp,
                        theme: qcfTheme,
                        onPageChanged: _onPageChanged,
                        onTap: (_, __) {
                          setState(() => _showControls = !_showControls);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, top: 4),
                      child: Text(
                        '$_currentPage'.replaceAllMapped(
                          RegExp(r'\d'),
                          (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)],
                        ),
                        style: GoogleFonts.amiri(
                          fontSize: 17.5,
                          color: goldColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        bgColor,
                        bgColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _pickReciter,
                        icon: const Icon(Icons.person, size: 18),
                        label: Text(
                          _reciters[_currentReciterIndex]['name']!,
                          style: GoogleFonts.amiri(fontSize: 14),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          if (_isPlayingAudio) _toggleAudioPlay();
                          setState(() => _isPlayingAudio = false);
                        },
                        icon: const Icon(Icons.stop, size: 18),
                        label: Text(
                          'إيقاف الصوت',
                          style: GoogleFonts.amiri(fontSize: 14),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _jumpToPage(_currentPage + 1),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text(
                          'الصفحة التالية',
                          style: GoogleFonts.amiri(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
