import 'package:archive/archive.dart';

/// Builds a real ZIP in memory for the v13.5 surah-ZIP tests:
/// [entries] maps a ZIP entry name (e.g. '112001.mp3') to its bytes.
/// Built with the `archive` package's encoder — the same format the
/// app's streaming reader in audio_downloads.dart must parse.
///
/// [stored]: when true the entries are STORED (method 0, no
/// compression) — exactly what everyayah ships (verified live
/// 2026-11-17 on the real Tunaiji 001.zip: all 7 MP3s Stored, 0%).
/// When false (default) the entries are DEFLATED (method 8), so the
/// tests prove the inflate path too.
List<int> buildSurahZip(
  Map<String, List<int>> entries, {
  bool stored = false,
}) {
  final archive = Archive();
  for (final e in entries.entries) {
    final file = ArchiveFile(e.key, e.value.length, e.value);
    if (stored) file.compression = CompressionType.none;
    archive.addFile(file);
  }
  return ZipEncoder().encode(archive);
}
