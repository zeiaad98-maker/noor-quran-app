import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'quran_audio.dart';

/// Download progress (v13.3): bytes received so far + the total when
/// the server reports a length (null when it streams without one).
typedef DownloadProgressCallback = void Function(int received, int? total);

/// Cancel check (v13.3): the player passes `() => token !=
/// _playToken`, so a stop / newer play aborts an in-flight download
/// instead of leaving a ghost load behind.
typedef DownloadCancelCheck = bool Function();

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
  File? localWbwFile(int surah, int ayah, int fileNumber) {
    final dir = _baseDir;
    if (dir == null) return null;
    final file = File(
        '${dir.path}/wbw/${ayahFileName(surah, ayah)}_${fileNumber.toString().padLeft(3, '0')}.mp3');
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
  /// then falls back to streaming). Never throws. [onProgress] /
  /// [isCancelled] are forwarded to the streamed download (v13.3).
  Future<File?> cacheAyahFile(
    Reciter reciter,
    int surah,
    int ayah, {
    DownloadProgressCallback? onProgress,
    DownloadCancelCheck? isCancelled,
  }) async {
    final existing = localAyahFile(reciter, surah, ayah);
    if (existing != null) return existing;
    final dir = _baseDir;
    if (dir == null) return null;
    final ok = await _fetchToFile(
      everyayahUrl(reciter, surah, ayah),
      File('${dir.path}/${reciter.everyayah}/${ayahFileName(surah, ayah)}.mp3'),
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (!ok) return null;
    return localAyahFile(reciter, surah, ayah);
  }

  /// Cache-on-play (v13) for one wbw word file (the small per-word
  /// recording, ~25–140 KB). Same guarantees as [cacheAyahFile]:
  /// downloaded once, played from disk after that. [fileNumber] is
  /// the word's 1-based position among the ayah's audio words
  /// (v13.4 — the wbw file number IS the word position) — it is
  /// also the cache key, so one cached file serves one wbw
  /// recording. The cache is self-consistent across the v13.4
  /// change: keys are file numbers, and a file's content matches
  /// its number, so a file cached under the old (shifted) number
  /// is still the right recording for the word that now asks for
  /// that number. No purge needed.
  /// Tries the current CDN first, then the legacy host (v13.2).
  /// Each host is fetched by [_fetchToFile] (streamed, stall timeout
  /// only, resume + retry — v13.3): a slow connection still gets
  /// the file, it just takes longer; there is no "too slow" any
  /// more. Returns the file, or null when both downloads fail (the
  /// player then reports the error). Never throws.
  Future<File?> cacheWbwFile(
    int surah,
    int ayah,
    int fileNumber, {
    DownloadProgressCallback? onProgress,
    DownloadCancelCheck? isCancelled,
  }) async {
    final existing = localWbwFile(surah, ayah, fileNumber);
    if (existing != null) return existing;
    final dir = _baseDir;
    if (dir == null) return null;
    final file = File('${dir.path}/wbw/${ayahFileName(surah, ayah)}_'
        '${fileNumber.toString().padLeft(3, '0')}.mp3');
    if (await _fetchToFile(wbwWordUrl(surah, ayah, fileNumber), file,
        onProgress: onProgress, isCancelled: isCancelled)) {
      return localWbwFile(surah, ayah, fileNumber);
    }
    if (await _fetchToFile(
        wbwWordUrlLegacy(surah, ayah, fileNumber), file,
        onProgress: onProgress, isCancelled: isCancelled)) {
      return localWbwFile(surah, ayah, fileNumber);
    }
    return null;
  }

  /// Download progress: bytes received so far + the total when the
  /// server reports a length (null when it streams without one).
  /// Stall timeout (v13.3): a download fails ONLY when no bytes
  /// arrive for this long. There is NO wall-clock timeout on a
  /// download: a 60 KB word file at 1 KB/s takes 60 s and still
  /// succeeds — the user's rule is that words must download at ANY
  /// speed, even the slowest. A stalled connection (silence) fails
  /// instead of spinning forever, and the user can cancel any time.
  /// Mutable so tests can shorten it; production always uses 30 s.
  static Duration stallTimeout = const Duration(seconds: 30);

  /// Attempts per URL (first + retries) and the pause between them.
  /// Mutable so tests can shorten the backoff.
  static int fetchAttempts = 2;
  static Duration retryBackoff = const Duration(seconds: 2);

  /// One file, streamed (v13.3 — the old whole-body GET with a
  /// wall-clock timeout killed slow downloads mid-flight and kept
  /// the entire file in memory). Retries [fetchAttempts] times with
  /// [retryBackoff] between them — but only for TRANSIENT failures
  /// (5xx, stall, early close, network error). A 4xx is definitive:
  /// the server answered that this file is not here, so retrying
  /// the same request cannot help — and for the wbw fallback it
  /// would delay the legacy host for nothing. A cancel also returns
  /// at once, with no backoff wait. Returns false on any failure.
  /// Never throws.
  Future<bool> _fetchToFile(
    String url,
    File file, {
    DownloadProgressCallback? onProgress,
    DownloadCancelCheck? isCancelled,
  }) async {
    for (var attempt = 1; attempt <= fetchAttempts; attempt++) {
      if (isCancelled?.call() ?? false) return false;
      final outcome = await _fetchOnce(url, file,
          onProgress: onProgress, isCancelled: isCancelled);
      if (outcome == _FetchOutcome.ok) return true;
      if (outcome == _FetchOutcome.fatal) return false;
      if (isCancelled?.call() ?? false) return false;
      if (attempt < fetchAttempts) {
        await Future.delayed(retryBackoff);
      }
    }
    return false;
  }

  /// One streamed attempt: GET with Range resume when a partial tmp
  /// file from the SAME url exists, stream the body to disk chunk by
  /// chunk (never the whole body in memory), fail only on a stall
  /// (no bytes for [stallTimeout]) or a cancel. Writes to a tmp file
  /// and renames atomically, so a partial download is never mistaken
  /// for a complete cached file. A failed attempt's tmp is KEPT for
  /// the next attempt to resume; a cancelled attempt's tmp is kept
  /// too (the target file is untouched). The directory is created
  /// only after the server answers OK, so a failed download leaves
  /// no trace — not even an empty folder. Never throws.
  Future<_FetchOutcome> _fetchOnce(
    String url,
    File file, {
    DownloadProgressCallback? onProgress,
    DownloadCancelCheck? isCancelled,
  }) async {
    final tmp = File('${file.path}.${_urlTag(url)}.tmp');
    http.StreamedResponse? response;
    IOSink? sink;
    StreamSubscription<List<int>>? sub;
    Timer? stallTimer;
    try {
      final existing = await tmp.exists() ? await tmp.length() : 0;
      final request = http.Request('GET', Uri.parse(url));
      if (existing > 0) request.headers['Range'] = 'bytes=$existing-';
      // Headers must arrive within one stall window; the body then
      // has its own per-chunk stall timer below.
      response = await _client.send(request).timeout(stallTimeout);
      if (response.statusCode == 416) {
        // Our resume offset is past the end (the server file
        // changed): drop the partial file; the retry starts fresh.
        try {
          await tmp.delete();
        } catch (_) {}
        return _FetchOutcome.retryable;
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        // 4xx: the server answered definitively — retrying the same
        // request cannot help. 5xx and anything else is transient.
        final code = response.statusCode;
        return code >= 400 && code < 500
            ? _FetchOutcome.fatal
            : _FetchOutcome.retryable;
      }
      var resumedFrom = 0;
      int? total;
      if (response.statusCode == 206) {
        resumedFrom = existing;
        final remaining = response.contentLength;
        total = remaining != null && remaining >= 0
            ? resumedFrom + remaining
            : null;
      } else {
        // 200: the server ignored Range — restart from scratch.
        if (existing > 0) {
          try {
            await tmp.delete();
          } catch (_) {}
        }
        final len = response.contentLength;
        total = len != null && len >= 0 ? len : null;
      }
      // Create the directory only now that the server answered OK:
      // a failed download leaves no trace — not even an empty folder.
      final dir = file.parent;
      if (!await dir.exists()) await dir.create(recursive: true);
      sink = tmp.openWrite(
          mode: resumedFrom > 0 ? FileMode.append : FileMode.write);
      final done = Completer<bool>();
      var received = resumedFrom;
      var failed = false;
      void finish(bool ok) {
        if (!done.isCompleted) done.complete(ok);
      }

      void armStall() {
        stallTimer?.cancel();
        stallTimer = Timer(stallTimeout, () async {
          failed = true;
          await sub?.cancel();
          finish(false);
        });
      }

      onProgress?.call(received, total);
      armStall();
      sub = response.stream.listen(
        (chunk) {
          if (isCancelled?.call() ?? false) {
            failed = true;
            unawaited(sub?.cancel());
            finish(false);
            return;
          }
          stallTimer?.cancel();
          sink!.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
          armStall();
        },
        onError: (_) {
          failed = true;
          finish(false);
        },
        onDone: () => finish(!failed),
        cancelOnError: true,
      );
      final ok = await done.future;
      stallTimer?.cancel();
      try {
        await sub.cancel();
      } catch (_) {}
      await sink.flush();
      await sink.close();
      sink = null;
      if (!ok) return _FetchOutcome.retryable;
      final size = await tmp.length();
      if (size == 0) return _FetchOutcome.retryable;
      // The stream ended early: keep the tmp for resume next time.
      if (total != null && size != total) return _FetchOutcome.retryable;
      await tmp.rename(file.path);
      return _FetchOutcome.ok;
    } catch (_) {
      return _FetchOutcome.retryable;
    } finally {
      stallTimer?.cancel();
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await sink?.close();
      } catch (_) {}
    }
  }

  /// Short deterministic tag for a URL (FNV-1a over the code units):
  /// the CDN and the legacy host serve the same file under the same
  /// cache path, but their partial downloads must never be appended
  /// to each other — each URL resumes only its own tmp file.
  static String _urlTag(String url) {
    var hash = 0x811c9dc5;
    for (final c in url.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
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

/// What one streamed attempt reports back (v13.3, FIX A):
/// * [ok] — the file downloaded completely.
/// * [retryable] — a transient failure (5xx, stall, early close,
///   network error): worth one more attempt after [AudioDownloadService.retryBackoff].
/// * [fatal] — a definitive failure (4xx): the server answered, so
///   retrying the same request cannot help.
enum _FetchOutcome { ok, retryable, fatal }

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
