import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;

import '../data/audio_player_controller.dart';
import '../data/ayah_marks.dart';
import '../data/ayah_notes.dart';
import '../data/qcf_word_map.dart';
import '../data/qiraat_data.dart';
import '../data/quran_audio.dart';
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
///
/// v13.3 (FIX B): the card is restyled EXACTLY like the SurahApp
/// popup the user approved (sample-v133-word-popup.png): cream popup,
/// المعنى pill, the word big in green, the SHORT plain meaning, and
/// the khaki toolbar استماع / فاصل / تلوين / تعليقات / المزيد.
/// صرف / إعراب / التفسير moved into المزيد; the "استمع للآية"
/// button stays (v13.2 UX D). The card also shows the word audio's
/// own loading state (spinner + honest progress + إلغاء) and its
/// failure state (plain message + إعادة المحاولة) — the approved
/// sample-v133-word-loading.png.

const _green = Color(0xFF0D6E52);
const _cream = Color(0xFFFBF6E9);
const _khaki = Color(0xFFE7E2CF);

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
// Word card — Wahy style (v13.6)
// ---------------------------------------------------------------------

/// The Wahy-style word card (v13.6): the approved sample
/// ~/workspace/your_files/sample-word-card-wahy-v2.png is the spec —
/// a cream bottom sheet, NOT the old centred dialog: ayah header
/// with the tapped word in blue; 4 tabs (المعنى/التصريف/الإعراب/
/// القراءات); right column of 4 round buttons; آخر قراءة bar;
/// ملاحظة/تفاسير row; bottom bar (playback settings, reciter pill,
/// استمرار, الآية).
///
/// EVERY button is wired to a working function (the user's order:
/// "فعّلوا كل الأزرار") — there are no dead buttons. The word's own
/// audio state never hides the meaning any more (the v13.5 bug: the
/// card showed "جارٍ تحميل الصوت..." instead of the meaning): the
/// meaning is always visible, and the loading spinner lives INSIDE
/// the green play button; a failure shows a small retry row under
/// the tabs.

const _blue = Color(0xFF2E7FD1);

enum _WahyTab { meaning, sarf, irab, qiraat }

/// Shows the Wahy-style word card as a bottom sheet.
///
/// [wordIndex] is the TRUE 0-based Uthmani word index from the QCF
/// word map (the same index the audio controller takes +1).
/// Every button has a working callback: [onPlayWord] (green ▶),
/// [onRepeatWord] (circled ▶ — repeats the word [repeatCount]
/// times, never the reciter-voice clip), [onPlayAyah] (الآية),
/// [onPlayPage] (الصفحة — v13.9: opens the player sheet on the
/// page scope and plays the whole current page),
/// [onContinueFromAyah] (استمرار — the surah from this ayah on),
/// [onGoToLastReading] (آخر قراءة), [onOpenTafsir] (تفاسير),
/// [onOpenReciterPicker] (reciter pill),
/// [onOpenPlaybackSettings] (bottom-left gear). The magnifier and
/// the gear open the card's own sheets (word details / word
/// settings) — no callback needed. The note editor lives INSIDE the
/// card (v13.8 one-card rule — the old ayah sheet is gone): the
/// ملاحظة pill toggles it in place; [onOpenNotesScreen] is only the
/// «ملاحظاتي» link inside that editor, opening the notes list.
/// [pageNumber] feeds the card's info line (الجزء • الربع • صفحة).
Future<void> showWordCard({
  required BuildContext context,
  required int surah,
  required int verse,
  required int wordIndex,
  required int pageNumber,
  required AudioPlayerController audioController,
  required void Function(int wordIndex) onPlayWord,
  required void Function(int wordIndex) onRepeatWord,
  required VoidCallback onPlayAyah,
  required VoidCallback onPlayPage,
  required VoidCallback onContinueFromAyah,
  required VoidCallback onGoToLastReading,
  required VoidCallback onOpenNotesScreen,
  required VoidCallback onOpenTafsir,
  required VoidCallback onOpenReciterPicker,
  required VoidCallback onOpenPlaybackSettings,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => WordCard(
      surah: surah,
      verse: verse,
      wordIndex: wordIndex,
      pageNumber: pageNumber,
      audioController: audioController,
      onPlayWord: onPlayWord,
      onRepeatWord: onRepeatWord,
      onPlayAyah: onPlayAyah,
      onPlayPage: onPlayPage,
      onContinueFromAyah: onContinueFromAyah,
      onGoToLastReading: onGoToLastReading,
      onOpenNotesScreen: onOpenNotesScreen,
      onOpenTafsir: onOpenTafsir,
      onOpenReciterPicker: onOpenReciterPicker,
      onOpenPlaybackSettings: onOpenPlaybackSettings,
    ),
  );
}

class WordCard extends StatefulWidget {
  final int surah;
  final int verse;
  final int wordIndex;
  final int pageNumber;
  final AudioPlayerController audioController;
  final void Function(int wordIndex) onPlayWord;
  final void Function(int wordIndex) onRepeatWord;
  final VoidCallback onPlayAyah;
  final VoidCallback onPlayPage;
  final VoidCallback onContinueFromAyah;
  final VoidCallback onGoToLastReading;
  final VoidCallback onOpenNotesScreen;
  final VoidCallback onOpenTafsir;
  final VoidCallback onOpenReciterPicker;
  final VoidCallback onOpenPlaybackSettings;

  const WordCard({
    super.key,
    required this.surah,
    required this.verse,
    required this.wordIndex,
    required this.pageNumber,
    required this.audioController,
    required this.onPlayWord,
    required this.onRepeatWord,
    required this.onPlayAyah,
    required this.onPlayPage,
    required this.onContinueFromAyah,
    required this.onGoToLastReading,
    required this.onOpenNotesScreen,
    required this.onOpenTafsir,
    required this.onOpenReciterPicker,
    required this.onOpenPlaybackSettings,
  });

  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  late final List<QcfWordInfo> _words;
  // Mutable since v13.8: tapping another word in the ayah header
  // switches the card to that word in place (no close/reopen).
  late int _wordIndex;
  // One tap recognizer per header word, built once (the words of
  // the ayah never change) and disposed with the card.
  late final List<TapGestureRecognizer> _wordTapRecognizers;
  _WahyTab _tab = _WahyTab.meaning;
  String? _gloss;
  // v13.9: which source the meaning comes from (see
  // QuranWordData.glossSourceForWord): 'tafsircenter' / 'addition' /
  // 'makhloof' / 'gharib' / 'lexicon' = a real meaning; 'morph' /
  // 'none' = no meaning source matched, so the المعنى tab says so
  // honestly instead of showing the morphology text (which is what
  // the الإعراب tab already shows).
  String? _glossSource;
  String? _morph;
  // v13.11: Tafsir Center sarf + per-word i'rab (full text) and
  // their sources ('tafsircenter' / 'morph' / 'none') — the
  // التصريف/الإعراب tabs show the Center's text first, with the
  // small credit line, and fall back to the simplified morphology.
  String? _sarf;
  String? _irab;
  String? _sarfSource;
  String? _irabSource;
  List<QiraatVariant> _qiraatForWord = const [];
  List<QiraatVariant> _qiraatForAyah = const [];
  bool _loading = true;
  bool _isBookmarked = false;
  bool _hasNote = false;
  // v13.8 (one-card rule): the note editor lives inside this card.
  String? _noteText;
  String? _quarterLabel;
  bool _showNoteEditor = false;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    // True words from the QCF word map (not the morphology entries:
    // those merge بَعۡدَ مَا in 2:181 etc. and would shift the count).
    _words = buildQcfWordMap(widget.surah, widget.verse).words;
    _wordIndex = widget.wordIndex.clamp(0, _words.length - 1);
    _wordTapRecognizers = List.generate(
      _words.length,
      (i) => TapGestureRecognizer()..onTap = () => _switchWord(i),
    );
    _noteController = TextEditingController();
    _loadWord();
  }

  @override
  void dispose() {
    _noteController.dispose();
    for (final r in _wordTapRecognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// v13.8: switch the card to another word of the same ayah, in
  /// place — the header tap. Resets to the المعنى tab; a tap on the
  /// word already shown does nothing. Does NOT play audio: the user
  /// only wants the meaning on tap; the green ▶ plays the word.
  void _switchWord(int index) {
    if (index == _wordIndex) return;
    setState(() {
      _wordIndex = index;
      _tab = _WahyTab.meaning;
    });
    _loadWord();
  }

  String get _wordText => _words[_wordIndex].text;
  String get _lookupText => _words[_wordIndex].lookupText;

  Future<void> _loadWord() async {
    // Generation guard (v13.8): a header tap can start a second load
    // while the first is in flight — a stale load must not overwrite
    // the word the card now shows.
    final index = _wordIndex;
    setState(() => _loading = true);
    final results = await Future.wait([
      QuranWordData.wordGloss(widget.surah, widget.verse, _lookupText),
      QuranWordData.morphForWord(widget.surah, widget.verse, _lookupText),
      QiraatData.variantsForWord(
          widget.surah, widget.verse, _wordIndex, _lookupText),
      QiraatData.variantsForAyah(widget.surah, widget.verse),
      AyahBookmarks.isBookmarked(widget.surah, widget.verse),
      AyahNotes.getNote(widget.surah, widget.verse),
      QuranWordData.hizbQuarterLabel(widget.surah, widget.verse),
      QuranWordData.glossSourceForWord(
          widget.surah, widget.verse, _lookupText),
      QuranWordData.sarfForWord(widget.surah, widget.verse, _lookupText),
      QuranWordData.irabForWord(widget.surah, widget.verse, _lookupText),
      QuranWordData.sarfSourceForWord(
          widget.surah, widget.verse, _lookupText),
      QuranWordData.irabSourceForWord(
          widget.surah, widget.verse, _lookupText),
    ]);
    if (!mounted || index != _wordIndex) return;
    setState(() {
      _gloss = results[0] as String?;
      _morph = results[1] as String?;
      _qiraatForWord = results[2] as List<QiraatVariant>;
      _qiraatForAyah = results[3] as List<QiraatVariant>;
      _isBookmarked = results[4] as bool;
      _noteText = results[5] as String?;
      _hasNote = _noteText != null;
      _quarterLabel = results[6] as String?;
      _glossSource = results[7] as String?;
      _sarf = results[8] as String?;
      _irab = results[9] as String?;
      _sarfSource = results[10] as String?;
      _irabSource = results[11] as String?;
      _loading = false;
    });
  }

  Future<void> _toggleBookmark() async {
    final now = await AyahBookmarks.toggle(widget.surah, widget.verse);
    if (!mounted) return;
    setState(() => _isBookmarked = now);
  }

  /// v13.8: the ملاحظة pill toggles the inline editor — the card
  /// stays open. Opening it pre-fills the current note (if any).
  void _toggleNoteEditor() {
    setState(() {
      _showNoteEditor = !_showNoteEditor;
      if (_showNoteEditor) _noteController.text = _noteText ?? '';
    });
  }

  /// Save from the inline editor. An empty text deletes the note
  /// (the old sheet's rule). The editor closes; the saved note shows
  /// in the yellow box below and the pill icon turns green.
  Future<void> _saveNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty) {
      await AyahNotes.deleteNote(widget.surah, widget.verse);
    } else {
      await AyahNotes.saveNote(widget.surah, widget.verse, text);
    }
    if (!mounted) return;
    setState(() {
      _noteText = text.isEmpty ? null : text;
      _hasNote = text.isNotEmpty;
      _showNoteEditor = false;
    });
  }

  /// Delete from the inline editor (only offered when a note exists).
  Future<void> _deleteNote() async {
    await AyahNotes.deleteNote(widget.surah, widget.verse);
    if (!mounted) return;
    setState(() {
      _noteText = null;
      _hasNote = false;
      _showNoteEditor = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1F1E) : _cream;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      // The bottom bar (الآية / استمرار / reciter) is pinned OUTSIDE
      // the scroll area: it is the card's primary action row and must
      // stay visible and tappable even when the meaning is long (on a
      // short screen the scrollable middle shrinks instead of pushing
      // the bar below the fold — v13.6 fix). The Column is max-sized
      // (NOT min): a min Column gives its Flexible child unbounded
      // height, so the scroll view would size to its full content and
      // push the bar off-screen. Max-sized, the Column fills the
      // Container's 85% cap and the Flexible middle is bounded — the
      // sheet is always 85% tall, like Wahy's card.
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
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ayahHeader(isDark),
                  const SizedBox(height: 6),
                  _ayahInfoLine(),
                  const SizedBox(height: 10),
                  _tabsRow(),
                  _audioErrorRow(),
                  const SizedBox(height: 10),
                  _contentRow(isDark),
                  const SizedBox(height: 14),
                  Divider(
                      height: 1, color: Colors.grey.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  _lastReadingBar(isDark),
                  const SizedBox(height: 10),
                  _notesTafsirRow(isDark),
                  if (_showNoteEditor) ...[
                    const SizedBox(height: 10),
                    _noteEditor(isDark),
                  ],
                  if (_noteText != null && !_showNoteEditor) ...[
                    const SizedBox(height: 10),
                    _savedNoteBox(),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _bottomBar(isDark),
        ],
      ),
    );
  }

  Color get _boxColor =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2B29)
          : Colors.white;

  Color get _khakiColor =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF33342F)
          : _khaki;

  /// The whole ayah in a white box, the tapped word in blue, the
  /// verse number in a small medallion at the end (the sample's ٤).
  /// v13.8: every word is tappable — a tap switches the card to
  /// that word in place (see [_switchWord]), no close/reopen.
  Widget _ayahHeader(bool isDark) {
    final baseStyle = GoogleFonts.amiri(
      fontSize: 20,
      color: Theme.of(context).textTheme.bodyLarge?.color,
    );
    final spans = <InlineSpan>[];
    for (var i = 0; i < _words.length; i++) {
      final isTapped = i == _wordIndex;
      spans.add(TextSpan(
        text: _words[i].text,
        style: GoogleFonts.amiri(
          fontSize: 20,
          fontWeight: isTapped ? FontWeight.bold : FontWeight.normal,
          color: isTapped ? _blue : baseStyle.color,
        ),
        recognizer: _wordTapRecognizers[i],
      ));
      if (i < _words.length - 1) {
        spans.add(const TextSpan(text: ' '));
      }
    }
    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsetsDirectional.only(start: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _green, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          arabicIndic(widget.verse),
          style: GoogleFonts.amiri(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: _green,
          ),
        ),
      ),
    ));
    return Container(
      key: const ValueKey('ayahHeader'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _boxColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(style: baseStyle, children: spans),
      ),
    );
  }

  /// v13.8 (one-card rule): the old ayah sheet's info line lives
  /// here now — juz + hizb-quarter + page — so the number tap loses
  /// nothing when it opens this card instead of the sheet.
  Widget _ayahInfoLine() {
    final juz = quran.getJuzNumber(widget.surah, widget.verse);
    return Text(
      'الجزء $juz • ${_quarterLabel ?? '...'} • صفحة ${widget.pageNumber}',
      textAlign: TextAlign.center,
      style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
    );
  }

  /// v13.8: the note editor, inlined in the card (the old ayah
  /// sheet's AlertDialog, moved here) — gold-bordered box with the
  /// label, the text field, green حفظ, red حذف الملاحظة (only when
  /// a note exists), and the ملاحظاتي link to the notes list.
  /// The card stays open the whole time.
  Widget _noteEditor(bool isDark) {
    return Container(
      key: const ValueKey('noteEditor'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _boxColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8A723D), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ملاحظة على الآية',
            style: GoogleFonts.amiri(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _green,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('noteTextField'),
            controller: _noteController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'اكتب ملاحظتك أو فائدة من الآية...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('saveNoteButton'),
                  onPressed: _saveNote,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                  ),
                  child: Text(
                    'حفظ',
                    style: GoogleFonts.amiri(fontSize: 16),
                  ),
                ),
              ),
              if (_hasNote) ...[
                const SizedBox(width: 10),
                // Flexible + ellipsis: the three-button row must
                // never overflow — in the test font the delete label
                // runs 16px wide of the card.
                Flexible(
                  child: TextButton(
                    key: const ValueKey('deleteNoteButton'),
                    onPressed: _deleteNote,
                    child: Text(
                      'حذف الملاحظة',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.amiri(
                        fontSize: 15,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              TextButton(
                key: const ValueKey('myNotesButton'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onOpenNotesScreen();
                },
                child: Text(
                  'ملاحظاتي',
                  style: GoogleFonts.amiri(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The saved note, shown in the yellow box (the old sheet's box)
  /// once the editor closes — the visible confirmation of a save.
  Widget _savedNoteBox() {
    return Container(
      key: const ValueKey('savedNoteBox'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3C4).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _noteText!,
        style: GoogleFonts.amiri(
          fontSize: 16,
          color: const Color(0xFF2D2A26),
        ),
      ),
    );
  }

  /// Tabs row (المعنى selected = green pill) with the solid green ▶
  /// at the right edge. In RTL the first child is rightmost, so the
  /// play button sits at the right, the tabs fill to its left.
  Widget _tabsRow() {
    return Row(
      children: [
        _playButton(),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              _tabButton(_WahyTab.meaning, 'المعنى', 'tabMeaning'),
              _tabButton(_WahyTab.sarf, 'التصريف', 'tabSarf'),
              _tabButton(_WahyTab.irab, 'الإعراب', 'tabIrab'),
              _tabButton(_WahyTab.qiraat, 'القراءات', 'tabQiraat'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabButton(_WahyTab tab, String label, String keyName) {
    final selected = _tab == tab;
    return Expanded(
      child: InkWell(
        key: ValueKey(keyName),
        borderRadius: BorderRadius.circular(20),
        onTap: selected ? null : () => setState(() => _tab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected ? _green : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.amiri(
              fontSize: 16,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected
                  ? Colors.white
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ),
    );
  }

  /// The solid green ▶. While the word file downloads, the spinner
  /// lives INSIDE this button — the meaning is never hidden behind
  /// a loading state (the v13.5 bug).
  Widget _playButton() {
    return AnimatedBuilder(
      animation: widget.audioController,
      builder: (context, _) {
        final c = widget.audioController;
        final loading = c.scope == PlayerScope.word && c.isLoading;
        return InkWell(
          key: const ValueKey('playWordButton'),
          customBorder: const CircleBorder(),
          onTap: loading ? null : () => widget.onPlayWord(_wordIndex),
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: _green,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(Icons.play_arrow,
                    color: Colors.white, size: 32),
          ),
        );
      },
    );
  }

  /// Word-audio failure: a small retry row under the tabs. The
  /// meaning stays visible; only this row mentions the failure.
  Widget _audioErrorRow() {
    return AnimatedBuilder(
      animation: widget.audioController,
      builder: (context, _) {
        final c = widget.audioController;
        if (c.scope != PlayerScope.word || c.lastError == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'تعذّر تحميل الصوت',
                style: GoogleFonts.amiri(fontSize: 14, color: Colors.red),
              ),
              const SizedBox(width: 10),
              InkWell(
                key: const ValueKey('retryWordAudioButton'),
                onTap: () => unawaited(c.retryLastError()),
                child: Text(
                  'إعادة المحاولة',
                  style: GoogleFonts.amiri(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _green,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Content box + right column of 3 round buttons (repeat, word
  /// details, word settings). RTL: the column sits at the right.
  Widget _contentRow(bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _roundButton(
              keyName: 'repeatWordButton',
              icon: Icons.play_circle_outline,
              tooltip: 'تكرار الكلمة',
              onPressed: () => widget.onRepeatWord(_wordIndex),
            ),
            const SizedBox(height: 12),
            _roundButton(
              keyName: 'wordDetailsButton',
              icon: Icons.search,
              tooltip: 'تفاصيل الكلمة',
              onPressed: () => showWordDetailsSheet(
                context: context,
                surah: widget.surah,
                verse: widget.verse,
                wordText: _wordText,
                lookupText: _lookupText,
              ),
            ),
            const SizedBox(height: 12),
            _roundButton(
              keyName: 'wordSettingsButton',
              icon: Icons.settings,
              tooltip: 'إعدادات الكلمة',
              onPressed: () => showWordSettingsSheet(
                context: context,
                controller: widget.audioController,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 170),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _boxColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tabBody(),
          ),
        ),
      ],
    );
  }

  Widget _roundButton({
    required String keyName,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey(keyName),
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _boxColor,
            shape: BoxShape.circle,
            border: Border.all(color: _green, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: _green, size: 26),
        ),
      ),
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case _WahyTab.meaning:
        // v13.9: when no meaning source matched this word (source
        // 'morph' / 'none'), the meaning tab must NOT show the
        // morphology description — that text is what the الإعراب tab
        // already shows, and the two tabs were identical. Say so
        // honestly and point at the tafsir (one tap away in the card).
        if (_glossSource == 'morph' || _glossSource == 'none') {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'لا يوجد معنى مختصر لهذه الكلمة في المصادر المتوفرة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.amiri(fontSize: 19),
              ),
              const SizedBox(height: 12),
              Text(
                'معناها من سياق الآية — افتح «تفاسير» من البطاقة.',
                textAlign: TextAlign.center,
                style: GoogleFonts.amiri(fontSize: 13, color: Colors.grey),
              ),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _gloss ?? 'كلمة من كلمات القرآن الكريم',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(fontSize: 19),
            ),
            // v13.11: the Tafsir Center meanings are CC BY 4.0 — the
            // licence's free permission is conditional on attribution.
            // The user approved a small discreet line (his words:
            // «حط سطر صغير بالمصدر»), NOT a banner.
            if (_glossSource == 'tafsircenter') ...[
              const SizedBox(height: 10),
              Text(
                'المصدر: مركز تفسير للدراسات القرآنية — tafsir.net',
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.amiri(fontSize: 12, color: Colors.grey),
              ),
            ],
          ],
        );
      case _WahyTab.sarf:
        return _sarfBody();
      case _WahyTab.irab:
        return _irabBody();
      case _WahyTab.qiraat:
        return _qiraatBody();
    }
  }

  Widget _sarfBody() {
    // v13.11: Tafsir Center sarf FIRST — the Center's full analysis
    // (avg ~157 chars), shown in FULL, never shortened, with the
    // small approved credit line (CC BY 4.0 attribution, same line
    // as the المعنى tab). The parsed simplified morphology below is
    // fallback-only (the Center covers 100%, so it should never
    // fire — verified by the coverage test).
    if (_sarfSource == 'tafsircenter' && _sarf != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _sarf!,
            textAlign: TextAlign.center,
            style: GoogleFonts.amiri(fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            'المصدر: مركز تفسير للدراسات القرآنية — tafsir.net',
            textAlign: TextAlign.center,
            style: GoogleFonts.amiri(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }
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

  /// Per-word i'rab (v13.11): the Tafsir Center's full per-word
  /// analysis FIRST, shown in FULL with the small credit line. The
  /// simplified morphology display below is fallback-only (the
  /// Center covers 100%, so it should never fire — verified by the
  /// coverage test); its honest disclaimer stays, because when it
  /// shows, it IS a simplification, not a full i'rab.
  Widget _irabBody() {
    if (_irabSource == 'tafsircenter' && _irab != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _irab!,
            textAlign: TextAlign.center,
            style: GoogleFonts.amiri(fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            'المصدر: مركز تفسير للدراسات القرآنية — tafsir.net',
            textAlign: TextAlign.center,
            style: GoogleFonts.amiri(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }
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

  /// القراءات tab (v13.6): real variant readings from the bundled
  /// qiraat-variants data (MIT), matched to the tapped word by span
  /// AND word text. A word with no variant says so honestly; an
  /// ayah with no variant at all says so too.
  Widget _qiraatBody() {
    if (_qiraatForWord.isEmpty) {
      if (_qiraatForAyah.isEmpty) {
        return Text(
          'لا توجد قراءات مختلفة لهذه الآية في المصدر (القراءات العشر).',
          textAlign: TextAlign.center,
          style: GoogleFonts.amiri(fontSize: 18),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'هذه الكلمة تُقرأ بنفس اللفظ في القراءات العشر.',
            textAlign: TextAlign.center,
            style: GoogleFonts.amiri(fontSize: 18),
          ),
          const SizedBox(height: 12),
          Text(
            'قراءات أخرى في هذه الآية:',
            style: GoogleFonts.amiri(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _green,
            ),
          ),
          const SizedBox(height: 8),
          for (final v in _qiraatForAyah) _qiraatVariant(v),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final v in _qiraatForWord) ...[
          _qiraatVariant(v),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _qiraatVariant(QiraatVariant v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          v.word,
          textAlign: TextAlign.center,
          style: GoogleFonts.amiri(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _green,
          ),
        ),
        const SizedBox(height: 4),
        for (final r in v.readings)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              r.hafs
                  ? '${r.text} — ${r.readers.join('، ')} (قراءة المصحف)'
                  : '${r.text} — ${r.readers.join('، ')}',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 17,
                fontWeight: r.hafs ? FontWeight.bold : FontWeight.normal,
                color: r.hafs ? _green : null,
              ),
            ),
          ),
      ],
    );
  }

  /// The khaki bar: bookmark-add square + آخر قراءة pill.
  Widget _lastReadingBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _khakiColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          InkWell(
            key: const ValueKey('bookmarkButton'),
            borderRadius: BorderRadius.circular(10),
            onTap: _toggleBookmark,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _boxColor,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(
                _isBookmarked ? Icons.bookmark : Icons.bookmark_add_outlined,
                color: _green,
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            key: const ValueKey('lastReadingButton'),
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              Navigator.of(context).pop();
              widget.onGoToLastReading();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _boxColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'آخر قراءة',
                    style: GoogleFonts.amiri(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.bookmark, color: _green, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// تفاسير + ملاحظة pills. تفاسير pops the card and opens the
  /// tafsir card; ملاحظة toggles the INLINE note editor (v13.8) —
  /// the card stays open, no sheet branching off the card.
  Widget _notesTafsirRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _whitePill(
            keyName: 'tafsirButton',
            label: 'تفاسير',
            icon: Icons.menu_book,
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenTafsir();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _whitePill(
            keyName: 'notesButton',
            label: 'ملاحظة',
            icon: _hasNote ? Icons.note_alt : Icons.note_add_outlined,
            iconColor: _hasNote ? _green : null,
            onTap: _toggleNoteEditor,
          ),
        ),
      ],
    );
  }

  Widget _whitePill({
    required String keyName,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return InkWell(
      key: ValueKey(keyName),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _boxColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: GoogleFonts.amiri(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: iconColor ?? _green, size: 22),
          ],
        ),
      ),
    );
  }

  /// Bottom bar: الآية ▶ | استمرار | reciter pill | playback
  /// settings. RTL: the first child is rightmost.
  Widget _bottomBar(bool isDark) {
    return Row(
      children: [
        _bottomStack(
          keyName: 'playAyahButton',
          icon: Icons.play_circle_outline,
          label: 'الآية',
          onTap: () {
            Navigator.of(context).pop();
            widget.onPlayAyah();
          },
        ),
        const SizedBox(width: 8),
        _bottomStack(
          keyName: 'continueButton',
          icon: Icons.menu_book,
          label: 'استمرار',
          onTap: () {
            Navigator.of(context).pop();
            widget.onContinueFromAyah();
          },
        ),
        const SizedBox(width: 8),
        _bottomStack(
          keyName: 'playPageButton',
          icon: Icons.play_circle_outline,
          label: 'الصفحة',
          onTap: () {
            Navigator.of(context).pop();
            widget.onPlayPage();
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            key: const ValueKey('reciterButton'),
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.of(context).pop();
              widget.onOpenReciterPicker();
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _boxColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListenableBuilder(
                listenable: widget.audioController,
                builder: (context, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        widget.audioController.reciter.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.amiri(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.mic, color: _green, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          key: const ValueKey('playbackSettingsButton'),
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.of(context).pop();
            widget.onOpenPlaybackSettings();
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _boxColor,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.settings, color: _green, size: 24),
          ),
        ),
      ],
    );
  }

  Widget _bottomStack({
    required String keyName,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: ValueKey(keyName),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _green, size: 28),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.amiri(fontSize: 13, color: _green),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Word details sheet (magnifier) — v13.6
// ---------------------------------------------------------------------

/// The magnifier button's sheet: the word's full lexicon entry
/// (مفردات الراغب) + its full morphology description. Everything
/// shown comes from the bundled data; a missing entry says so.
Future<void> showWordDetailsSheet({
  required BuildContext context,
  required int surah,
  required int verse,
  required String wordText,
  required String lookupText,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _WordDetailsSheet(
      surah: surah,
      verse: verse,
      wordText: wordText,
      lookupText: lookupText,
    ),
  );
}

class _WordDetailsSheet extends StatefulWidget {
  final int surah;
  final int verse;
  final String wordText;
  final String lookupText;

  const _WordDetailsSheet({
    required this.surah,
    required this.verse,
    required this.wordText,
    required this.lookupText,
  });

  @override
  State<_WordDetailsSheet> createState() => _WordDetailsSheetState();
}

class _WordDetailsSheetState extends State<_WordDetailsSheet> {
  String? _lexicon;
  String? _morph;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      QuranWordData.lexiconForWord(
          widget.surah, widget.verse, widget.lookupText),
      QuranWordData.morphForWord(
          widget.surah, widget.verse, widget.lookupText),
    ]);
    if (!mounted) return;
    setState(() {
      _lexicon = results[0];
      _morph = results[1];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1F1E) : _cream;
    final root = _morph == null
        ? null
        : parseSarf(_morph!, widget.wordText).root;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: bg,
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
                  const SizedBox(height: 14),
                  Text(
                    widget.wordText,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.amiri(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                  ),
                  if (root != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'الجذر: $root',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.amiri(fontSize: 17, color: _green),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'المعجم (مفردات الراغب)',
                    style: GoogleFonts.amiri(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _lexicon ??
                        'لا يوجد تعريف معجمي لهذه الكلمة في مفردات الراغب.',
                    style: GoogleFonts.amiri(fontSize: 17),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'الصرف',
                    style: GoogleFonts.amiri(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _green,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _morph ?? 'لا يوجد وصف صرفي لهذه الكلمة في البيانات.',
                    style: GoogleFonts.amiri(fontSize: 17),
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------
// Word settings sheet (gear) + playback settings sheet — v13.6
// ---------------------------------------------------------------------

/// Choice chips for one setting (repeat count / speed): a Wrap of
/// ChoiceChips, the selected one filled green.
Widget _optionChips<T>({
  required List<(T, String)> options,
  required T selected,
  required void Function(T) onSelected,
}) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (value, label) in options)
        ChoiceChip(
          label: Text(
            label,
            style: GoogleFonts.amiri(
              fontSize: 15,
              color: value == selected ? Colors.white : null,
            ),
          ),
          selected: value == selected,
          selectedColor: _green,
          onSelected: (_) => onSelected(value),
        ),
    ],
  );
}

/// Repeat-count options, shared by both settings sheets. 0 =
/// endless (مستمر). Count 1 = play once = repeat off.
const _repeatOptions = <(int, String)>[
  (1, 'مرة واحدة'),
  (3, '٣ مرات'),
  (5, '٥ مرات'),
  (10, '١٠ مرات'),
  (0, 'مستمر'),
];

/// The gear button's sheet: auto-play the word on tap + the word
/// repeat count.
Future<void> showWordSettingsSheet({
  required BuildContext context,
  required AudioPlayerController controller,
}) {
  return showModalBottomSheet(
    context: context,
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
        listenable: controller,
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
              'إعدادات الكلمة',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            // Own Material: the sheet's DecoratedBox background would
            // otherwise hide the tile's ink (FlutterError in tests).
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                title: Text(
                  'تشغيل صوت الكلمة تلقائياً عند الضغط عليها',
                  style: GoogleFonts.amiri(fontSize: 16),
                ),
                value: controller.wordAutoPlay,
                activeThumbColor: _green,
                onChanged: controller.setWordAutoPlay,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'تكرار الكلمة',
              style: GoogleFonts.amiri(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _green,
              ),
            ),
            const SizedBox(height: 8),
            _optionChips<int>(
              options: _repeatOptions,
              selected: controller.repeatCount,
              onSelected: controller.setRepeatCount,
            ),
          ],
        ),
      ),
    ),
  );
}

/// The bottom-left gear's sheet: playback speed + the repeat count.
Future<void> showPlaybackSettingsSheet({
  required BuildContext context,
  required AudioPlayerController controller,
}) {
  return showModalBottomSheet(
    context: context,
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
        listenable: controller,
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
              'إعدادات التشغيل',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'السرعة',
              style: GoogleFonts.amiri(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _green,
              ),
            ),
            const SizedBox(height: 8),
            _optionChips<double>(
              options: const [
                (0.75, 'بطيئة 0.75×'),
                (1.0, 'عادية 1×'),
                (1.25, 'سريعة 1.25×'),
                (1.5, 'سريعة 1.5×'),
              ],
              selected: controller.speed,
              onSelected: (v) => unawaited(controller.setSpeed(v)),
            ),
            const SizedBox(height: 12),
            Text(
              'التكرار',
              style: GoogleFonts.amiri(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: _green,
              ),
            ),
            const SizedBox(height: 8),
            _optionChips<int>(
              options: _repeatOptions,
              selected: controller.repeatCount,
              onSelected: controller.setRepeatCount,
            ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------
// Reciter picker sheet — v13.6
// ---------------------------------------------------------------------

/// The reciter pill's sheet: the 15 reciters, the current one
/// checked; a tap switches the reciter (persisted) and closes.
/// Downloads live in the reciters screen, not here — this is only
/// a picker.
Future<void> showReciterPickerSheet({
  required BuildContext context,
  required AudioPlayerController controller,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1F1E)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: ListenableBuilder(
        listenable: controller,
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
              'اختر القارئ',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < reciters.length; i++)
                    // Own Material: the sheet's DecoratedBox background
                    // would otherwise hide the tile's ink (FlutterError
                    // in tests).
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        title: Text(
                          reciters[i].name,
                          style: GoogleFonts.amiri(
                            fontSize: 17,
                            fontWeight: i == controller.reciterIndex
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: i == controller.reciterIndex
                            ? const Icon(Icons.check, color: _green)
                            : null,
                        onTap: () async {
                          await controller.setReciter(i);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
