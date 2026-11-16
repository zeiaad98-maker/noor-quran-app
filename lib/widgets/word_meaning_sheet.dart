import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quran/quran.dart' as quran;

import '../data/word_meanings.dart';

/// Bottom sheet showing a tapped word with three tabs:
/// المعنى (غريب القرآن), الإعراب (simplified morphology), الآية (التفسير الميسر).
class WordMeaningSheet extends StatefulWidget {
  final int surahNumber;
  final int verseNumber;
  final String word;
  final VoidCallback? onPlayWord;

  const WordMeaningSheet({
    super.key,
    required this.surahNumber,
    required this.verseNumber,
    required this.word,
    this.onPlayWord,
  });

  @override
  State<WordMeaningSheet> createState() => _WordMeaningSheetState();
}

class _WordMeaningSheetState extends State<WordMeaningSheet> {
  String? _meaning;
  String? _morph;
  String? _tafsir;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      QuranWordData.meaningForWord(
          widget.surahNumber, widget.verseNumber, widget.word),
      QuranWordData.morphForWord(
          widget.surahNumber, widget.verseNumber, widget.word),
      QuranWordData.tafsirForAyah(widget.surahNumber, widget.verseNumber),
    ]);
    if (!mounted) return;
    setState(() {
      _meaning = results[0];
      _morph = results[1];
      _tafsir = results[2];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF2D2A26);
    return DefaultTabController(
      length: 3,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1F1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
            const SizedBox(height: 12),
            Text(
              widget.word,
              style: GoogleFonts.amiri(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D6E52),
              ),
            ),
            Text(
              'سورة ${quran.getSurahNameArabic(widget.surahNumber)} • الآية ${widget.verseNumber}',
              style: GoogleFonts.amiri(fontSize: 14, color: Colors.grey),
            ),
            if (widget.onPlayWord != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onPlayWord!.call();
                },
                icon: const Icon(Icons.volume_up, size: 20),
                label: Text(
                  'استمع إلى الكلمة',
                  style: GoogleFonts.amiri(fontSize: 16),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D6E52),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TabBar(
              labelColor: const Color(0xFF0D6E52),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF0D6E52),
              tabs: [
                Tab(child: Text('المعنى', style: GoogleFonts.amiri(fontSize: 16))),
                Tab(child: Text('الإعراب', style: GoogleFonts.amiri(fontSize: 16))),
                Tab(child: Text('الآية', style: GoogleFonts.amiri(fontSize: 16))),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _MeaningTab(
                          meaning: _meaning,
                          tafsir: _tafsir,
                          textColor: textColor,
                        ),
                        _MorphTab(morph: _morph, textColor: textColor),
                        _TafsirTab(tafsir: _tafsir, textColor: textColor),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeaningTab extends StatelessWidget {
  final String? meaning;
  final String? tafsir;
  final Color textColor;

  const _MeaningTab({this.meaning, this.tafsir, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (meaning != null) ...[
            Text(
              meaning!,
              style: GoogleFonts.amiri(fontSize: 19, color: textColor),
            ),
            const SizedBox(height: 8),
            Text(
              'من كتاب «السراج في بيان غريب القرآن»',
              style: GoogleFonts.amiri(fontSize: 13, color: Colors.grey),
            ),
          ] else ...[
            Text(
              'لا يوجد معنى خاص لهذه الكلمة في غريب القرآن.',
              style: GoogleFonts.amiri(fontSize: 18, color: textColor),
            ),
            const SizedBox(height: 12),
            Text(
              'تفسير الآية:',
              style: GoogleFonts.amiri(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D6E52),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tafsir ?? 'تفسير هذه الآية غير متوفر حالياً.',
              style: GoogleFonts.amiri(fontSize: 17, color: textColor),
            ),
          ],
        ],
      ),
    );
  }
}

class _MorphTab extends StatelessWidget {
  final String? morph;
  final Color textColor;

  const _MorphTab({this.morph, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (morph != null)
            Text(
              morph!,
              style: GoogleFonts.amiri(fontSize: 19, color: textColor),
            )
          else
            Text(
              'لا يوجد إعراب مبسّط لهذه الكلمة.',
              style: GoogleFonts.amiri(fontSize: 18, color: textColor),
            ),
          const SizedBox(height: 12),
          Text(
            'الإعراب هنا مبسّط من بيانات الصرف (الجذر ونوع الكلمة وحركتها)، وليس إعراباً تفصيلياً كاملاً.',
            style: GoogleFonts.amiri(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _TafsirTab extends StatelessWidget {
  final String? tafsir;
  final Color textColor;

  const _TafsirTab({this.tafsir, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'التفسير الميسر:',
            style: GoogleFonts.amiri(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0D6E52),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tafsir ?? 'تفسير هذه الآية غير متوفر حالياً.',
            style: GoogleFonts.amiri(fontSize: 17, color: textColor),
          ),
        ],
      ),
    );
  }
}
