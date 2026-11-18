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
/// * Source (v13.5): one per-surah ZIP per reciter
///   ([everyayahSurahZipUrl] —
///   `http://www.everyayah.com/data/<folder>/zips/NNN.zip`, Wahy's
///   exact method: that address opens from the user's Syrian
///   network, where the bare-HTTPS per-ayah URL does not). The ZIP
///   is unzipped into the same per-ayah layout the player already
///   uses, so one ZIP download caches the whole surah. The per-ayah
///   file ([everyayahUrl]) stays as the fallback for a ZIP that
///   fails or lacks an ayah. No new reciters.
/// * Resume: downloads are per-SURAH, decided from the files on
///   disk — a failed or interrupted job resumes from the next
///   missing surah, and files already on disk are never re-fetched
///   or overwritten. A manifest
///   (`<docs>/audio/<folder>/manifest.json`) still records completed
///   files. This is what makes a full-Mushaf download survivable on
///   a weak connection.
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
  /// v13.5 — the surah ZIP first: one download of
  /// `http://www.everyayah.com/data/<folder>/zips/NNN.zip` (Wahy's
  /// exact method) caches the WHOLE surah, so the next ayah in the
  /// same surah plays offline with no further download. That
  /// address opens from the user's Syrian network, where the
  /// bare-HTTPS per-ayah URL does not. The ZIP is deleted after
  /// extraction — the extracted per-ayah files ARE the cache.
  /// Secondary fallback: the per-ayah file over bare HTTPS, for
  /// networks where that address works (and when the ZIP lacks the
  /// ayah).
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
    final extracted = await _downloadSurahZip(
      reciter,
      surah,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (extracted != null) {
      final file = localAyahFile(reciter, surah, ayah);
      if (file != null) return file;
      // The ZIP extracted but this ayah is not in it: fall through
      // to the per-ayah download below.
    }
    if (isCancelled?.call() ?? false) return null;
    final file = File('${dir.path}/${reciter.everyayah}/'
        '${ayahFileName(surah, ayah)}.mp3');
    if (await _fetchToFile(
      everyayahUrl(reciter, surah, ayah),
      file,
      onProgress: onProgress,
      isCancelled: isCancelled,
    )) {
      return localAyahFile(reciter, surah, ayah);
    }
    return null;
  }

  /// Downloads one surah's everyayah ZIP and extracts it into the
  /// reciter folder (v13.5 — Wahy's exact method, see
  /// [everyayahSurahZipUrl]). Returns the extracted ayah names
  /// (SSSAAA) on success, or null when the ZIP download failed (the
  /// caller then falls back to the per-ayah download). An
  /// extraction that yields nothing (corrupt ZIP) still returns an
  /// empty set — the caller fills the missing ayahs per-ayah. The
  /// ZIP file itself is deleted after extraction: the extracted
  /// per-ayah files ARE the cache. Never throws.
  Future<Set<String>?> _downloadSurahZip(
    Reciter reciter,
    int surah, {
    DownloadProgressCallback? onProgress,
    DownloadCancelCheck? isCancelled,
  }) async {
    final dir = _baseDir;
    if (dir == null) return null;
    final reciterDir = Directory('${dir.path}/${reciter.everyayah}');
    final zipFile = File('${reciterDir.path}/zips/'
        '${surah.toString().padLeft(3, '0')}.zip');
    final ok = await _fetchToFile(
      everyayahSurahZipUrl(reciter, surah),
      zipFile,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (!ok) return null;
    try {
      return await _extractAyahZip(zipFile, reciterDir, surah);
    } finally {
      // Delete the ZIP either way: on success the per-ayah files
      // are the cache; on failure a corrupt ZIP must not linger.
      try {
        await zipFile.delete();
      } catch (_) {}
      try {
        final zipsDir = Directory('${reciterDir.path}/zips');
        if (await zipsDir.exists() &&
            (await zipsDir.list().toList()).isEmpty) {
          await zipsDir.delete();
        }
      } catch (_) {}
    }
  }

  /// Extracts a per-surah everyayah ZIP into [reciterDir] (v13.5).
  /// Only this surah's ayah files are written (`SSSAAA.mp3` where
  /// SSS is the surah — anything else in the ZIP, e.g. the
  /// `000_license.html` everyayah ships, is skipped); files already
  /// on disk are left untouched, so a re-download never overwrites
  /// an ayah the user already has. Streaming: one entry at a time,
  /// ~64 KB buffers — the 58 MB Baqarah ZIP never sits whole in
  /// memory. Returns the extracted ayah names (SSSAAA). Never
  /// throws — a corrupt or truncated ZIP yields whatever was
  /// extracted before the failure (possibly empty); files already
  /// written are valid ayah files and stay.
  Future<Set<String>> _extractAyahZip(
    File zipFile,
    Directory reciterDir,
    int surah,
  ) async {
    final extracted = <String>{};
    final prefix = surah.toString().padLeft(3, '0');
    try {
      final entries = await _readZipEntries(zipFile);
      final raf = await zipFile.open(mode: FileMode.read);
      try {
        for (final entry in entries) {
          if (!entry.name.startsWith(prefix)) continue;
          final base = entry.name.split('/').last;
          if (!RegExp(r'^\d{6}\.mp3$').hasMatch(base)) continue;
          final out = File('${reciterDir.path}/$base');
          if (await out.exists()) continue; // never overwrite
          if (await _extractZipEntry(raf, entry, out)) {
            extracted.add(base.substring(0, 6));
          }
        }
      } finally {
        await raf.close();
      }
    } catch (_) {
      // Corrupt ZIP: the caller falls back to the per-ayah download.
    }
    return extracted;
  }

  /// Reads the central directory of [zipFile] and returns one entry
  /// per file (directories skipped). ZIP64 archives are refused —
  /// the everyayah ZIPs are old-style, and a ZIP64 file falls back
  /// to the per-ayah download. Never throws: any parse failure
  /// returns an empty list.
  Future<
      List<
          ({
            String name,
            int method,
            int compressedSize,
            int uncompressedSize,
            int localHeaderOffset,
          })>> _readZipEntries(File zipFile) async {
    try {
      final length = await zipFile.length();
      if (length < 22) return [];
      // The end-of-central-directory record is the last 22 bytes,
      // plus an optional comment of up to 64 KB: scan the tail
      // backwards for its signature (0x06054b50) and accept only
      // the candidate whose comment length lands exactly at the
      // end of the file (a comment could contain the same bytes).
      final tailSize = length < 65557 ? length : 65557;
      final raf = await zipFile.open(mode: FileMode.read);
      try {
        await raf.setPosition(length - tailSize);
        final tail = await raf.read(tailSize);
        var eocd = -1;
        for (var i = tail.length - 22; i >= 0; i--) {
          if (tail[i] == 0x50 &&
              tail[i + 1] == 0x4b &&
              tail[i + 2] == 0x05 &&
              tail[i + 3] == 0x06) {
            final commentLen = tail[i + 20] | (tail[i + 21] << 8);
            if (i + 22 + commentLen == tail.length) {
              eocd = i;
              break;
            }
          }
        }
        if (eocd < 0) return [];
        final d = ByteData.sublistView(tail, eocd, eocd + 22);
        final totalEntries = d.getUint16(10, Endian.little);
        final cdSize = d.getUint32(12, Endian.little);
        final cdOffset = d.getUint32(16, Endian.little);
        // 0xFFFF / 0xFFFFFFFF mean "see the ZIP64 record" — not
        // supported, and not what everyayah ships.
        if (totalEntries == 0xFFFF ||
            cdSize == 0xFFFFFFFF ||
            cdOffset == 0xFFFFFFFF) {
          return [];
        }
        await raf.setPosition(cdOffset);
        final cd = await raf.read(cdSize);
        final entries = <({
          String name,
          int method,
          int compressedSize,
          int uncompressedSize,
          int localHeaderOffset,
        })>[];
        var pos = 0;
        while (pos + 46 <= cd.length) {
          if (cd[pos] != 0x50 ||
              cd[pos + 1] != 0x4b ||
              cd[pos + 2] != 0x01 ||
              cd[pos + 3] != 0x02) {
            break;
          }
          final e = ByteData.sublistView(cd, pos, pos + 46);
          final method = e.getUint16(10, Endian.little);
          final compSize = e.getUint32(20, Endian.little);
          final uncompSize = e.getUint32(24, Endian.little);
          final nameLen = e.getUint16(28, Endian.little);
          final extraLen = e.getUint16(30, Endian.little);
          final commentLen = e.getUint16(32, Endian.little);
          final localOffset = e.getUint32(42, Endian.little);
          final nameStart = pos + 46;
          final nameEnd = nameStart + nameLen;
          if (nameEnd > cd.length) break;
          final name = utf8.decode(cd.sublist(nameStart, nameEnd));
          if (!name.endsWith('/')) {
            entries.add((
              name: name,
              method: method,
              compressedSize: compSize,
              uncompressedSize: uncompSize,
              localHeaderOffset: localOffset,
            ));
          }
          pos = nameEnd + extraLen + commentLen;
        }
        return entries;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return [];
    }
  }

  /// Extracts one central-directory entry to [out] (v13.5). [raf]
  /// is the open ZIP file; the entry's data is read from its local
  /// header in ~64 KB chunks and inflated on the fly (raw deflate,
  /// method 8) or copied (stored, method 0) — memory stays bounded
  /// no matter how big the surah ZIP is. Returns false on any
  /// failure (unknown method, truncated data, inflate error, a
  /// short file) and leaves no partial file behind. The extracted
  /// file's length must equal the entry's uncompressed size.
  Future<bool> _extractZipEntry(
    RandomAccessFile raf,
    ({
      String name,
      int method,
      int compressedSize,
      int uncompressedSize,
      int localHeaderOffset,
    }) entry,
    File out,
  ) async {
    var success = false;
    IOSink? sink;
    try {
      await raf.setPosition(entry.localHeaderOffset);
      final header = await raf.read(30);
      if (header.length < 30 ||
          header[0] != 0x50 ||
          header[1] != 0x4b ||
          header[2] != 0x03 ||
          header[3] != 0x04) {
        return false;
      }
      final h = ByteData.sublistView(header);
      final nameLen = h.getUint16(26, Endian.little);
      final extraLen = h.getUint16(28, Endian.little);
      final dataStart = entry.localHeaderOffset + 30 + nameLen + extraLen;
      await raf.setPosition(dataStart);
      sink = out.openWrite();
      var remaining = entry.compressedSize;
      if (entry.method == 0) {
        while (remaining > 0) {
          final chunk =
              await raf.read(remaining < 65536 ? remaining : 65536);
          if (chunk.isEmpty) return false;
          sink.add(chunk);
          remaining -= chunk.length;
        }
      } else if (entry.method == 8) {
        // Raw deflate (ZIP has no zlib header). One entry's
        // compressed bytes in memory (one ayah MP3, ~50–500 KB) —
        // the ZIP as a whole is never loaded. (ZLibDecoder.bind on
        // a chunk stream never closes its output in this SDK —
        // verified by repro 2026-11-17 — so convert() on the whole
        // entry is the working path.)
        final compressed = <int>[];
        while (remaining > 0) {
          final chunk =
              await raf.read(remaining < 65536 ? remaining : 65536);
          if (chunk.isEmpty) return false;
          compressed.addAll(chunk);
          remaining -= chunk.length;
        }
        List<int> inflated;
        try {
          inflated = ZLibDecoder(raw: true).convert(compressed);
        } catch (_) {
          return false; // corrupt deflate data
        }
        sink.add(inflated);
      } else {
        return false; // unknown compression method
      }
      await sink.flush();
      await sink.close();
      sink = null;
      final size = await out.length();
      if (size != entry.uncompressedSize) return false;
      success = true;
    } catch (_) {
      success = false;
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      if (!success) {
        try {
          await out.delete();
        } catch (_) {}
      }
    }
    return success;
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
  /// Tries the hosts in [wbwWordUrlsInOrder] — SurahPedia FIRST
  /// since v13.6 (Wahy's host, the one that opens from the user's
  /// network), then the Quran.com CDN, then the legacy host. Each
  /// host is fetched by [_fetchToFile] (streamed, stall timeout
  /// only, resume + retry — v13.3): a slow connection still gets
  /// the file, it just takes longer; there is no "too slow" any
  /// more. Returns the file, or null when all three hosts fail
  /// (the player then reports the error). Never throws.
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
    for (final url in wbwWordUrlsInOrder(surah, ayah, fileNumber)) {
      if (await _fetchToFile(url, file,
          onProgress: onProgress, isCancelled: isCancelled)) {
        return localWbwFile(surah, ayah, fileNumber);
      }
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
        if (job.cancelled) {
          job.status = DownloadStatus.cancelled;
          notifyListeners();
          return;
        }
        final count = quran.getVerseCount(surah);
        // Files already on disk (from cache-on-play ZIPs or an
        // earlier run) are never re-fetched and never overwritten:
        // the job only downloads what is missing.
        final missing = <int>[];
        for (var ayah = 1; ayah <= count; ayah++) {
          if (localAyahFile(reciter, surah, ayah) == null) {
            missing.add(ayah);
          }
        }
        if (missing.isEmpty) {
          job.doneFiles += count;
        } else {
          // v13.5: one surah ZIP instead of one request per ayah.
          final written = await _downloadSurahZip(
            reciter,
            surah,
            isCancelled: () => job.cancelled,
          );
          if (written == null) {
            job.status = DownloadStatus.failed;
            job.error =
                'تعذّر تحميل السورة $surah — تحقق من الإنترنت وحاول مجدداً';
            notifyListeners();
            return;
          }
          // The ZIP may lack an ayah (bad ZIP): fill the rest from
          // the per-ayah files, so the job still completes.
          for (final ayah in missing) {
            if (job.cancelled) {
              job.status = DownloadStatus.cancelled;
              notifyListeners();
              return;
            }
            if (localAyahFile(reciter, surah, ayah) != null) continue;
            final ok = await _downloadOne(reciter, surah, ayah);
            if (!ok) {
              job.status = DownloadStatus.failed;
              job.error =
                  'تعذّر تحميل الآية $surah:$ayah — تحقق من الإنترنت وحاول مجدداً';
              notifyListeners();
              return;
            }
          }
          job.doneFiles += count;
          for (var ayah = 1; ayah <= count; ayah++) {
            manifest.add(ayahFileName(surah, ayah));
          }
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
