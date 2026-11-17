import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_audio.dart';

/// Per-reciter audio downloads (v12): the full Mushaf or selected
/// surahs, downloaded in the background and played offline after.
///
/// * Source: the SAME per-ayah files the player already streams
///   (`everyayahUrl` — everyayah.com, verified URLs from the
///   reciters list). No new source, no new reciters.
/// * Resume: downloads are per-FILE. A manifest
///   (`<docs>/audio/<folder>/manifest.json`) records completed files;
///   a failed or interrupted job resumes from the next missing file —
///   nothing already downloaded is fetched again. This is what makes
///   a 6,236-file download survivable on a weak connection.
/// * Playback: the player checks [localAyahFile] first and plays the
///   local file when present, streams otherwise. One download runs at
///   a time (sequential files — kinder to weak internet, and the
///   progress count is exact).
/// * No file management UI: the screen shows only مثبّت / تحميل /
///   progress. Files live under `<docs>/audio/<everyayah folder>/`.
class AudioDownloadService extends ChangeNotifier {
  final http.Client _client;
  final Directory? _storageDirOverride;
  final SharedPreferences? _prefsOverride;

  Directory? _baseDir;

  /// Downloaded surahs per reciter index (persisted in prefs).
  final Map<int, Set<int>> _downloadedSurahs = {};

  /// The current or most recent job (null only before any download).
  /// Kept after it finishes so the UI can show done/failed/cancelled
  /// instead of losing the result.
  DownloadJob? _job;

  AudioDownloadService({
    http.Client? client,
    Directory? storageDir,
    SharedPreferences? prefs,
  })  : _client = client ?? http.Client(),
        _storageDirOverride = storageDir,
        _prefsOverride = prefs;

  DownloadJob? get activeJob => _job;

  Future<void> init() async {
    _baseDir = _storageDirOverride ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/audio');
    if (!await _baseDir!.exists()) {
      await _baseDir!.create(recursive: true);
    }
    final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
    for (var i = 0; i < reciters.length; i++) {
      final saved = prefs.getStringList(_surahsKey(i)) ?? const [];
      _downloadedSurahs[i] =
          saved.map((s) => int.tryParse(s) ?? 0).where((s) => s > 0).toSet();
    }
    notifyListeners();
  }

  static String _surahsKey(int reciterIndex) => 'audio_dl_surahs_$reciterIndex';

  /// Surahs of [reciterIndex] that are fully downloaded.
  Set<int> downloadedSurahsOf(int reciterIndex) =>
      Set<int>.unmodifiable(_downloadedSurahs[reciterIndex] ?? const {});

  bool isSurahDownloaded(int reciterIndex, int surah) =>
      _downloadedSurahs[reciterIndex]?.contains(surah) ?? false;

  bool get isDownloading => _job != null && _job!.isDownloading;

  /// Local file for one ayah, when it was downloaded (sync — the
  /// player calls this on every play). Null when not downloaded or
  /// before [init] finished.
  File? localAyahFile(Reciter reciter, int surah, int ayah) {
    final dir = _baseDir;
    if (dir == null) return null;
    final file = File(
        '${dir.path}/${reciter.everyayah}/${ayahFileName(surah, ayah)}.mp3');
    return file.existsSync() ? file : null;
  }

  /// Local wbw word file, when it was cached (sync). Null when not
  /// cached or before [init] finished.
  File? localWbwFile(int surah, int ayah, int word) {
    final dir = _baseDir;
    if (dir == null) return null;
    final file = File(
        '${dir.path}/wbw/${ayahFileName(surah, ayah)}_${word.toString().padLeft(3, '0')}.mp3');
    return file.existsSync() ? file : null;
  }

  /// Cache-on-play (v13): one ayah file, downloaded on demand the
  /// first time it is played and reused from disk after that. This
  /// is what makes pronunciation clear and complete on a weak
  /// connection: the player plays a LOCAL file (no mid-play stutter,
  /// no buffering stall, no start-late), and a repeat tap is instant
  /// and works offline. Files live in the SAME layout as the
  /// surah downloads above, so a cached ayah also counts as
  /// downloaded for the downloads screen — and vice versa.
  /// Returns the file, or null when the download fails (the player
  /// then falls back to streaming). Never throws.
  Future<File?> cacheAyahFile(Reciter reciter, int surah, int ayah) async {
    final existing = localAyahFile(reciter, surah, ayah);
    if (existing != null) return existing;
    final dir = _baseDir;
    if (dir == null) return null;
    final ok = await _fetchToFile(
      everyayahUrl(reciter, surah, ayah),
      File('${dir.path}/${reciter.everyayah}/${ayahFileName(surah, ayah)}.mp3'),
    );
    if (!ok) return null;
    return localAyahFile(reciter, surah, ayah);
  }

  /// Cache-on-play (v13) for one wbw word file (the small per-word
  /// recording, ~40–140 KB). Same guarantees as [cacheAyahFile]:
  /// downloaded once, played from disk after that. Returns the file,
  /// or null when the download fails (the player falls back to
  /// streaming). Never throws.
  Future<File?> cacheWbwFile(int surah, int ayah, int word) async {
    final existing = localWbwFile(surah, ayah, word);
    if (existing != null) return existing;
    final dir = _baseDir;
    if (dir == null) return null;
    final ok = await _fetchToFile(
      wbwWordUrl(surah, ayah, word),
      File(
          '${dir.path}/wbw/${ayahFileName(surah, ayah)}_${word.toString().padLeft(3, '0')}.mp3'),
    );
    if (!ok) return null;
    return localWbwFile(surah, ayah, word);
  }

  /// One file: GET (30 s timeout), verify it is an mp3 (non-empty),
  /// write it to disk ATOMICALLY (temp file + rename) so a partial
  /// download is never mistaken for a complete cached file. A failed
  /// or partial download leaves nothing behind. Returns false on any
  /// failure. Never throws.
  Future<bool> _fetchToFile(String url, File file) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return false;
      }
      final dir = file.parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(response.bodyBytes);
      await tmp.rename(file.path);
      return true;
    } catch (_) {
      try {
        final tmp = File('${file.path}.tmp');
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return false;
    }
  }

  /// Start downloading [surahs] of the reciter (1–114). Ignored when
  /// another download is already running. Surahs already downloaded
  /// are skipped. Returns false when a job is already running.
  Future<bool> downloadSurahs(int reciterIndex, List<int> surahs) async {
    if (_job != null && _job!.isDownloading) return false;
    final reciter = reciters[reciterIndex];
    final pending = surahs
        .where((s) => !isSurahDownloaded(reciterIndex, s))
        .toList(growable: false);
    if (pending.isEmpty) return true;
    _job = DownloadJob(
      reciterIndex: reciterIndex,
      surahs: pending,
      totalFiles:
          pending.fold<int>(0, (sum, s) => sum + quran.getVerseCount(s)),
    );
    notifyListeners();
    unawaited(_runJob(reciterIndex, reciter));
    return true;
  }

  /// Download the FULL Mushaf of the reciter (all 114 surahs).
  Future<bool> downloadFullMushaf(int reciterIndex) =>
      downloadSurahs(reciterIndex, List<int>.generate(114, (i) => i + 1));

  Future<void> _runJob(int reciterIndex, Reciter reciter) async {
    final job = _job!;
    final manifest = await _loadManifest(reciter);
    try {
      for (final surah in job.surahs) {
        for (var ayah = 1; ayah <= quran.getVerseCount(surah); ayah++) {
          if (job.cancelled) {
            job.status = DownloadStatus.cancelled;
            notifyListeners();
            return;
          }
          final name = ayahFileName(surah, ayah);
          if (manifest.contains(name)) {
            job.doneFiles++;
            continue;
          }
          final ok = await _downloadOne(reciter, surah, ayah);
          if (!ok) {
            job.status = DownloadStatus.failed;
            job.error =
                'تعذّر تحميل الآية $surah:$ayah — تحقق من الإنترنت وحاول مجدداً';
            notifyListeners();
            return;
          }
          manifest.add(name);
          job.doneFiles++;
          await _saveManifest(reciter, manifest);
          notifyListeners();
        }
        // Whole surah done — persist it (survives even a crash).
        _downloadedSurahs.putIfAbsent(reciterIndex, () => <int>{}).add(surah);
        final prefs = _prefsOverride ?? await SharedPreferences.getInstance();
        await prefs.setStringList(
          _surahsKey(reciterIndex),
          _downloadedSurahs[reciterIndex]!.map((s) => '$s').toList(),
        );
        notifyListeners();
      }
      job.status = DownloadStatus.done;
    } catch (e) {
      job.status = DownloadStatus.failed;
      job.error = e.toString();
    }
    notifyListeners();
  }

  /// One file of a surah job: same atomic cached download as
  /// [cacheAyahFile] (the manifest records it only after success).
  Future<bool> _downloadOne(Reciter reciter, int surah, int ayah) async {
    final dir = Directory('${_baseDir!.path}/${reciter.everyayah}');
    final name = ayahFileName(surah, ayah);
    return _fetchToFile(
      everyayahUrl(reciter, surah, ayah),
      File('${dir.path}/$name.mp3'),
    );
  }

  Future<Set<String>> _loadManifest(Reciter reciter) async {
    try {
      final file = File('${_baseDir!.path}/${reciter.everyayah}/manifest.json');
      if (!await file.exists()) return <String>{};
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      return raw.map((e) => e as String).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveManifest(Reciter reciter, Set<String> manifest) async {
    final file = File('${_baseDir!.path}/${reciter.everyayah}/manifest.json');
    await file.writeAsString(jsonEncode(manifest.toList()));
  }

  /// Cancel the running job (keeps what was already downloaded).
  void cancel() {
    _job?.cancelled = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

enum DownloadStatus { downloading, done, failed, cancelled }

/// One download job: a reciter + the surahs being fetched.
/// [doneFiles]/[totalFiles] drive the progress display
/// ("٣٤٥ / ٦٢٣٦" and a percentage).
class DownloadJob {
  final int reciterIndex;
  final List<int> surahs;
  final int totalFiles;
  int doneFiles = 0;
  DownloadStatus status = DownloadStatus.downloading;
  String? error;
  bool cancelled = false;

  DownloadJob({
    required this.reciterIndex,
    required this.surahs,
    required this.totalFiles,
  });

  bool get isDownloading => status == DownloadStatus.downloading;

  double get progress => totalFiles == 0 ? 0 : doneFiles / totalFiles;
}
