import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../widgets/quran_search_sheet.dart';

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
  bool _showControls = false; // يبدأ بواجهة القراءة الصافية المطابقة للصورة، وتظهر الأشرطة عند اللمس
  int? _bookmarkedPage;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoadingAudio = false;
  int _selectedReciterIndex = 0;
  Timer? _clockTimer;
  String _currentTimeStr = '';

  final List<Map<String, String>> _reciters = [
    {'name': 'محمود الحصري', 'server': 'https://server13.mp3quran.net/husr'},
    {'name': 'مشاري العفاسي', 'server': 'https://server8.mp3quran.net/afs'},
    {'name': 'محمد صديق المنشاوي', 'server': 'https://server10.mp3quran.net/minsh'},
    {'name': 'عبد الباسط عبد الصمد', 'server': 'https://server7.mp3quran.net/basit'},
    {'name': 'ماهر المعيقلي', 'server': 'https://server12.mp3quran.net/maher'},
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
    _currentPage = widget.initialPage ?? quran.getPageNumber(widget.surahNumber, 1);
    _pageController = PageController(initialPage: _currentPage - 1);
    _saveLastRead(_currentPage);
    _loadBookmark();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) => _updateClock());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheSurroundingPages(_currentPage);
    });

    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        _isLoadingAudio = state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
        }
      });
    });
  }

  void _precacheSurroundingPages(int centerPage) {
    if (!mounted) return;
    final pagesToPreload = [
      centerPage + 1,
      centerPage + 2,
      centerPage + 3,
      centerPage + 4,
      centerPage + 5,
      centerPage - 1,
      centerPage - 2,
    ];
    for (final p in pagesToPreload) {
      if (p >= 1 && p <= 604) {
        precacheImage(CachedNetworkImageProvider(_getPageImageUrl(p)), context);
      }
    }
  }

  void _updateClock() {
    final now = DateTime.now();
    int h = now.hour % 12;
    if (h == 0) h = 12;
    final m = now.minute.toString().padLeft(2, '0');
    if (mounted) {
      setState(() => _currentTimeStr = _toArabicDigits('$h:$m'));
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _pageController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _bookmarkedPage = prefs.getInt('bookmarked_page'));
  }

  Future<void> _toggleBookmark() async {
    final prefs = await SharedPreferences.getInstance();
    if (_bookmarkedPage == _currentPage) {
      await prefs.remove('bookmarked_page');
      setState(() => _bookmarkedPage = null);
    } else {
      await prefs.setInt('bookmarked_page', _currentPage);
      setState(() => _bookmarkedPage = _currentPage);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ العلامة المرجعية عند صفحة ${_toArabicDigits('$_currentPage')}')),
        );
      }
    }
  }

  Future<void> _saveLastRead(int page) async {
    final prefs = await SharedPreferences.getInstance();
    final pageData = quran.getPageData(page);
    final firstSurahOnPage = pageData.isNotEmpty ? pageData.first['surah'] as int : widget.surahNumber;
    await prefs.setInt('last_page', page);
    await prefs.setInt('last_surah', firstSurahOnPage);
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

  String _getPageImageUrl(int pageNumber) {
    // صور مصحف مجمع الملك فهد عالية الدقة بشمسات الآيات الذهبية والزيتية
    final padded = pageNumber.toString().padLeft(3, '0');
    return 'https://android.quran.com/data/width_1920/page$padded.png';
  }

  Future<void> _toggleAudioPlay(int surahNum) async {
    if (_isPlaying) {
      await _audioPlayer.pause();
      return;
    }
    try {
      final server = _reciters[_selectedReciterIndex]['server']!;
      final surahCode = surahNum.toString().padLeft(3, '0');
      final url = '$server/$surahCode.mp3';
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تشغيل التلاوة، تأكد من اتصال الإنترنت')),
        );
      }
    }
  }

  void _pickReciter() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('اختر القارئ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ...List.generate(_reciters.length, (i) {
              return ListTile(
                leading: Icon(
                  i == _selectedReciterIndex ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: const Color(0xFF8C7A4B),
                ),
                title: Text(_reciters[i]['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final wasPlaying = _isPlaying;
                  await _audioPlayer.stop();
                  setState(() => _selectedReciterIndex = i);
                  if (wasPlaying) {
                    final pageData = quran.getPageData(_currentPage);
                    final s = pageData.isNotEmpty ? pageData.first['surah'] as int : widget.surahNumber;
                    _toggleAudioPlay(s);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openInMushafSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('البحث في آيات المصحف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: QuranSearchView(
                  onSelectPage: (page) {
                    Navigator.pop(ctx);
                    _pageController.jumpToPage(page - 1);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = NoorQuranApp.of(context);
    final isDark = appState?.isDarkMode ?? false;

    final pageData = quran.getPageData(_currentPage);
    final currentSurah = pageData.isNotEmpty ? pageData.first['surah'] as int : widget.surahNumber;

    // ألوان الورق والحبر الذهبي الدافئ المطابقة للصورة المرفقة تماماً
    final bgColor = isDark ? const Color(0xFF141413) : const Color(0xFFFDFCF9);
    final goldText = isDark ? const Color(0xFFC8B27D) : const Color(0xFF8B7544);
    final subtleText = isDark ? Colors.white54 : const Color(0xFF9C9688);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. صفحة المصحف الكاملة بنفس الجمالية والألوان
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              child: PageView.builder(
                controller: _pageController,
                itemCount: 604,
                physics: const BouncingScrollPhysics(),
                onPageChanged: (index) {
                  final newPage = index + 1;
                  setState(() => _currentPage = newPage);
                  _saveLastRead(newPage);
                  _precacheSurroundingPages(newPage);
                },
                itemBuilder: (context, index) {
                  final pageNum = index + 1;
                  final pData = quran.getPageData(pageNum);
                  final sNum = pData.isNotEmpty ? pData.first['surah'] as int : 1;
                  final jNum = pData.isNotEmpty ? quran.getJuzNumber(sNum, pData.first['start'] as int) : 1;
                  final juzText = _juzNamesArabic[(jNum - 1).clamp(0, 29)];
                  final surahName = quran.getSurahNameArabic(sNum);
                  final isPageRight = pageNum % 2 == 1;
                  final isFirstTwoPages = pageNum == 1 || pageNum == 2;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        children: [
                          // الترويسة العلوية الأنيقة المطابقة للصورة: (الجزء الأول) يميناً | (صفحة يمنى + الساعة) وسطاً | (البقرة) يساراً
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    juzText,
                                    textAlign: TextAlign.right,
                                    style: GoogleFonts.amiri(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: goldText,
                                    ),
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isPageRight ? 'صفحة يمنى' : 'صفحة يسرى',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: subtleText,
                                      ),
                                    ),
                                    Text(
                                      _currentTimeStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: subtleText.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ),
                                Expanded(
                                  child: Text(
                                    surahName,
                                    textAlign: TextAlign.left,
                                    style: GoogleFonts.amiri(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: goldText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // متن الآيات بكامل عرض الشاشة بدون تمطيط أو حذف
                          Expanded(
                            child: InteractiveViewer(
                              minScale: 1.0,
                              maxScale: 2.5,
                              child: Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isFirstTwoPages ? 10 : 2,
                                  ),
                                  child: ColorFiltered(
                                    colorFilter: isDark
                                        ? const ColorFilter.matrix([
                                            -0.92, 0, 0, 0, 238,
                                            0, -0.92, 0, 0, 236,
                                            0, 0, -0.92, 0, 230,
                                            0, 0, 0, 1, 0,
                                          ])
                                        : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                                    child: CachedNetworkImage(
                                      imageUrl: _getPageImageUrl(pageNum),
                                      width: constraints.maxWidth,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      fadeInDuration: const Duration(milliseconds: 50),
                                      placeholder: (context, url) => Center(
                                        child: CircularProgressIndicator(color: goldText, strokeWidth: 2),
                                      ),
                                      errorWidget: (context, url, error) => Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.wifi_off_rounded, size: 42, color: goldText),
                                          const SizedBox(height: 8),
                                          Text(
                                            'صفحة ${_toArabicDigits('$pageNum')}\nافتح الصفحة مرة واحدة بالإنترنت لحفظها أوفلاين',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: goldText),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // التذييل السفلي: رقم الصفحة باللون الذهبي الدافئ في المنتصف تماماً كالصورة
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8, top: 2),
                            child: Text(
                              _toArabicDigits('$pageNum'),
                              style: GoogleFonts.amiri(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: goldText,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            // 2. شريط الأدوات العلوي العائم (يظهر عند اللمس فقط)
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: bgColor.withValues(alpha: 0.96),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: goldText, size: 25),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      Text(
                        'سورة ${quran.getSurahNameArabic(currentSurah)}',
                        style: GoogleFonts.amiri(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: goldText,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.search_rounded, color: goldText, size: 23),
                        tooltip: 'البحث عن آية أو كلمة',
                        onPressed: _openInMushafSearch,
                      ),
                      IconButton(
                        icon: Icon(Icons.format_list_bulleted_rounded, color: goldText, size: 23),
                        tooltip: 'فهرس السور',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              ),

            // 3. شريط التلاوة والتحكم السفلي العائم (يظهر عند اللمس فقط)
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: bgColor.withValues(alpha: 0.96),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _bookmarkedPage == _currentPage
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          color: goldText,
                          size: 25,
                        ),
                        onPressed: _toggleBookmark,
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _toggleAudioPlay(currentSurah),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: goldText.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: _isLoadingAudio
                              ? Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: goldText),
                                )
                              : Icon(
                                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: goldText,
                                  size: 26,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: _pickReciter,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _reciters[_selectedReciterIndex]['name']!,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: goldText,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.keyboard_arrow_down_rounded, color: goldText, size: 20),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isDark ? Icons.light_mode_rounded : Icons.dark_mode_outlined,
                          color: goldText,
                          size: 23,
                        ),
                        onPressed: () => appState?.toggleTheme(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
