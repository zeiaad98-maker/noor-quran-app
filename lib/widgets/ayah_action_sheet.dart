import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran/quran.dart' as quran;

import '../data/ayah_notes.dart';
import '../data/qcf_word_map.dart';
import '../data/word_meanings.dart';
import 'word_meaning_sheet.dart';

/// Bottom sheet for a tapped ayah: verse text, word buttons (tap a word
/// for its meaning), play-audio controls (via the audio player sheet),
/// and a per-ayah note editor.
class AyahActionSheet extends StatefulWidget {
  final int surahNumber;
  final int verseNumber;
  final int pageNumber;
  final VoidCallback onPlayAyah;
  final void Function(int wordIndex) onPlayWord;
  final VoidCallback onOpenNotesScreen;
  final VoidCallback onNoteChanged;

  const AyahActionSheet({
    super.key,
    required this.surahNumber,
    required this.verseNumber,
    required this.pageNumber,
    required this.onPlayAyah,
    required this.onPlayWord,
    required this.onOpenNotesScreen,
    required this.onNoteChanged,
  });

  @override
  State<AyahActionSheet> createState() => _AyahActionSheetState();
}

class _AyahActionSheetState extends State<AyahActionSheet> {
  String? _note;
  String? _quarterLabel;
  /// TRUE Uthmani words of this ayah, from the QCF word map (v12 fix).
  /// The old source (QuranWordData.wordsForAyah, morphology entries)
  /// merges بَعۡدَ مَا in 2:181, 8:6, 13:37 and إِلۡ يَاسِينَ in
  /// 37:130 into ONE entry, so the chips after the merge were shifted
  /// by one and played the wrong word. The word map gives the real
  /// words, so chip i plays word i + 1 — exactly like the word card.
  /// Synchronous (pure function on bundled data), so the chips are
  /// built immediately, no loading spinner.
  late final List<String> _words;

  @override
  void initState() {
    super.initState();
    _loadNote();
    _words = buildQcfWordMap(widget.surahNumber, widget.verseNumber)
        .words
        .map((w) => w.text)
        .toList(growable: false);
    QuranWordData.hizbQuarterLabel(widget.surahNumber, widget.verseNumber)
        .then((label) {
      if (mounted) setState(() => _quarterLabel = label);
    });
  }

  Future<void> _loadNote() async {
    final note =
        await AyahNotes.getNote(widget.surahNumber, widget.verseNumber);
    if (mounted) setState(() => _note = note);
  }

  void _openWord(String word, int wordIndex) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WordMeaningSheet(
        surahNumber: widget.surahNumber,
        verseNumber: widget.verseNumber,
        word: word,
        onPlayWord: () {
          Navigator.of(context).pop();
          widget.onPlayWord(wordIndex);
        },
      ),
    );
  }

  Future<void> _editNote() async {
    final controller =
        TextEditingController(text: _note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'ملاحظة على الآية ${widget.verseNumber} من سورة ${quran.getSurahNameArabic(widget.surahNumber)}',
          style: GoogleFonts.amiri(fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'اكتب ملاحظتك أو فائدة من الآية...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (_note != null)
            TextButton(
              onPressed: () async {
                await AyahNotes.deleteNote(
                    widget.surahNumber, widget.verseNumber);
                unawaited(Fluttertoast.showToast(
                  msg: 'تم حذف الملاحظة',
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: const Color(0xFF0D6E52),
                  textColor: Colors.white,
                ));
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: const Text('حذف الملاحظة',
                  style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) {
                await AyahNotes.deleteNote(
                    widget.surahNumber, widget.verseNumber);
              } else {
                await AyahNotes.saveNote(
                    widget.surahNumber, widget.verseNumber, text);
                unawaited(Fluttertoast.showToast(
                  msg: 'تم حفظ الملاحظة',
                  toastLength: Toast.LENGTH_SHORT,
                  gravity: ToastGravity.BOTTOM,
                  backgroundColor: const Color(0xFF0D6E52),
                  textColor: Colors.white,
                ));
              }
              if (context.mounted) Navigator.of(context).pop(true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _loadNote();
      widget.onNoteChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF2D2A26);
    final surahName = quran.getSurahNameArabic(widget.surahNumber);
    final verseCount = quran.getVerseCount(widget.surahNumber);
    final juzNumber =
        quran.getJuzNumber(widget.surahNumber, widget.verseNumber);
    final verseText =
        quran.getVerse(widget.surahNumber, widget.verseNumber);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1F1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SingleChildScrollView(
        child: Column(
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
              'سورة $surahName • الآية ${widget.verseNumber} من $verseCount',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D6E52),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'الجزء $juzNumber • ${_quarterLabel ?? '...'} • صفحة ${widget.pageNumber}',
              textAlign: TextAlign.center,
              style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF2A2D2A) : const Color(0xFFFAF6EE)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                verseText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Hafs',
                  fontSize: 22,
                  height: 1.9,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على أي كلمة لعرض معناها:',
              style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _words.length; i++)
                  OutlinedButton(
                    onPressed: () => _openWord(_words[i], i + 1),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _words[i],
                      style: GoogleFonts.amiri(fontSize: 17),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onPlayAyah();
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(
                'تشغيل الآية',
                style: GoogleFonts.amiri(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D6E52),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _editNote,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: Text(
                      _note == null ? 'إضافة ملاحظة' : 'تعديل الملاحظة',
                      style: GoogleFonts.amiri(fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenNotesScreen();
                    },
                    icon: const FaIcon(FontAwesomeIcons.noteSticky, size: 18),
                    label: Text(
                      'ملاحظاتي',
                      style: GoogleFonts.amiri(fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
            if (_note != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3C4).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _note!,
                  style: GoogleFonts.amiri(
                    fontSize: 16,
                    color: const Color(0xFF2D2A26),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
