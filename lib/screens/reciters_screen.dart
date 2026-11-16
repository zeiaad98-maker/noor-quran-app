import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quran/quran.dart' as quran;

import '../data/audio_downloads.dart';
import '../data/quran_audio.dart';

/// Reciters download screen (v12, per the sample-reciters.png and
/// sample-surah-download.png samples).
///
/// ONE list of the 15 reciters. Per reciter ONE تحميل button
/// downloads the FULL Mushaf in the background (resumable — it
/// continues where it stopped if the connection drops), and works
/// offline after. A second button (سورة محددة) downloads only the
/// surahs the user picks. After a download only مثبّت is shown —
/// no file management UI.
class RecitersScreen extends StatefulWidget {
  final AudioDownloadService service;
  final int currentReciterIndex;

  const RecitersScreen({
    super.key,
    required this.service,
    required this.currentReciterIndex,
  });

  @override
  State<RecitersScreen> createState() => _RecitersScreenState();
}

class _RecitersScreenState extends State<RecitersScreen> {
  static const _green = Color(0xFF0D6E52);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'تحميل التلاوات',
          style: GoogleFonts.amiri(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1F1E) : Colors.white,
        foregroundColor: _green,
      ),
      body: ListenableBuilder(
        listenable: widget.service,
        builder: (context, _) {
          final service = widget.service;
          final job = service.activeJob;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'حمّل تلاوة القارئ مرة واحدة، واستمع بعدها بدون إنترنت. التحميل يستأنف من حيث توقف إذا انقطع الاتصال.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.amiri(
                      fontSize: 14, color: Colors.grey),
                ),
              ),
              if (job != null && job.isDownloading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: job.progress,
                        backgroundColor: Colors.grey.shade300,
                        color: _green,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'جارٍ تحميل ${reciters[job.reciterIndex].name} — ${job.doneFiles} / ${job.totalFiles} (${(job.progress * 100).round()}٪)',
                        style: GoogleFonts.amiri(
                            fontSize: 13, color: _green),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: reciters.length,
                  itemBuilder: (context, i) {
                    final reciter = reciters[i];
                    final downloaded =
                        service.downloadedSurahsOf(i);
                    final full = downloaded.length >= 114;
                    final thisJob =
                        job != null && job.reciterIndex == i;
                    final busy = job != null && job.isDownloading;
                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              reciter.name,
                              style: GoogleFonts.amiri(
                                fontSize: 17,
                                fontWeight: i == widget.currentReciterIndex
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (i == widget.currentReciterIndex)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'الحالي',
                                style: GoogleFonts.amiri(
                                    fontSize: 12, color: _green),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        full
                            ? 'المصحف كامل مثبّت ✓'
                            : downloaded.isEmpty
                                ? 'غير مثبّت'
                                : '${downloaded.length} سورة مثبّتة',
                        style: GoogleFonts.amiri(
                            fontSize: 14,
                            color: full ? _green : Colors.grey),
                      ),
                      trailing: thisJob && job.isDownloading
                          ? Text(
                              '${(job.progress * 100).round()}٪',
                              style: GoogleFonts.amiri(
                                  fontSize: 15, color: _green),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilledButton(
                                  onPressed: busy || full
                                      ? null
                                      : () => _startFull(i),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _green,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                  ),
                                  child: Text(
                                    full ? 'مثبّت ✓' : 'تحميل',
                                    style:
                                        GoogleFonts.amiri(fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _pickSurahs(i),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _green,
                                    side:
                                        const BorderSide(color: _green),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                  ),
                                  child: Text(
                                    'سورة محددة',
                                    style:
                                        GoogleFonts.amiri(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startFull(int index) async {
    final ok =
        await widget.service.downloadFullMushaf(index);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يوجد تحميل جارٍ الآن — انتظر حتى ينتهي'),
        ),
      );
    }
  }

  Future<void> _pickSurahs(int index) async {
    final picked = await showDialog<List<int>>(
      context: context,
      builder: (context) => _SurahPickerDialog(
        reciterIndex: index,
        service: widget.service,
      ),
    );
    if (picked == null || picked.isEmpty) return;
    final ok = await widget.service.downloadSurahs(index, picked);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يوجد تحميل جارٍ الآن — انتظر حتى ينتهي'),
        ),
      );
    }
  }
}

/// Multi-select surah picker: tick one or more surahs, then تحميل.
/// Already-downloaded surahs show مثبّت and are untickable.
class _SurahPickerDialog extends StatefulWidget {
  final int reciterIndex;
  final AudioDownloadService service;

  const _SurahPickerDialog({
    required this.reciterIndex,
    required this.service,
  });

  @override
  State<_SurahPickerDialog> createState() => _SurahPickerDialogState();
}

class _SurahPickerDialogState extends State<_SurahPickerDialog> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final downloaded =
        widget.service.downloadedSurahsOf(widget.reciterIndex);
    return AlertDialog(
      title: Text(
        'اختر السور — ${reciters[widget.reciterIndex].name}',
        style: GoogleFonts.amiri(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: ListView.builder(
          itemCount: 114,
          itemBuilder: (context, i) {
            final surah = i + 1;
            final done = downloaded.contains(surah);
            return CheckboxListTile(
              value: done ? true : _selected.contains(surah),
              onChanged: done
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _selected.add(surah);
                        } else {
                          _selected.remove(surah);
                        }
                      }),
              title: Text(
                '${quran.getSurahNameArabic(surah)} ($surah)',
                style: GoogleFonts.amiri(fontSize: 16),
              ),
              subtitle: done
                  ? Text(
                      'مثبّت ✓',
                      style: GoogleFonts.amiri(
                          fontSize: 13, color: const Color(0xFF0D6E52)),
                    )
                  : Text(
                      '${quran.getVerseCount(surah)} آية',
                      style: GoogleFonts.amiri(
                          fontSize: 13, color: Colors.grey),
                    ),
              controlAffinity: ListTileControlAffinity.leading,
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('إلغاء', style: GoogleFonts.amiri(fontSize: 15)),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0D6E52),
          ),
          child: Text(
            'تحميل المحدد (${_selected.length})',
            style: GoogleFonts.amiri(fontSize: 15),
          ),
        ),
      ],
    );
  }
}
