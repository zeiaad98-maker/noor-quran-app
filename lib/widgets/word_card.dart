import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;

import '../data/qcf_word_map.dart';
import '../data/surah_sciences.dart';
import '../data/tafsir_downloads.dart';
import '../data/word_meanings.dart';

/// v12 word card + tafsir card (replaces the v10/v11 tabbed popup).
///
/// The user rejected the tabbed popup ("الكلمات والايات كل هذه
/// التبويبات مو زابطة") and ordered a design with NO tabs: tap a word
/// → one small card (word + meaning, toolbar swaps the content
/// INSIDE the same card); tap the verse-end number ۝ → the tafsir
/// card. The sample images in ~/workspace/your_files/
/// (sample-word-card-v2, sample-word-tafsir, sample-word-sarf,
/// sample-word-irab) are the spec.

const _green = Color(0xFF0D6E52);
const _cream = Color(0xFFFBF6E9);

/// Arabic-Indic digits for counters ("الكلمة ٨ من ٤٦").
String arabicIndic(int n) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  return n
      .toString()
      .split('')
      .map((c) => digits[int.parse(c)])
      .join();
}

// ---------------------------------------------------------------------
// Sarf parsing (pure — pinned by tests)
// ---------------------------------------------------------------------

/// The صرف fields parsed out of the bundled morphology description
/// (e.g. "اسم مفعول مرفوع، جمع مؤنث، نعت، نكرة، الجذر (حكم)،
/// الوزن (أَفْعَلَ)").
class SarfFields {
  final String? root; // حكم
  final String? type; // اسم مفعول مرفوع
  final String? plural; // جمع مؤنث سالم
  final String? singular; // مُحْكَمَة
  final String fullDesc;

  const SarfFields({
    this.root,
    this.type,
    this.plural,
    this.singular,
    required this.fullDesc,
  });
}

/// Parses a morphology description into labelled صرف fields.
///
/// The singular is derived ONLY for the regular sound plurals, where
/// the derivation is certain: feminine اتٌ/اتٍ/اتً → ة، masculine
/// ونَ/ينَ → strip the suffix. For broken plurals (جمع تكسير) no
/// singular is shown — the bundled data does not record it, and it
/// must not be guessed.
///
/// The word may arrive in QCF spelling (dagger alef ٰ for ا, and ۡ
/// for the sukun) — the endings are checked on a normalized copy, so
/// مُّحۡكَمَٰتٌ derives the same singular as مُّحْكَمَاتٌ.
SarfFields parseSarf(String desc, String word) {
  final normWord = _normalizeQcf(word);
  final segments =
      desc.split('،').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final rootMatch = RegExp(r'الجذر \(([^)]+)\)').firstMatch(desc);
  final root = rootMatch?.group(1);

  String? plural;
  String? singular;
  for (final segment in segments) {
    if (!segment.contains('جمع')) continue;
    plural = segment;
    if (normWord.endsWith('اتٌ') ||
        normWord.endsWith('اتٍ') ||
        normWord.endsWith('اتً')) {
      plural = '$segment سالم';
      singular = '${normWord.substring(0, normWord.length - 3)}ة';
    } else if (normWord.endsWith('ونَ') || normWord.endsWith('ينَ')) {
      plural = '$segment سالم';
      // The stem keeps the case vowel on its last letter
      // (مُسْلِمُونَ → مُسْلِمُ) — drop that one trailing diacritic
      // so the singular is bare (مُسْلِم).
      var stem = normWord.substring(0, normWord.length - 3);
      if (stem.isNotEmpty && _isDiacritic(stem.codeUnitAt(stem.length - 1))) {
        stem = stem.substring(0, stem.length - 1);
      }
      singular = stem;
    }
    break;
  }

  return SarfFields(
    root: root,
    type: segments.isEmpty ? null : segments.first,
    plural: plural,
    singular: singular,
    fullDesc: desc,
  );
}

/// Normalizes QCF spelling to the plain spelling the morphology data
/// uses: dagger alef ٰ (U+0670) → ا, small high ligature ۡ (U+06E1)
/// → sukun ْ. Everything else is left untouched.
String _normalizeQcf(String word) =>
    word.replaceAll('\u0670', 'ا').replaceAll('\u06E1', 'ْ');

/// Arabic diacritic (tashkeel) code unit: 064B–0652.
bool _isDiacritic(int codeUnit) => codeUnit >= 0x064B && codeUnit <= 0x0652;

// ---------------------------------------------------------------------
// Word card
// ---------------------------------------------------------------------

enum _WordMode { meaning, sarf, irab }

/// Shows the small word card as a centred dialog.
///
/// [wordIndex] is the TRUE 0-based Uthmani word index from the QCF
/// word map (the same index the audio controller takes +1).
Future<void> showWordCard({
  required BuildContext context,
  required int surah,
  required int verse,
  required int wordIndex,
  required void Function(int wordIndex) onPlayWord,
}) {
  return showDialog(
    context: context,
    builder: (context) => WordCard(
      surah: surah,
      verse: verse,
      wordIndex: wordIndex,
      onPlayWord: onPlayWord,
    ),
  );
}

class WordCard extends StatefulWidget {
  final int surah;
  final int verse;
  final int wordIndex;
  final void Function(int wordIndex) onPlayWord;

  const WordCard({
    super.key,
    required this.surah,
    required this.verse,
    required this.wordIndex,
    required this.onPlayWord,
  });

  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  late final List<QcfWordInfo> _words;
  late int _wordIndex;
  _WordMode _mode = _WordMode.meaning;
  String? _gloss;
  String? _morph;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // True words from the QCF word map (not the morphology entries:
    // those merge بَعۡدَ مَا in 2:181 etc. and would shift the count).
    _words = buildQcfWordMap(widget.surah, widget.verse).words;
    _wordIndex = widget.wordIndex.clamp(0, _words.length - 1);
    _loadWord();
  }

  String get _wordText => _words[_wordIndex].text;
  String get _lookupText => _words[_wordIndex].lookupText;

  Future<void> _loadWord() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      QuranWordData.wordGloss(widget.surah, widget.verse, _lookupText),
      QuranWordData.morphForWord(widget.surah, widget.verse, _lookupText),
    ]);
    if (!mounted) return;
    setState(() {
      _gloss = results[0];
      _morph = results[1];
      _loading = false;
    });
  }

  void _goToWord(int index) {
    if (index < 0 || index >= _words.length || index == _wordIndex) return;
    setState(() => _wordIndex = index);
    _loadWord();
  }

  String get _modeLabel {
    switch (_mode) {
      case _WordMode.meaning:
        return 'المعنى';
      case _WordMode.sarf:
        return 'صرف';
      case _WordMode.irab:
        return 'إعراب';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: isDark ? const Color(0xFF1E1F1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // The pill shows the current section; tapping it
                  // returns to المعنى (the toolbar has استمع/صرف/إعراب
                  // only — there is no other way back to the meaning).
                  Tooltip(
                    message: 'عرض المعنى',
                    child: InkWell(
                      key: const ValueKey('modePill'),
                      borderRadius: BorderRadius.circular(20),
                      onTap: _mode == _WordMode.meaning
                          ? null
                          : () => setState(() => _mode = _WordMode.meaning),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(color: _green, width: 1.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _modeLabel,
                          style: GoogleFonts.amiri(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _green,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: Colors.grey,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _wordText,
                textAlign: TextAlign.center,
                style: GoogleFonts.amiri(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: _green,
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _modeBody(),
                ),
              ),
              const SizedBox(height: 10),
              _toolbar(),
              const SizedBox(height: 8),
              _counterRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeBody() {
    switch (_mode) {
      case _WordMode.meaning:
        return Text(
          _gloss ?? 'كلمة من كلمات القرآن الكريم',
          textAlign: TextAlign.center,
          style: GoogleFonts.amiri(fontSize: 19),
        );
      case _WordMode.sarf:
        return _sarfBody();
      case _WordMode.irab:
        return _irabBody();
    }
  }

  Widget _sarfBody() {
    final morph = _morph;
    if (morph == null) {
      return Text(
        'لا يوجد صرف لهذه الكلمة في البيانات.',
        textAlign: TextAlign.center,
        style: GoogleFonts.amiri(fontSize: 18),
      );
    }
    final fields = parseSarf(morph, _wordText);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fields.root != null) _sarfRow('الجذر', fields.root!),
        if (fields.type != null) _sarfRow('النوع', fields.type!),
        if (fields.plural != null) _sarfRow('الجمع', fields.plural!),
        if (fields.singular != null) _sarfRow('المفرد', fields.singular!),
        const SizedBox(height: 8),
        Text(
          'الوصف الكامل: $morph',
          style: GoogleFonts.amiri(fontSize: 15, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _sarfRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.amiri(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: _green,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.amiri(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _irabBody() {
    final morph = _morph;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (morph != null)
          Text(
            morph,
            textAlign: TextAlign.center,
            style: GoogleFonts.amiri(fontSize: 19),
          )
        else
          Text(
            'لا يوجد إعراب مبسّط لهذه الكلمة.',
            textAlign: TextAlign.center,
            style: GoogleFonts.amiri(fontSize: 18),
          ),
        const SizedBox(height: 12),
        Text(
          'الإعراب هنا مبسّط من بيانات الصرف (الجذر ونوع الكلمة وحركتها)، وليس إعراباً تفصيلياً كاملاً.',
          textAlign: TextAlign.center,
          style: GoogleFonts.amiri(fontSize: 13, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _toolbar() {
    // Loose fit (not Expanded): each button sizes to its content,
    // so the row fits even in the wide test font — and comfortably
    // in the real Amiri font on the phone.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: _toolButton(
            icon: Icons.volume_up,
            label: 'استمع',
            active: false,
            onPressed: () {
              final index = _wordIndex;
              Navigator.of(context).pop();
              widget.onPlayWord(index);
            },
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: _toolButton(
            label: 'صرف',
            active: _mode == _WordMode.sarf,
            onPressed: () => setState(() => _mode = _WordMode.sarf),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: _toolButton(
            label: 'إعراب',
            active: _mode == _WordMode.irab,
            onPressed: () => setState(() => _mode = _WordMode.irab),
          ),
        ),
      ],
    );
  }

  Widget _toolButton({
    IconData? icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? _green : null,
        foregroundColor: active ? Colors.white : _green,
        side: const BorderSide(color: _green),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 4),
          ],
          Text(label, style: GoogleFonts.amiri(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _counterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          color: _wordIndex > 0 ? _green : Colors.grey,
          tooltip: 'الكلمة السابقة',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed:
              _wordIndex > 0 ? () => _goToWord(_wordIndex - 1) : null,
        ),
        const SizedBox(width: 6),
        Text(
          'الكلمة ${arabicIndic(_wordIndex + 1)} من ${arabicIndic(_words.length)}',
          style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          color:
              _wordIndex < _words.length - 1 ? _green : Colors.grey,
          tooltip: 'الكلمة التالية',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: _wordIndex < _words.length - 1
              ? () => _goToWord(_wordIndex + 1)
              : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// Tafsir card
// ---------------------------------------------------------------------

/// Shows the tafsir card as a centred dialog (opened by tapping the
/// verse-end number ۝).
///
/// Ayah in a cream box + the selected tafsir + أسباب النزول when the
/// ayah has an entry + استمع للآية / ملاحظاتي. The tafsir name is a
/// selector pill that opens the 6-tafsir menu.
Future<void> showTafsirCard({
  required BuildContext context,
  required int surah,
  required int verse,
  required TafsirService tafsirService,
  required VoidCallback onPlayAyah,
  required VoidCallback onOpenNotes,
}) {
  return showDialog(
    context: context,
    builder: (context) => TafsirCard(
      surah: surah,
      verse: verse,
      tafsirService: tafsirService,
      onPlayAyah: onPlayAyah,
      onOpenNotes: onOpenNotes,
    ),
  );
}

class TafsirCard extends StatefulWidget {
  final int surah;
  final int verse;
  final TafsirService tafsirService;
  final VoidCallback onPlayAyah;
  final VoidCallback onOpenNotes;

  const TafsirCard({
    super.key,
    required this.surah,
    required this.verse,
    required this.tafsirService,
    required this.onPlayAyah,
    required this.onOpenNotes,
  });

  @override
  State<TafsirCard> createState() => _TafsirCardState();
}

class _TafsirCardState extends State<TafsirCard> {
  String? _tafsirText;
  List<String> _asbab = const [];
  bool _loading = true;
  String? _loadedForId;

  @override
  void initState() {
    super.initState();
    widget.tafsirService.addListener(_onServiceChanged);
    _load();
  }

  @override
  void dispose() {
    widget.tafsirService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    // The user may have picked another tafsir or finished a download
    // in the selector sheet above this card — reload when that happens.
    final id = widget.tafsirService.selectedId;
    final available =
        widget.tafsirService.statusOf(id) == TafsirStatus.downloaded;
    if (id != _loadedForId || (available && _tafsirText == null)) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.tafsirService.selectedId;
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.tafsirService
          .selectedTafsirForAyah(widget.surah, widget.verse),
      SurahSciences.asbabForAyah(widget.surah, widget.verse),
    ]);
    if (!mounted) return;
    setState(() {
      _tafsirText = results[0] as String?;
      _asbab = results[1] as List<String>;
      _loadedForId = id;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final service = widget.tafsirService;
    final selected = service.selected;
    final available = service.statusOf(selected.id) ==
        TafsirStatus.downloaded;
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: isDark ? const Color(0xFF1E1F1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ListenableBuilder(
                    listenable: service,
                    builder: (context, _) => TextButton.icon(
                      onPressed: () => showTafsirSelector(
                        context: context,
                        service: service,
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      label: Text(
                        service.selected.name,
                        style: GoogleFonts.amiri(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _green,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        side: const BorderSide(color: _green),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: Colors.grey,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2A2B29)
                              : _cream,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              quran.getVerse(widget.surah, widget.verse),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.amiri(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'سورة ${quran.getSurahNameArabic(widget.surah)} • الآية ${widget.verse}',
                              style: GoogleFonts.amiri(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (!available)
                        _downloadPrompt(selected)
                      else if (_tafsirText == null)
                        Text(
                          'لا يوجد تفسير لهذه الآية في ${selected.name}.',
                          style: GoogleFonts.amiri(fontSize: 17),
                        )
                      else
                        Text(
                          _tafsirText!,
                          style: GoogleFonts.amiri(fontSize: 17),
                        ),
                      if (_asbab.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'أسباب النزول',
                          style: GoogleFonts.amiri(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _green,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final occasion in _asbab) ...[
                          Text(
                            occasion,
                            style: GoogleFonts.amiri(fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onPlayAyah();
                      },
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: Text(
                        'استمع للآية',
                        style: GoogleFonts.amiri(fontSize: 16),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onOpenNotes();
                      },
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: Text(
                        'ملاحظاتي',
                        style: GoogleFonts.amiri(fontSize: 16),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green,
                        side: const BorderSide(color: _green),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _downloadPrompt(TafsirInfo info) {
    return ListenableBuilder(
      listenable: widget.tafsirService,
      builder: (context, _) {
        final service = widget.tafsirService;
        final status = service.statusOf(info.id);
        final progress = service.progressOf(info.id);
        if (status == TafsirStatus.downloading) {
          return Column(
            children: [
              Text(
                'جارٍ تحميل ${info.name}…',
                style: GoogleFonts.amiri(fontSize: 16),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade300,
                color: _green,
              ),
              if (progress != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).round()}٪',
                  style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
                ),
              ],
            ],
          );
        }
        return Column(
          children: [
            Text(
              '${info.name} غير مثبّت بعد — حمّله مرة واحدة، ويعمل بعدها بدون إنترنت.',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(fontSize: 16),
            ),
            if (status == TafsirStatus.failed) ...[
              const SizedBox(height: 6),
              Text(
                'تعذّر التحميل: ${service.errorOf(info.id) ?? ''}',
                textAlign: TextAlign.center,
                style: GoogleFonts.amiri(fontSize: 14, color: Colors.red),
              ),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: () => service.download(info),
              icon: const Icon(Icons.download, size: 20),
              label: Text(
                status == TafsirStatus.failed ? 'إعادة المحاولة' : 'تحميل',
                style: GoogleFonts.amiri(fontSize: 16),
              ),
              style: FilledButton.styleFrom(backgroundColor: _green),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------
// Tafsir selector (6 rows, no tabs)
// ---------------------------------------------------------------------

/// Bottom sheet listing the six tafsirs. A row is tappable when the
/// tafsir is available (bundled / downloaded): it becomes the current
/// tafsir. Otherwise the row offers تحميل (once, background,
/// resumable, offline after) and shows progress while downloading.
Future<void> showTafsirSelector({
  required BuildContext context,
  required TafsirService service,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1F1E)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: ListenableBuilder(
        listenable: service,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'اختر التفسير',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (final info in kTafsirs)
              _TafsirRow(
                info: info,
                service: service,
                onSelected: () => Navigator.of(context).pop(),
              ),
            const SizedBox(height: 8),
            Text(
              'التفسير الميسر مدمج في التطبيق. باقي التفاسير تُحمَّل مرة واحدة وتعمل بعدها بدون إنترنت، ولا تكبّر حجم التطبيق.',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TafsirRow extends StatelessWidget {
  final TafsirInfo info;
  final TafsirService service;
  final VoidCallback onSelected;

  const _TafsirRow({
    required this.info,
    required this.service,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final status = service.statusOf(info.id);
    final isCurrent = service.selectedId == info.id;
    final available = status == TafsirStatus.downloaded;
    final progress = service.progressOf(info.id);
    return InkWell(
      onTap: available
          ? () async {
              await service.select(info.id);
              onSelected();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isCurrent ? _green : Colors.grey,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    style: GoogleFonts.amiri(
                      fontSize: 17,
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (isCurrent)
                    Text(
                      'الحالي',
                      style: GoogleFonts.amiri(
                          fontSize: 13, color: _green),
                    ),
                  if (status == TafsirStatus.downloading) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.grey.shade300,
                      color: _green,
                    ),
                  ],
                  if (status == TafsirStatus.failed)
                    Text(
                      'تعذّر التحميل — جرّب مجدداً',
                      style: GoogleFonts.amiri(
                          fontSize: 13, color: Colors.red),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (available)
              Text(
                'مثبّت ✓',
                style: GoogleFonts.amiri(fontSize: 14, color: _green),
              )
            else if (!info.available)
              // The extraction for this tafsir failed: no download
              // exists, so no تحميل button — say so honestly.
              Text(
                'غير متوفر بعد',
                style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
              )
            else if (status == TafsirStatus.downloading)
              Text(
                progress != null ? '${(progress * 100).round()}٪' : '…',
                style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
              )
            else
              FilledButton(
                onPressed: () => service.download(info),
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                ),
                child: Text(
                  status == TafsirStatus.failed ? 'إعادة' : 'تحميل',
                  style: GoogleFonts.amiri(fontSize: 15),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Surah sciences sheet ("عن السورة" — no tabs, one scroll)
// ---------------------------------------------------------------------

/// Bottom sheet with everything about the current surah: أسماء /
/// نزول / مقاصد / فضائل / عدد آيات / إحصائيات. One scroll, section
/// headings, no tabs.
Future<void> showSurahSciencesSheet({
  required BuildContext context,
  required int surah,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => SurahSciencesSheet(surah: surah),
  );
}

class SurahSciencesSheet extends StatefulWidget {
  final int surah;

  const SurahSciencesSheet({super.key, required this.surah});

  @override
  State<SurahSciencesSheet> createState() => _SurahSciencesSheetState();
}

class _SurahSciencesSheetState extends State<SurahSciencesSheet> {
  SurahInfo? _info;
  SurahScience? _science;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      SurahSciences.infoForSurah(widget.surah),
      SurahSciences.scienceForSurah(widget.surah),
    ]);
    if (!mounted) return;
    setState(() {
      _info = results[0] as SurahInfo?;
      _science = results[1] as SurahScience?;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stats = SurahSciences.statsForSurah(widget.surah);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1F1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'عن سورة ${quran.getSurahNameArabic(widget.surah)}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _section(
                    'أسماء السورة',
                    _namesBody(),
                  ),
                  _section(
                    'نزول السورة',
                    _nuzulBody(),
                  ),
                  _section(
                    'مقاصد السورة',
                    _maqsadBody(),
                  ),
                  _section(
                    'فضائل السورة',
                    _fadailBody(),
                  ),
                  _section(
                    'عدد آيات السورة',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow('عدد الآيات', '${stats.ayahCount}'),
                        _infoRow('عدد الكلمات', '${stats.wordCount}'),
                        _infoRow('عدد الحروف', '${stats.letterCount}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'المصادر: مصاعد النظر للبقاعي؛ موسوعة فضائل سور وآيات القرآن (القسم الصحيح)؛ معلومات النزول من Dalail وquran.com.',
                    style:
                        GoogleFonts.amiri(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _section(String title, Widget body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: GoogleFonts.amiri(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _green,
            ),
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _namesBody() {
    final science = _science;
    if (science == null ||
        ((science.names == null || science.names!.isEmpty) &&
            science.namesVerbatim == null)) {
      return _noteText(
        'لم يذكر البقاعي أسماء أخرى لهذه السورة في مصاعد النظر — المتوفر الاسم المعروف فقط.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (science.names != null && science.names!.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final name in science.names!)
                Chip(
                  label: Text(name),
                  backgroundColor: const Color(0xFFE8F5E9),
                  side: BorderSide.none,
                ),
            ],
          ),
        if (science.namesVerbatim != null) ...[
          const SizedBox(height: 10),
          _bodyText(science.namesVerbatim!),
        ],
        if (science.namesEtymology != null) ...[
          const SizedBox(height: 10),
          _bodyText(science.namesEtymology!),
        ],
      ],
    );
  }

  Widget _nuzulBody() {
    final info = _info;
    final science = _science;
    if (info == null) {
      return _noteText('معلومات النزول غير متوفرة لهذه السورة.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow('مكان النزول', info.revelationPlaceAr),
        _infoRow('ترتيب النزول', '${info.revelationOrder}'),
        _infoRow(
          'الصفحات',
          info.pageStart == info.pageEnd
              ? 'صفحة ${info.pageStart}'
              : 'من صفحة ${info.pageStart} إلى ${info.pageEnd}',
        ),
        if (science?.nuzulVerbatim != null) ...[
          const SizedBox(height: 10),
          _bodyText(science!.nuzulVerbatim!),
        ],
      ],
    );
  }

  Widget _maqsadBody() {
    final science = _science;
    if (science?.maqsadVerbatim == null) {
      return _noteText('مقاصد هذه السورة غير متوفرة حالياً.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bodyText(science!.maqsadVerbatim!),
        if (science.maqsadShort != null) ...[
          const SizedBox(height: 10),
          _bodyText('الخلاصة: ${science.maqsadShort!}'),
        ],
      ],
    );
  }

  Widget _fadailBody() {
    final science = _science;
    if (science == null ||
        (science.fadailHeadline == null && science.fadailHadith == null)) {
      return _noteText(
        'لا يوجد باب لهذه السورة في القسم الصحيح من موسوعة فضائل سور وآيات القرآن.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (science.fadailHeadline != null) ...[
          _bodyText(science.fadailHeadline!),
          const SizedBox(height: 8),
        ],
        if (science.fadailHadith != null) _bodyText(science.fadailHadith!),
        if (science.fadailSource != null) ...[
          const SizedBox(height: 8),
          Text(
            'المصدر: ${science.fadailSource!}',
            style: GoogleFonts.amiri(fontSize: 13, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: GoogleFonts.amiri(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.amiri(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _bodyText(String text) {
    return Text(text, style: GoogleFonts.amiri(fontSize: 16));
  }

  Widget _noteText(String text) {
    return Text(
      text,
      style: GoogleFonts.amiri(
        fontSize: 15,
        color: Colors.grey,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}
