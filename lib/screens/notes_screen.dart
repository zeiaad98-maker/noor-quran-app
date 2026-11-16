import 'package:material_ui/material_ui.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran/quran.dart' as quran;

import '../data/ayah_notes.dart';
import 'surah_reader_screen.dart';

/// Lists all per-ayah notes; tapping one jumps to its page in the reader.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<AyahNote> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final notes = await AyahNotes.getAllNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  void _openNote(AyahNote note) {
    final page = quran.getPageNumber(note.surah, note.verse);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SurahReaderScreen(
          surahNumber: note.surah,
          initialPage: page,
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _deleteNote(AyahNote note) async {
    await AyahNotes.deleteNote(note.surah, note.verse);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ملاحظاتي', style: GoogleFonts.amiri(fontSize: 20)),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FaIcon(
                          FontAwesomeIcons.bookQuran,
                          size: 48,
                          color: Color(0xFF0D6E52),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد ملاحظات بعد.\nاضغط على أي آية في المصحف ثم «إضافة ملاحظة» لحفظ فائدة عليها.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.amiri(
                              fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _notes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return ListTile(
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
                      onTap: () => _openNote(note),
                    );
                  },
                ),
    );
  }
}
