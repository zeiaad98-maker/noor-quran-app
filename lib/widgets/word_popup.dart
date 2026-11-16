import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;
import 'package:share_plus/share_plus.dart';

import '../data/audio_player_controller.dart';
import '../data/qcf_word_map.dart';
import '../data/surah_sciences.dart';
import '../data/word_meanings.dart';

/// The word popup: a SMALL compact card over the dimmed Mushaf page
/// (a [Dialog], NOT a bottom sheet), opened by tapping a single word
/// on the page. Built to the user's reference screenshot (v11):
/// a small centered card — المعنى pill on top, the word in green
/// with its meaning directly below, a small icon toolbar — never a
/// tall 68%-of-screen dialog. The dialog sizes to its content
/// (max ~60% of screen height, ~85% when expanded) and every tab
/// and action fits a ~411dp-wide screen with NOTHING cut off:
/// scope tabs are equal-width segments (no horizontal scroll),
/// content tabs wrap, the action bar uses Expanded buttons.
/// * top scope tabs: الكلمة | الآية | الصفحة | علوم السورة
/// * second content tabs per scope, ONLY where we have verified data:
///   - الكلمة: المعنى (غريب القرآن) | الإعراب (مبسّط)
///   - الآية: التفسير الميسر (one tab, honestly labelled)
///   - الصفحة: أسباب النزول (per ayah) — the only content tab.
///     الترجمات was REMOVED entirely in v11 (Bug I, user order
///     "الترجمات احذفها"): no translation tab, no alquran.cloud
///     fetch, no replacement translation.
///   - علوم السورة: أسماء السورة | نزول السورة | مقاصد السورة |
///     فضائل السورة | عدد آيات السورة | إحصائيات
///   OMITTED (no verified source — never fabricated): القراءات،
///   التصريف، التجويد، الفوائد، and the توقيفية/اجتهادية labels on
///   surah names. Names / maqsad / fadail exist only for Fatiha (1)
///   and Baqarah (2) so far — other surahs say so plainly.
/// * المعنى fallback: when the word has no غريب القرآن entry, the
///   morphology description (morphForWord — same data as الإعراب)
///   is shown as the body text instead of a "no meaning" note.
/// * bottom row: expand, mute, prev/next word, counter, share, close.
/// * bottom green action bar: استماع (plays the single word and
///   closes the popup so the compact mini-player bar docked at the
///   bottom of the reader is visible — it NEVER opens the full
///   player sheet), الإعدادات, فاصل (page bookmark), تعليق (opens
///   the ayah sheet for notes).
///
/// The tapped word comes from the QCF glyph→word map
/// ([buildQcfWordMap]), so the index is the TRUE Uthmani word index
/// — the same index the word audio and the Quran.com segments use.
/// Prev/next arrows move between the true words of the same ayah.
Future<void> showWordPopup({
  required BuildContext context,
  required int surah,
  required int verse,
  required int wordIndex,
  required AudioPlayerController audioController,
  required bool isBookmarked,
  required VoidCallback onToggleBookmark,
  required VoidCallback onOpenSettings,
  required void Function(int wordIndex) onPlayWord,
  required VoidCallback onOpenNotes,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => WordPopup(
      surah: surah,
      verse: verse,
      initialWordIndex: wordIndex,
      audioController: audioController,
      isBookmarked: isBookmarked,
      onToggleBookmark: onToggleBookmark,
      onOpenSettings: onOpenSettings,
      onPlayWord: onPlayWord,
      onOpenNotes: onOpenNotes,
    ),
  );
}

class WordPopup extends StatefulWidget {
  final int surah;
  final int verse;
  final int initialWordIndex;
  final AudioPlayerController audioController;
  final bool isBookmarked;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenSettings;
  final void Function(int wordIndex) onPlayWord;
  final VoidCallback onOpenNotes;

  const WordPopup({
    super.key,
    required this.surah,
    required this.verse,
    required this.initialWordIndex,
    required this.audioController,
    required this.isBookmarked,
    required this.onToggleBookmark,
    required this.onOpenSettings,
    required this.onPlayWord,
    required this.onOpenNotes,
  });

  @override
  State<WordPopup> createState() => _WordPopupState();
}

class _WordPopupState extends State<WordPopup> {
  static const _scopes = ['الكلمة', 'الآية', 'الصفحة', 'علوم السورة'];

  // Content tabs per scope (only tabs with verified data).
  static const _contentTabs = <List<String>>[
    ['المعنى', 'الإعراب'],
    ['التفسير الميسر'],
    ['أسباب النزول'],
    [
      'أسماء السورة',
      'نزول السورة',
      'مقاصد السورة',
      'فضائل السورة',
      'عدد آيات السورة',
      'إحصائيات',
    ],
  ];

  static const _accent = Color(0xFF0D6E52);
  static const _gold = Color(0xFFC59B27);

  int _scope = 0;
  int _contentTab = 0;
  late int _wordIndex;
  bool _expanded = false;

  late final QcfWordMap _map;
  late final String _ayahText;

  String? _meaning;
  String? _morph;
  String? _tafsir;
  List<String>? _asbab;
  String? _hizbLabel;
  SurahInfo? _surahInfo;
  SurahScience? _surahScience;
  SurahStats? _stats;
  bool _wordLoading = true;

  @override
  void initState() {
    super.initState();
    _map = buildQcfWordMap(widget.surah, widget.verse);
    _wordIndex = widget.initialWordIndex.clamp(0, _mapWordCount - 1);
    _ayahText = getVerse(widget.surah, widget.verse);
    _loadAyahData();
    _loadWordData();
  }

  int get _mapWordCount => _map.wordCount;

  QcfWordInfo get _word => _map.words[_wordIndex];

  Future<void> _loadWordData() async {
    setState(() => _wordLoading = true);
    final word = _word;
    final meaning = await QuranWordData.meaningForWord(
      widget.surah,
      widget.verse,
      word.text,
    );
    final morph = await QuranWordData.morphForWord(
      widget.surah,
      widget.verse,
      word.lookupText,
    );
    if (!mounted) return;
    setState(() {
      _meaning = meaning;
      _morph = morph;
      _wordLoading = false;
    });
  }

  Future<void> _loadAyahData() async {
    final tafsir = await QuranWordData.tafsirForAyah(
      widget.surah,
      widget.verse,
    );
    final asbab = await SurahSciences.asbabForAyah(
      widget.surah,
      widget.verse,
    );
    final hizb = await QuranWordData.hizbQuarterLabel(
      widget.surah,
      widget.verse,
    );
    final info = await SurahSciences.infoForSurah(widget.surah);
    final science = await SurahSciences.scienceForSurah(widget.surah);
    if (!mounted) return;
    setState(() {
      _tafsir = tafsir;
      _asbab = asbab;
      _hizbLabel = hizb;
      _surahInfo = info;
      _surahScience = science;
      _stats = SurahSciences.statsForSurah(widget.surah);
    });
  }

  void _setScope(int scope) {
    setState(() {
      _scope = scope;
      _contentTab = 0;
    });
  }

  void _setContentTab(int tab) {
    setState(() => _contentTab = tab);
  }

  void _moveWord(int delta) {
    final next = (_wordIndex + delta).clamp(0, _mapWordCount - 1);
    if (next == _wordIndex) return;
    setState(() => _wordIndex = next);
    _loadWordData();
  }

  Future<void> _share() async {
    final surahName = quran.getSurahName(widget.surah);
    final meaningPart = (_meaning ?? _morph) == null
        ? ''
        : '\nمعناها: ${_meaning ?? _morph}';
    await Share.share(
      '﴿${_word.text}﴾ — سورة $surahName، الآية ${widget.verse}$meaningPart\n'
      'تطبيق نور قرآن',
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final surahName = quran.getSurahName(widget.surah);
    // Compact card: sizes to its content, capped so it never fills
    // the screen like the old 68%-tall dialog. The content area is a
    // Flexible scroll region, so short content (word + meaning) stays
    // a small card and long content (tafsir, sciences) scrolls inside.
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: size.height * (_expanded ? 0.85 : 0.60),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _scopeTabs(),
            const Divider(height: 1),
            _contentTabsRow(),
            const Divider(height: 1),
            Flexible(child: _content(surahName)),
            const Divider(height: 1),
            _controlRow(),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  /// Scope tabs as equal-width segments — no horizontal scrolling,
  /// so nothing (not even علوم السورة) is cut off at a 411dp width.
  Widget _scopeTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < _scopes.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ChoiceChip(
                  label: Text(
                    _scopes[i],
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
                  labelPadding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  selected: _scope == i,
                  onSelected: (_) => _setScope(i),
                  selectedColor: _accent,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _scope == i ? Colors.white : Colors.black87,
                    fontWeight:
                        _scope == i ? FontWeight.bold : FontWeight.normal,
                  ),
                  backgroundColor: Colors.grey.shade200,
                  side: BorderSide.none,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Content tabs WRAP onto extra lines instead of scrolling
  /// horizontally — the 6 علوم السورة tabs must all be visible.
  Widget _contentTabsRow() {
    final tabs = _contentTabs[_scope];
    if (tabs.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          tabs[0],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: _accent,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < tabs.length; i++)
            ChoiceChip(
              label: Text(tabs[i], style: const TextStyle(fontSize: 13)),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              selected: _contentTab == i,
              onSelected: (_) => _setContentTab(i),
              selectedColor: _gold,
              labelStyle: TextStyle(
                color: _contentTab == i ? Colors.white : Colors.black87,
              ),
              backgroundColor: Colors.grey.shade200,
              side: BorderSide.none,
            ),
        ],
      ),
    );
  }

  Widget _content(String surahName) {
    switch (_scope) {
      case 0:
        return _wordContent();
      case 1:
        return _ayahContent(surahName);
      case 2:
        return _pageContent();
      case 3:
        return _sciencesContent(surahName);
      default:
        return const SizedBox.shrink();
    }
  }

  // -- الكلمة -----------------------------------------------------------

  Widget _wordContent() {
    if (_wordLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_contentTab == 1) {
      // الإعراب (مبسّط).
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _bigWord(),
            const SizedBox(height: 12),
            if (_morph != null)
              _bodyText(_morph!)
            else
              _noteText(
                'لا يوجد إعراب مبسّط مسجَّل لهذه الكلمة في البيانات المتوفرة.',
              ),
          ],
        ),
      );
    }
    // المعنى — word in green, meaning directly below it (reference
    // layout). No full-ayah box: the card stays small, and the ayah
    // is one tap away on the الآية scope. When the word has no
    // غريب القرآن entry, the morphology description is the body
    // text instead of a "no special meaning" note.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bigWord(),
          const SizedBox(height: 10),
          if (_meaning != null)
            _bodyText(_meaning!)
          else if (_morph != null)
            _bodyText(_morph!)
          else
            _noteText(
              'هذه الكلمة ليس لها معنى خاص في غريب القرآن — معناها واضح '
              'من سياق الآية.',
            ),
        ],
      ),
    );
  }

  Widget _bigWord() {
    return Text(
      _word.text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Hafs',
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: _accent,
        height: 1.4,
      ),
    );
  }

  // -- الآية ------------------------------------------------------------

  Widget _ayahContent(String surahName) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '[$surahName - ${widget.verse}]',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _ayahText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Hafs',
              fontSize: 22,
              height: 1.9,
              color: Color(0xFFB71C1C),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'التفسير الميسر',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 6),
          if (_tafsir != null)
            _bodyText(_tafsir!)
          else
            _noteText('جاري تحميل التفسير…'),
        ],
      ),
    );
  }

  // -- الصفحة: أسباب النزول only (الترجمات removed, v11 Bug I). -----
  Widget _pageContent() {
    final asbab = _asbab;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pageInfoLine(),
          const SizedBox(height: 12),
          const Text(
            'أسباب النزول',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 8),
          if (asbab == null)
            const Center(child: CircularProgressIndicator())
          else if (asbab.isEmpty)
            _noteText(
              'لم يرد سبب نزول مسجَّل لهذه الآية في صحيح أسباب النزول.',
            )
          else
            for (final occasion in asbab)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(fontSize: 16, color: _accent)),
                    Expanded(child: _bodyText(occasion)),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          _noteText('المصدر: صحيح أسباب النزول — إبراهيم محمد العلي.'),
        ],
      ),
    );
  }

  Widget _pageInfoLine() {
    final juz = quran.getJuzNumber(widget.surah, widget.verse);
    final page = _surahInfo == null
        ? null
        : quran.getPageNumber(widget.surah, widget.verse);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        [
          if (page != null) 'الصفحة $page',
          'الجزء $juz',
          if (_hizbLabel != null) _hizbLabel!,
        ].join(' • '),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
    );
  }

  // -- علوم السورة -------------------------------------------------------

  Widget _sciencesContent(String surahName) {
    switch (_contentTab) {
      case 0:
        return _scienceTextBlock(
          'أسماء السورة',
          _surahScience?.names,
          _surahScience?.namesVerbatim,
          _surahScience?.namesEtymology,
        );
      case 1:
        return _nuzulBlock(surahName);
      case 2:
        return _scienceTextBlock(
          'مقاصد السورة',
          null,
          _surahScience?.maqsadVerbatim,
          _surahScience?.maqsadShort == null
              ? null
              : 'الخلاصة: ${_surahScience!.maqsadShort!}',
        );
      case 3:
        return _fadailBlock();
      case 4:
        return _countBlock();
      case 5:
        return _statsBlock();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _scienceTextBlock(
    String title,
    List<String>? chips,
    String? verbatim,
    String? extra,
  ) {
    final missing = verbatim == null && (chips == null || chips.isEmpty);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 10),
          if (missing)
            _noteText(
              'لم تُستخرَج بعد $title لهذه السورة — المتوفر حالياً '
              'سورتا الفاتحة والبقرة فقط.',
            )
          else ...[
            if (chips != null && chips.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in chips)
                    Chip(
                      label: Text(name),
                      backgroundColor: const Color(0xFFE8F5E9),
                      side: BorderSide.none,
                    ),
                ],
              ),
            if (verbatim != null) ...[
              const SizedBox(height: 12),
              _bodyText(verbatim),
            ],
            if (extra != null) ...[
              const SizedBox(height: 12),
              _bodyText(extra),
            ],
            const SizedBox(height: 12),
            _noteText('المصدر: مصاعد النظر للبقاعي.'),
          ],
        ],
      ),
    );
  }

  Widget _nuzulBlock(String surahName) {
    final info = _surahInfo;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'نزول السورة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 10),
          if (info == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            _infoRow('السورة', surahName),
            _infoRow('مكان النزول', info.revelationPlaceAr),
            _infoRow('ترتيب النزول', '${info.revelationOrder}'),
            _infoRow(
              'الصفحات',
              info.pageStart == info.pageEnd
                  ? 'صفحة ${info.pageStart}'
                  : 'من صفحة ${info.pageStart} إلى ${info.pageEnd}',
            ),
            if (_surahScience?.nuzulVerbatim != null) ...[
              const SizedBox(height: 12),
              _bodyText(_surahScience!.nuzulVerbatim!),
            ],
          ],
        ],
      ),
    );
  }

  Widget _fadailBlock() {
    final sci = _surahScience;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'فضائل السورة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 10),
          if (sci == null)
            _noteText(
              'لم تُستخرَج بعد فضائل هذه السورة — المتوفر حالياً '
              'سورتا الفاتحة والبقرة فقط.',
            )
          else ...[
            if (sci.fadailHeadline != null) _bodyText(sci.fadailHeadline!),
            if (sci.fadailHadith != null) ...[
              const SizedBox(height: 12),
              _bodyText(sci.fadailHadith!),
            ],
            if (sci.fadailSource != null) ...[
              const SizedBox(height: 12),
              _noteText('المصدر: ${sci.fadailSource!}'),
            ],
          ],
        ],
      ),
    );
  }

  Widget _countBlock() {
    final info = _surahInfo;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'عدد آيات السورة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 10),
          if (info == null)
            const Center(child: CircularProgressIndicator())
          else _infoRow('عدد الآيات', '${info.ayahCount} آية'),
        ],
      ),
    );
  }

  Widget _statsBlock() {
    final stats = _stats;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إحصائيات السورة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: _accent,
            ),
          ),
          const SizedBox(height: 10),
          if (stats == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            _infoRow('عدد الآيات', '${stats.ayahCount}'),
            _infoRow('عدد الكلمات', '${stats.wordCount}'),
            _infoRow('عدد الحروف', '${stats.letterCount}'),
          ],
          const SizedBox(height: 12),
          _noteText(
            'تُحسَب الكلمات والحروف من نص المصحف المضمَّن في التطبيق.',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, height: 1.7, color: Colors.black87),
    );
  }

  Widget _noteText(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, height: 1.6, color: Colors.black54),
    );
  }

  // -- bottom rows ------------------------------------------------------

  Widget _controlRow() {
    // Custom 32dp tap targets, NOT IconButton: IconButton enforces
    // a 48dp minimum tap target, so 6 buttons + the counter needed
    // ~460dp and the row overflowed the 363dp inner width. At 32dp
    // the row needs ~350dp even in the wide test font, ~295dp in
    // a real Arabic font.
    Widget controlIcon({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onPressed,
              child: Icon(
                icon,
                size: 20,
                color: onPressed == null ? Colors.black26 : Colors.black87,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          controlIcon(
            icon: _expanded ? Icons.fullscreen_exit : Icons.fullscreen,
            tooltip: _expanded ? 'تصغير' : 'تكبير',
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
          ListenableBuilder(
            listenable: widget.audioController,
            builder: (context, _) => controlIcon(
              icon: widget.audioController.isMuted
                  ? Icons.volume_off
                  : Icons.volume_up,
              tooltip:
                  widget.audioController.isMuted ? 'إلغاء الكتم' : 'كتم',
              onPressed: () => widget.audioController.toggleMute(),
            ),
          ),
          controlIcon(
            icon: Icons.chevron_right,
            tooltip: 'الكلمة السابقة',
            onPressed:
                _wordIndex > 0 ? () => _moveWord(-1) : null,
          ),
          // Unambiguous counter: "الكلمة 4 من 46". The old
          // "4 / 46" rendered as "46 / 4" — the bidi algorithm
          // flips a bare "n / m" inside an RTL paragraph.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              'الكلمة ${_wordIndex + 1} من $_mapWordCount',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          controlIcon(
            icon: Icons.chevron_left,
            tooltip: 'الكلمة التالية',
            onPressed: _wordIndex < _mapWordCount - 1
                ? () => _moveWord(1)
                : null,
          ),
          controlIcon(
            icon: Icons.share,
            tooltip: 'مشاركة',
            onPressed: _share,
          ),
          controlIcon(
            icon: Icons.close,
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    return Container(
      decoration: const BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _actionButton(
              Icons.play_arrow,
              'استماع',
              () {
                widget.onPlayWord(_wordIndex);
                // Close the popup so the compact mini-player bar
                // docked at the bottom of the reader is visible.
                // (A Dialog is modal — the bar sits behind it.)
                if (mounted) Navigator.of(context).pop();
              },
            ),
          ),
          Expanded(
            child: _actionButton(
              Icons.settings,
              'الإعدادات',
              widget.onOpenSettings,
            ),
          ),
          Expanded(
            child: _actionButton(
              Icons.bookmark,
              'فاصل',
              widget.onToggleBookmark,
              active: widget.isBookmarked,
            ),
          ),
          Expanded(
            child: _actionButton(
              Icons.comment,
              'تعليق',
              () {
                Navigator.of(context).pop();
                widget.onOpenNotes();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool active = false,
  }) {
    // Tight padding + small label: the old default TextButton.icon
    // padding overflowed the ~387dp inner width and cut استماع off.
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        icon,
        color: active ? _gold : Colors.white,
        size: 18,
      ),
      label: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: active ? _gold : Colors.white,
          fontSize: 12,
        ),
      ),
    );
  }
}
