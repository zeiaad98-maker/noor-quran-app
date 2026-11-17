import 'package:material_ui/material_ui.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran/quran.dart' as quran;

import '../data/ayah_marks.dart';
import '../data/ayah_notes.dart';
import 'surah_reader_screen.dart';

/// Lists all per-ayah notes; tapping one jumps to its page in the reader.
///
/// v13.3 (FIX B): a second section, الفواصل, lists the ayahs the
/// user bookmarked from the word popup (فاصل) — same jump-to-page
/// behaviour, so a bookmark is a real return point, not a dead mark.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<AyahNote> _notes = [];
  List<(int, int)> _bookmarks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      AyahNotes.getAllNotes(),
      AyahBookmarks.ids(),
    ]);
    if (!mounted) return;
    final ids = (results[1] as Set<String>)
        .map((id) {
          final parts = id.split(':');
          if (parts.length != 2) return null;
          final s = int.tryParse(parts[0]);
          final v = int.tryParse(parts[1]);
          if (s == null || v == null) return null;
          return (s, v);
        })
        .whereType<(int, int)>()
        .toList()
      ..sort((a, b) {
        final bySurah = a.$1.compareTo(b.$1);
        return bySurah != 0 ? bySurah : a.$2.compareTo(b.$2);
      });
    setState(() {
      _notes = results[0] as List<AyahNote>;
      _bookmarks = ids;
      _loading = false;
    });
  }

  void _openAyah(int surah, int verse) {
    final page = quran.getPageNumber(surah, verse);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurahReaderScreen(
          surahNumber: surah,
          initialPage: page,
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _deleteNote(AyahNote note) async {
    await AyahNotes.deleteNote(note.surah, note.verse);
    await _load();
  }

  Future<void> _deleteBookmark((int, int) bookmark) async {
    await AyahBookmarks.remove(bookmark.$1, bookmark.$2);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0D6E52);
    return Scaffold(
      appBar: AppBar(
        title: Text('ملاحظاتي', style: GoogleFonts.amiri(fontSize: 20)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty && _bookmarks.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.bookQuran,
                          size: 48,
                          color: green,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد ملاحظات ولا فواصل بعد.\nاضغط على أي آية في المصحف ثم «إضافة ملاحظة» لحفظ فائدة عليها، أو «فاصل» من نافذة الكلمة لحفظ الآية.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.amiri(
                              fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  children: [
                    if (_notes.isNotEmpty) ...[
                      _sectionHeader('ملاحظاتي'),
                      for (final note in _notes)
                        ListTile(
                          title: Text(
                            'سورة ${quran.getSurahNameArabic(note.surah)} • الآية ${note.verse}',
                            style: GoogleFonts.amiri(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            note.text,
                            style: GoogleFonts.amiri(fontSize: 16),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _deleteNote(note),
                          ),
                          onTap: () => _openAyah(note.surah, note.verse),
                        ),
                    ],
                    if (_bookmarks.isNotEmpty) ...[
                      _sectionHeader('الفواصل'),
                      for (final bookmark in _bookmarks)
                        ListTile(
                          leading: const Icon(Icons.bookmark, color: green),
                          title: Text(
                            'سورة ${quran.getSurahNameArabic(bookmark.$1)} • الآية ${bookmark.$2}',
                            style: GoogleFonts.amiri(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _deleteBookmark(bookmark),
                          ),
                          onTap: () =>
                              _openAyah(bookmark.$1, bookmark.$2),
                        ),
                    ],
                  ],
                ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      alignment: Alignment.centerRight,
      child: Text(
        title,
        style: GoogleFonts.amiri(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF0D6E52),
        ),
      ),
    );
  }
}
