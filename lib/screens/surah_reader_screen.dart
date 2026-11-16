import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/audio_player_controller.dart';
import '../data/ayah_notes.dart';
import '../main.dart';
import '../widgets/audio_player_sheet.dart';
import '../widgets/ayah_action_sheet.dart';
import '../widgets/noor_qcf_page.dart';
import '../widgets/quran_search_sheet.dart';
import '../widgets/surah_name_image.dart';
import '../widgets/word_popup.dart';
import 'notes_screen.dart';

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
  // Mushaf zoom: 1.0 = the size the QCF fonts are calibrated for.
  // Anything far from 1.0 breaks the Madinah line breaks, so the range
  // is deliberately narrow (0.92..1.08). See _qcfSp below.
  double _pageZoom = 1.0;
  late final AudioPlayerController _audioController;
  // True while a page jump was caused by the player following the
  // playing ayah; such jumps must NOT stop the playback.
  bool _playerDrivenPageChange = false;
  Set<String> _notedAyahIds = {};
  Timer? _clockTimer;
  String _currentTime = '';

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
    _audioController = AudioPlayerController();
    // The player sheet and the top-bar play icon rebuild from this.
    _audioController.addListener(() {
      if (mounted) setState(() {});
    });
    _audioController.onAyahChanged = (ayah) {
      final page = quran.getPageNumber(ayah.$1, ayah.$2);
      if (page != _currentPage) {
        _playerDrivenPageChange = true;
        _pageController.jumpToPage(page - 1);
      }
    };
    _audioController.onError = (message, retry) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'إعادة المحاولة',
            onPressed: () => unawaited(retry()),
          ),
        ),
      );
    };
    // Keep the screen on while reading / reciting.
    unawaited(WakelockPlus.enable());
    _loadSettings();
    _loadNotedAyahs();
    _updateClock();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    _clockTimer?.cancel();
    _pageController.dispose();
    _audioController.dispose();
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

  Future<void> _loadNotedAyahs() async {
    final ids = await AyahNotes.notedIds();
    if (mounted) setState(() => _notedAyahIds = ids);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isBookmarked = prefs.getInt('bookmarked_page') == _currentPage;
      // Migrate old zoom values (previously 1.12 default, up to 1.28)
      // into the narrow range that keeps the Mushaf line breaks intact.
      _pageZoom =
          (prefs.getDouble('mushaf_page_zoom') ?? 1.0).clamp(0.92, 1.08);
      _audioController.setInitialReciterIndex(
          prefs.getInt('reciter_index') ?? 0);
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
    // A manual page change stops the audio so it always matches what
    // is on screen — except when the player itself jumped here while
    // following the playing ayah.
    if (_playerDrivenPageChange) {
      _playerDrivenPageChange = false;
    } else {
      unawaited(_audioController.stop());
    }
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
    if (mounted) {
      setState(() => _isBookmarked = !_isBookmarked);
      unawaited(Fluttertoast.showToast(
        msg: _isBookmarked ? 'تمت إضافة العلامة' : 'تم حذف العلامة',
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: const Color(0xFF0D6E52),
        textColor: Colors.white,
      ));
    }
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
                    label: Text('ورقي كريمي',
                        style: GoogleFonts.amiri(fontSize: 14)),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('ليلي مريح',
                        style: GoogleFonts.amiri(fontSize: 14)),
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
                            _pageZoom = (_pageZoom - 0.04) < 0.92
                                ? 0.92
                                : _pageZoom - 0.04;
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
                            _pageZoom = (_pageZoom + 0.04) > 1.08
                                ? 1.08
                                : _pageZoom + 0.04;
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
              const SizedBox(height: 4),
              Text(
                'تكبير الخط كثيراً يغيّر فواصل الأسطر عن مصحف المدينة — الأفضل 100%',
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

  /// Opens the audio player sheet, preset to [scope], and starts
  /// playing immediately. The reader play button opens it on the
  /// current page; the ayah sheet opens it on that ayah; a tapped
  /// word opens it on that word.
  void _openPlayerSheet({
    required PlayerScope scope,
    int? surah,
    int? verse,
    int? wordIndex,
  }) {
    switch (scope) {
      case PlayerScope.word:
        unawaited(_audioController.playWord(surah!, verse!, wordIndex!));
      case PlayerScope.ayah:
        unawaited(_audioController.playAyah(surah!, verse!));
      case PlayerScope.page:
        unawaited(
            _audioController.playPages(_currentPage, _currentPage));
      case PlayerScope.surah:
        unawaited(_audioController.playSurah(surah!));
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AudioPlayerSheet(
        controller: _audioController,
        currentPage: _currentPage,
      ),
    );
  }

  void _openAyahSheet(int surah, int verse) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AyahActionSheet(
        surahNumber: surah,
        verseNumber: verse,
        pageNumber: _currentPage,
        onPlayAyah: () => _openPlayerSheet(
          scope: PlayerScope.ayah,
          surah: surah,
          verse: verse,
        ),
        onPlayWord: (wordIndex) => _openPlayerSheet(
          scope: PlayerScope.word,
          surah: surah,
          verse: verse,
          wordIndex: wordIndex,
        ),
        onOpenNotesScreen: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotesScreen()),
          ).then((_) => _loadNotedAyahs());
        },
        onNoteChanged: _loadNotedAyahs,
      ),
    ).then((_) => _loadNotedAyahs());
  }

  /// Word popup (v10): opened by tapping a single word on the page.
  /// [wordIndex] is the TRUE 0-based Uthmani word index from the QCF
  /// word map; the audio controller takes a 1-based word position
  /// (the ayah sheet passes i + 1), so the play callback adds 1.
  /// Tapping the verse-end number glyph still opens the ayah sheet
  /// ([_openAyahSheet]) — that is the way to notes / ayah audio.
  void _openWordPopup(int surah, int verse, int wordIndex) {
    showWordPopup(
      context: context,
      surah: surah,
      verse: verse,
      wordIndex: wordIndex,
      audioController: _audioController,
      isBookmarked: _isBookmarked,
      onToggleBookmark: _toggleBookmark,
      onOpenSettings: _showMushafSettingsSheet,
      onPlayWord: (word) => _openPlayerSheet(
        scope: PlayerScope.word,
        surah: surah,
        verse: verse,
        wordIndex: word + 1,
      ),
      onOpenNotes: () => _openAyahSheet(surah, verse),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = NoorQuranApp.of(context)!.isDarkMode;
    final bgColor = isDark ? const Color(0xFF121413) : const Color(0xFFFAF6EE);
    final goldColor = const Color(0xFF8A723D);
    final pageData = quran.getPageData(_currentPage);
    final surahNumber = pageData.isNotEmpty ? pageData[0]['surah'] as int : 1;
    final juzNumber = quran.getJuzNumber(surahNumber, 1);
    final juzName = _juzNamesArabic[juzNumber - 1];
    final pageSide = _currentPage % 2 == 0 ? 'يسرى' : 'يمنى';

    final qcfTheme = isDark
        ? QcfThemeData.dark().copyWith(
            pageBackgroundColor: bgColor,
            verseNumberColor: const Color(0xFFD2BA80),
            verseHeight: 2.1,
            verseBackgroundColor: (surah, verse) =>
                _notedAyahIds.contains('$surah:$verse')
                    ? const Color(0xFF8A723D).withValues(alpha: 0.35)
                    : null,
          )
        : QcfThemeData(
            pageBackgroundColor: bgColor,
            verseTextColor: const Color(0xFF1A1A1A),
            verseNumberColor: goldColor,
            basmalaColor: const Color(0xFF1A1A1A),
            headerTextColor: const Color(0xFF1A1A1A),
            verseHeight: 2.1,
            verseBackgroundColor: (surah, verse) =>
                _notedAyahIds.contains('$surah:$verse')
                    ? const Color(0xFFFFF3C4).withValues(alpha: 0.7)
                    : null,
          );

    // Calibrated QCF font scale: the qcf_quran example uses sp = 1.sp
    // with design width 392.7, i.e. font size grows with screen width.
    // Do NOT multiply by ScreenUtil .sp (its fontSizeResolver is width,
    // so _pageZoom.sp was 1.12 x scaleWidth = 1.18) and do NOT let the
    // system font size scale the Quran text (see MediaQuery below):
    // either one pushes the font past the size the per-page QCF fonts
    // are calibrated for, so Mushaf lines wrap and orphan words spill
    // onto centred lines (v7 feedback).
    final qcfSp = MediaQuery.of(context).size.width / 392.7 * _pageZoom;

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      enableScaleText: () => false,
      minTextAdapt: true,
      builder: (_, __) => Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _showControls
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  size: 20,
                                ),
                                color: goldColor,
                                tooltip: 'إظهار / إخفاء أشرطة التحكم',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(
                                      () => _showControls = !_showControls);
                                },
                              ),
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
                                  SurahNameImage(
                                    surahNumber: surahNumber,
                                    height: 24,
                                    isDark: isDark,
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
                          // The Mushaf must fit vertically: the line
                          // height factor comes from the ACTUAL height
                          // the PageView gets (status bar, header,
                          // footer and nav bar already subtracted by
                          // the layout), so all 15 lines are visible
                          // with no scrolling or clipping, on any
                          // phone size. The font size never changes —
                          // only the line spacing shrinks a little,
                          // so the Madinah line breaks are untouched.
                          // (v9: page 5 lost its last 1.5 lines
                          // because the old code used a fixed h = 1.0
                          // and the page was pushed down by the
                          // status-bar padding — see noor_qcf_page.)
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final h = mushafHeightFactor(
                                constraints.maxHeight,
                                qcfSp,
                              );
                              // System font size must not scale the
                              // Mushaf text: the QCF page fonts are
                              // calibrated for one exact size, and any
                              // scaling breaks the line breaks.
                              return MediaQuery(
                                data: MediaQuery.of(context).copyWith(
                                  textScaler: TextScaler.noScaling,
                                ),
                                // NoorQcfPage: local copy of the package page
                                // widget that keeps the hard line breaks the
                                // package drops (see noor_qcf_page.dart).
                                child: NoorQuranPageView(
                                  controller: _pageController,
                                  initialPageNumber: _currentPage,
                                  sp: qcfSp,
                                  h: h,
                                  theme: qcfTheme,
                                  onPageChanged: _onPageChanged,
                                  onTap: (surah, verse) =>
                                      _openAyahSheet(surah, verse),
                                  onWordTap: (surah, verse, wordIndex) =>
                                      _openWordPopup(surah, verse, wordIndex),
                                ),
                              );
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
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: AnimatedOpacity(
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
                          IconButton(
                            icon: Icon(
                              _showControls
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            color: goldColor,
                            tooltip: 'إظهار / إخفاء الأشرطة',
                            onPressed: () {
                              setState(() => _showControls = !_showControls);
                            },
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                SurahNameImage(
                                  surahNumber: surahNumber,
                                  height: 26,
                                  isDark: isDark,
                                ),
                                Text(
                                  '$juzName • ${quran.getVerseCount(surahNumber)} آية • الصفحة $_currentPage من 604',
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
                              _isBookmarked
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
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
                              _audioController.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            color: goldColor,
                            onPressed: () => _openPlayerSheet(
                              scope: PlayerScope.page,
                            ),
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
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: AnimatedOpacity(
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
                            onPressed: () => _openPlayerSheet(
                              scope: PlayerScope.page,
                            ),
                            icon: const Icon(Icons.person, size: 18),
                            label: Text(
                              _audioController.reciter.name,
                              style: GoogleFonts.amiri(fontSize: 14),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                unawaited(_audioController.stop()),
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
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
