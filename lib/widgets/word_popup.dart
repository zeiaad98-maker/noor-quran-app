import 'package:material_ui/material_ui.dart';
import 'package:qcf_quran/qcf_quran.dart';
import 'package:quran/quran.dart' as quran;
import 'package:share_plus/share_plus.dart';

import '../data/audio_player_controller.dart';
import '../data/qcf_word_map.dart';
import '../data/surah_sciences.dart';
import '../data/word_meanings.dart';

/// The word popup: an overlay card over the dimmed Mushaf page
/// (a [Dialog], NOT a bottom sheet), opened by tapping a single word
/// on the page. Built to the user's reference screenshots:
/// * top scope tabs: الكلمة | الآية | الصفحة | علوم السورة
/// * second content tabs per scope, ONLY where we have verified data:
///   - الكلمة: المعنى (غريب القرآن) | الإعراب (مبسّط)
///   - الآية: التفسير الميسر (one tab, honestly labelled)
///   - الصفحة: أسباب النزول (per ayah) | الترجمات (Sahih Intl, API)
///   - علوم السورة: أسماء السورة | نزول السورة | مقاصد السورة |
///     فضائل السورة | عدد آيات السورة | إحصائيات
///   OMITTED (no verified source — never fabricated): القراءات،
///   التصريف، التجويد، الفوائد، and the توقيفية/اجتهادية labels on
///   surah names. Names / maqsad / fadail exist only for Fatiha (1)
///   and Baqarah (2) so far — other surahs say so plainly.
/// * bottom row: expand, mute, prev/next word, share, close.
/// * bottom green action bar: استماع (plays the single word),
///   الإعدادات, فاصل (page bookmark), تعليق (opens the ayah sheet
///   for notes).
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
    ['أسباب النزول', 'الترجمات'],
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
  // Translation: null = not requested yet, '' = failed/offline.
  String? _translation;
  bool _translationLoading = false;

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

  Future<void> _loadTranslation() async {
    if (_translation != null || _translationLoading) return;
    setState(() => _translationLoading = true);
    final text = await SurahSciences.fetchTranslation(
      widget.surah,
      widget.verse,
    );
    if (!mounted) return;
    setState(() {
      _translation = text ?? '';
      _translationLoading = false;
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
    if (_scope == 2 && tab == 1) _loadTranslation();
  }

  void _moveWord(int delta) {
    final next = (_wordIndex + delta).clamp(0, _mapWordCount - 1);
    if (next == _wordIndex) return;
    setState(() => _wordIndex = next);
    _loadWordData();
  }

  Future<void> _share() async {
    final surahName = quran.getSurahName(widget.surah);
    final meaningPart = _meaning == null
        ? ''
        : '\nمعناها: $_meaning';
    await Share.share(
      '﴿${_word.text}﴾ — سورة $surahName، الآية ${widget.verse}$meaningPart\n'
      'تطبيق نور قرآن',
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width * 0.94 > 540 ? 540.0 : size.width * 0.94;
    final height = size.height * (_expanded ? 0.88 : 0.68);
    final surahName = quran.getSurahName(widget.surah);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _scopeTabs(),
            const Divider(height: 1),
            _contentTabsRow(),
            const Divider(height: 1),
            Expanded(child: _content(surahName)),
            const Divider(height: 1),
            _controlRow(),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  Widget _scopeTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          for (var i = 0; i < _scopes.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(_scopes[i]),
                selected: _scope == i,
                onSelected: (_) => _setScope(i),
                selectedColor: _accent,
                labelStyle: TextStyle(
                  color: _scope == i ? Colors.white : Colors.black87,
                  fontWeight:
                      _scope == i ? FontWeight.bold : FontWeight.normal,
                ),
                backgroundColor: Colors.grey.shade200,
                side: BorderSide.none,
              ),
            ),
        ],
      ),
    );
  }

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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(tabs[i], style: const TextStyle(fontSize: 13)),
                selected: _contentTab == i,
                onSelected: (_) => _setContentTab(i),
                selectedColor: _gold,
                labelStyle: TextStyle(
                  color:
                      _contentTab == i ? Colors.white : Colors.black87,
                ),
                backgroundColor: Colors.grey.shade200,
                side: BorderSide.none,
              ),
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
    // المعنى.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ayahBox(),
          const SizedBox(height: 14),
          _bigWord(),
          const SizedBox(height: 12),
          if (_meaning != null)
            _bodyText(_meaning!)
          else
            _noteText(
              'هذه الكلمة ليس لها معنى خاص في غريب القرآن — معناها واضح '
              'من سياق الآية.',
            ),
        ],
      ),
    );
  }

  Widget _ayahBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F5),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _ayahText,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Hafs',
          fontSize: 20,
          height: 1.9,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _bigWord() {
    return Text(
      _word.text,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'Hafs',
        fontSize: 38,
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

  // -- الصفحة -----------------------------------------------------------

  Widget _pageContent() {
    if (_contentTab == 1) {
      // الترجمات.
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الترجمة الإنجليزية — Saheeh International',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: _accent,
              ),
            ),
            const SizedBox(height: 8),
            if (_translationLoading)
              const Center(child: CircularProgressIndicator())
            else if (_translation != null && _translation!.isNotEmpty)
              Text(
                _translation!,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 15, height: 1.6),
              )
            else
              _noteText(
                'تعذّر تحميل الترجمة — تحتاج إلى اتصال بالإنترنت. '
                'المصدر: alquran.cloud (Saheeh International).',
              ),
            const SizedBox(height: 8),
            _noteText('المصدر: alquran.cloud — Saheeh International.'),
          ],
        ),
      );
    }
    // أسباب النزول.
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: _expanded ? 'تصغير' : 'تكبير',
            icon: Icon(
              _expanded ? Icons.fullscreen_exit : Icons.fullscreen,
            ),
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
          ListenableBuilder(
            listenable: widget.audioController,
            builder: (context, _) => IconButton(
              tooltip: widget.audioController.isMuted ? 'إلغاء الكتم' : 'كتم',
              icon: Icon(
                widget.audioController.isMuted
                    ? Icons.volume_off
                    : Icons.volume_up,
              ),
              onPressed: () => widget.audioController.toggleMute(),
            ),
          ),
          IconButton(
            tooltip: 'الكلمة السابقة',
            icon: const Icon(Icons.chevron_right),
            onPressed:
                _wordIndex > 0 ? () => _moveWord(-1) : null,
          ),
          Text(
            '${_wordIndex + 1} / $_mapWordCount',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
          IconButton(
            tooltip: 'الكلمة التالية',
            icon: const Icon(Icons.chevron_left),
            onPressed: _wordIndex < _mapWordCount - 1
                ? () => _moveWord(1)
                : null,
          ),
          IconButton(
            tooltip: 'مشاركة',
            icon: const Icon(Icons.share),
            onPressed: _share,
          ),
          IconButton(
            tooltip: 'إغلاق',
            icon: const Icon(Icons.close),
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
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionButton(
            Icons.play_arrow,
            'استماع',
            () => widget.onPlayWord(_wordIndex),
          ),
          _actionButton(
            Icons.settings,
            'الإعدادات',
            widget.onOpenSettings,
          ),
          _actionButton(
            Icons.bookmark,
            'فاصل',
            widget.onToggleBookmark,
            active: widget.isBookmarked,
          ),
          _actionButton(
            Icons.comment,
            'تعليق',
            () {
              Navigator.of(context).pop();
              widget.onOpenNotes();
            },
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
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        icon,
        color: active ? _gold : Colors.white,
        size: 20,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: active ? _gold : Colors.white,
          fontSize: 13,
        ),
      ),
    );
  }
}
