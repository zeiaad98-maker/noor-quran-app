import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/audio_downloads.dart';
import '../data/audio_player_controller.dart';
import '../data/ayah_marks.dart';
import '../data/ayah_notes.dart';
import '../data/quran_audio.dart';
import '../data/tafsir_downloads.dart';
import '../main.dart';
import '../widgets/audio_player_sheet.dart';
import '../widgets/ayah_action_sheet.dart';
import '../widgets/mini_audio_bar.dart';
import '../widgets/noor_qcf_page.dart';
import '../widgets/quran_search_sheet.dart';
import '../widgets/surah_name_image.dart';
import '../widgets/word_card.dart';
import 'notes_screen.dart';
import 'reciters_screen.dart';

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
  // Anything above it breaks the Madinah line breaks, so the range
  // is deliberately narrow (0.92..0.98 — see clampMushafZoom).
  // Default 0.98: the safe maximum, visually identical to 1.0.
  double _pageZoom = 0.98;

  /// Playback highlight toggle (v13.2, bug C / best-apps rule 4):
  /// colour the playing ayah / word while audio plays. Default on;
  /// persisted as 'highlight_playback' in _loadSettings.
  bool _highlightPlayback = true;
  late final AudioPlayerController _audioController;
  // Offline reciter downloads (v12): one instance shared by the
  // player (plays local files when present) and the reciters screen.
  late final AudioDownloadService _downloadsService;
  // The six tafsirs (v12): الميسر bundled, the other five
  // download-on-demand. One instance for the whole reader.
  late final TafsirService _tafsirService;
  // True while a page jump was caused by the player following the
  // playing ayah; such jumps must NOT stop the playback.
  bool _playerDrivenPageChange = false;
  // True while the compact mini-player bar is docked at the bottom
  // of the reader (word playback from the word popup). It is NOT a
  // modal sheet: the reader's own audio button still opens the full
  // AudioPlayerSheet.
  bool _showMiniBar = false;
  Set<String> _notedAyahIds = {};
  // v13.3 (FIX B): bookmarked (فاصل) and coloured (تلوين) ayahs,
  // loaded with the noted ids to tint the page.
  Set<String> _bookmarkedAyahIds = {};
  Set<String> _highlightedAyahIds = {};
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
    _downloadsService = AudioDownloadService();
    unawaited(_downloadsService.init());
    _audioController = AudioPlayerController(downloads: _downloadsService);
    // Repeat / speed settings the user chose before (v13.2, bug B):
    // restored once at startup so a count survives app restarts.
    unawaited(_audioController.restorePlaybackSettings());
    _tafsirService = TafsirService();
    unawaited(_tafsirService.init());
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
    _loadMarkedAyahs();
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
    _downloadsService.dispose();
    _tafsirService.dispose();
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

  /// Bookmarked (فاصل) and coloured (تلوين) ayahs (v13.3, FIX B):
  /// reloaded whenever a card / sheet that can toggle them closes,
  /// so the page tint follows the toggle immediately.
  Future<void> _loadMarkedAyahs() async {
    final results = await Future.wait([
      AyahBookmarks.ids(),
      AyahHighlights.ids(),
    ]);
    if (mounted) {
      setState(() {
        _bookmarkedAyahIds = results[0];
        _highlightedAyahIds = results[1];
      });
    }
  }

  /// Page tint for a marked ayah (v13.3, FIX B): a coloured ayah
  /// (تلوين) gets a green tint; a noted or bookmarked ayah (فاصل)
  /// gets the gold tint. Colour wins when an ayah carries both.
  Color? _ayahTint(int surah, int verse, {required bool dark}) {
    final id = '$surah:$verse';
    if (_highlightedAyahIds.contains(id)) {
      return const Color(0xFF0D6E52).withValues(alpha: dark ? 0.30 : 0.22);
    }
    if (_notedAyahIds.contains(id) || _bookmarkedAyahIds.contains(id)) {
      return dark
          ? const Color(0xFF8A723D).withValues(alpha: 0.35)
          : const Color(0xFFFFF3C4).withValues(alpha: 0.7);
    }
    return null;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // v13 layout fix: the Mushaf fonts are calibrated for zoom 1.00
    // and wrap above it — clamp any saved zoom (the old range went
    // to 1.08; the user's was ~1.04) into 0.92–0.98 and persist the
    // migration, so the layout can never break again.
    final storedZoom = prefs.getDouble('mushaf_page_zoom') ?? 1.0;
    final zoom = clampMushafZoom(storedZoom);
    if (zoom != storedZoom) {
      await prefs.setDouble('mushaf_page_zoom', zoom);
    }
    // v13 default reciter: خليفة الطنيجي. A stored value the user
    // chose himself is kept; absent or still the old default (0)
    // migrates to الطنيجي and the migration is persisted.
    final storedReciter = prefs.getInt('reciter_index');
    final reciterIndex = resolveDefaultReciterIndex(storedReciter);
    if (storedReciter != reciterIndex) {
      await prefs.setInt('reciter_index', reciterIndex);
    }
    if (!mounted) return;
    setState(() {
      _isBookmarked = prefs.getInt('bookmarked_page') == _currentPage;
      _pageZoom = zoom;
      _highlightPlayback = prefs.getBool('highlight_playback') ?? true;
      _audioController.setInitialReciterIndex(reciterIndex);
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
      _showMiniBar = false;
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
                            // v13: the zoom caps at 0.98 — above the
                            // calibrated size the Mushaf lines wrap
                            // (see clampMushafZoom in noor_qcf_page).
                            _pageZoom = (_pageZoom + 0.04) > 0.98
                                ? 0.98
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
              // Playback highlight toggle (v13.2, bug C / best-apps
              // rule 4): the sheet is not a StatefulBuilder, so the
              // switch keeps its own local state to flip instantly;
              // the reader's setState repaints the page highlight.
              StatefulBuilder(
                builder: (context, setSwitchState) => SwitchListTile(
                  title: Text(
                    'تمييز الآية أثناء الاستماع',
                    style: GoogleFonts.amiri(
                      fontSize: 17,
                      color: isDark ? Colors.white : const Color(0xFF2D2A26),
                    ),
                  ),
                  subtitle: Text(
                    'تلوين الآية والكلمة أثناء التشغيل',
                    style: GoogleFonts.amiri(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                  value: _highlightPlayback,
                  activeThumbColor: const Color(0xFF0D6E52),
                  onChanged: (value) async {
                    setSwitchState(() {});
                    setState(() => _highlightPlayback = value);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('highlight_playback', value);
                  },
                ),
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
        unawaited(_audioController.playPages(_currentPage, _currentPage));
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
        onOpenDownloads: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RecitersScreen(
                service: _downloadsService,
                currentReciterIndex: _audioController.reciterIndex,
              ),
            ),
          );
        },
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

  /// Word card (v13.6 — Wahy style): opened by tapping a single
  /// word on the page. Bottom sheet, ayah header with the tapped
  /// word in blue, 4 tabs, every button wired (the user's order:
  /// "فعّلوا كل الأزرار"). [wordIndex] is the TRUE 0-based Uthmani
  /// word index from the QCF word map; the audio controller takes a
  /// 1-based word position, so the play callbacks add 1.
  ///
  /// Tapping the verse-end number glyph opens the AYAH SHEET
  /// ([_openAyahSheet]) — play ayah, word chips, notes (v13.5:
  /// the world apps show the ayah sheet for an ayah tap; the
  /// tafsir card moved to the word card's تفاسير button).
  ///
  /// v13.2 (best-apps rule 1): tapping a word plays JUST the word
  /// immediately — the wbw file, never the ayah — and shows the
  /// compact mini-player bar docked at the bottom of the reader.
  /// v13.6: the auto-play honours the word settings toggle
  /// ([AudioPlayerController.wordAutoPlay]) — when off, the tap
  /// opens the card only and the green ▶ plays the word.
  void _openWordCard(int surah, int verse, int wordIndex) {
    if (_audioController.wordAutoPlay) {
      unawaited(_audioController.playWord(surah, verse, wordIndex + 1));
      if (mounted) setState(() => _showMiniBar = true);
    }
    showWordCard(
      context: context,
      surah: surah,
      verse: verse,
      wordIndex: wordIndex,
      audioController: _audioController,
      onPlayWord: (word) {
        unawaited(_audioController.playWord(surah, verse, word + 1));
        if (mounted) setState(() => _showMiniBar = true);
      },
      onRepeatWord: (word) {
        unawaited(_audioController.repeatWord(surah, verse, word + 1));
        if (mounted) setState(() => _showMiniBar = true);
      },
      onPlayAyah: () {
        unawaited(_audioController.playAyah(surah, verse));
        if (mounted) setState(() => _showMiniBar = true);
      },
      onContinueFromAyah: () {
        unawaited(_audioController.playFromAyah(surah, verse));
        if (mounted) setState(() => _showMiniBar = true);
      },
      onGoToLastReading: _goToLastReading,
      // ملاحظة opens the ayah sheet (note editor lives there);
      // تفاسير opens the tafsir card. The card pops itself first.
      onOpenNotes: () => _openAyahSheet(surah, verse),
      onOpenTafsir: () => _openTafsirCard(surah, verse),
      onOpenReciterPicker: () => showReciterPickerSheet(
        context: context,
        controller: _audioController,
      ),
      onOpenPlaybackSettings: () => showPlaybackSettingsSheet(
        context: context,
        controller: _audioController,
      ),
    ).then((_) => _loadMarkedAyahs());
  }

  /// آخر قراءة (v13.6, the word card's button): jump to the page
  /// the user last read (persisted as 'last_page' on every page
  /// change). A no-op when nothing was saved yet.
  Future<void> _goToLastReading() async {
    final prefs = await SharedPreferences.getInstance();
    final page = prefs.getInt('last_page');
    if (page != null && mounted) _jumpToPage(page);
  }

  /// Long-press a word plays its whole AYAH (v13.2, UX D /
  /// best-apps rule 2): the second, distinct gesture for ayah audio
  /// — tap is the word, long-press is the ayah (rule 6). Shows the
  /// mini bar; the full sheet is one tap away on the bar.
  void _onWordLongPress(int surah, int verse, int wordIndex) {
    unawaited(_audioController.playAyah(surah, verse));
    if (mounted) setState(() => _showMiniBar = true);
  }

  /// Tafsir card (v12): opened from the word card's التفسير button
  /// (v13.5: the verse-end number glyph ۝ opens the ayah sheet now).
  /// Ayah in a cream box + the selected tafsir (selector pill
  /// switches between the six) + أسباب النزول when the ayah has an
  /// entry. استمع للآية opens the full player; ملاحظاتي opens the
  /// old ayah sheet (notes / word chips / ayah audio).
  void _openTafsirCard(int surah, int verse) {
    showTafsirCard(
      context: context,
      surah: surah,
      verse: verse,
      tafsirService: _tafsirService,
      onPlayAyah: () => _openPlayerSheet(
        scope: PlayerScope.ayah,
        surah: surah,
        verse: verse,
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
                _ayahTint(surah, verse, dark: true),
          )
        : QcfThemeData(
            pageBackgroundColor: bgColor,
            verseTextColor: const Color(0xFF1A1A1A),
            verseNumberColor: goldColor,
            basmalaColor: const Color(0xFF1A1A1A),
            headerTextColor: const Color(0xFF1A1A1A),
            verseHeight: 2.1,
            verseBackgroundColor: (surah, verse) =>
                _ayahTint(surah, verse, dark: false),
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
                                      _openWordCard(surah, verse, wordIndex),
                                  onWordLongPress: (surah, verse, wordIndex) =>
                                      _onWordLongPress(
                                          surah, verse, wordIndex),
                                  // Playback highlight (v13.2, bug C):
                                  // only while really playing and the
                                  // toggle is on; word scope colours
                                  // the word (0-based), other scopes
                                  // tint the whole ayah.
                                  playingActive: _highlightPlayback &&
                                      _audioController.isPlaying,
                                  playingSurah:
                                      _audioController.currentAyah?.$1,
                                  playingVerse:
                                      _audioController.currentAyah?.$2,
                                  playingWordIndex:
                                      _audioController.scope ==
                                              PlayerScope.word
                                          ? (_audioController.wordIndex ??
                                                  1) -
                                              1
                                          : null,
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
                            icon: const Icon(Icons.info_outline),
                            color: goldColor,
                            tooltip: 'عن السورة',
                            onPressed: () => showSurahSciencesSheet(
                              context: context,
                              surah: surahNumber,
                            ),
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
                            onPressed: () => unawaited(_audioController.stop()),
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
              // Compact mini-player bar (word playback from the word
              // popup): docked at the bottom of the reader, overlaying
              // the page — never a modal sheet. X stops the audio
              // and hides the bar; a manual page change hides it too.
              if (_showMiniBar)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MiniAudioBar(
                    controller: _audioController,
                    onClose: () async {
                      await _audioController.stop();
                      if (mounted) {
                        setState(() => _showMiniBar = false);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
