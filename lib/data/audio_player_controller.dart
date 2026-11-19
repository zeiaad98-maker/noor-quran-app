import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:quran/quran.dart' as quran;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_downloads.dart';
import 'qcf_word_map.dart';
import 'quran_audio.dart';
import 'word_meanings.dart';

/// Which slice of the Mushaf the player is playing.
enum PlayerScope { word, ayah, page, surah }

/// The audio engine behind the player sheet.
///
/// One ayah file at a time (everyayah.com), advanced manually, so that
/// repeat counts, prev/next, reciter switching and page following all
/// stay under our control. The old whole-surah mp3quran file is gone:
/// the surah scope is the surah's ayah files in sequence.
///
/// Word scope (v13.2): the word plays ONLY from Quran.com's dedicated
/// per-word recording (wbw — one fixed teaching voice, complete and
/// clear by construction). There is NO other word-audio path: the
/// v13/v13.1 segment path (cutting the word out of an ayah file) is
/// gone — whenever its seek failed, a tap on a word played the whole
/// ayah, which was the user's #1 complaint. If the wbw file cannot be
/// fetched, the sheet shows the error with a retry; it never falls
/// back to an ayah file.
class AudioPlayerController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();

  /// Offline downloads (v12, optional): when a downloaded ayah file
  /// exists for the current reciter, the player plays it instead of
  /// streaming — same recording (everyayah), so word-segment timings
  /// still apply. Null in tests / when downloads are not wired up.
  final AudioDownloadService? downloads;

  int reciterIndex = 0;
  PlayerScope scope = PlayerScope.page;
  List<(int, int)> queue = [];
  int queueIndex = 0;

  bool isPlaying = false;
  bool isLoading = false;
  bool isMuted = false;
  bool repeatItem = false;
  bool repeatScope = false;

  /// 0 = endless, otherwise the number of plays.
  int repeatCount = 3;
  double speed = 1.0;

  /// Whether tapping a word plays it immediately (v13.6, the word
  /// card's gear settings). Default false since v13.8 — the user
  /// only wants the meaning on tap; the green ▶ plays the word.
  /// When true, a tap plays the word at once.
  bool wordAutoPlay = false;
  int fromPage = 1;
  int toPage = 1;

  // Word scope state.
  int? wordIndex; // 1-based QCF position inside the ayah (display words).
  bool wordUsesWbw = false;
  int wordCount = 0;

  /// Fired when the playing ayah changes, so the reader can follow
  /// the playback position (jump to the ayah's page).
  void Function((int, int) ayah)? onAyahChanged;

  /// Fired on a playback error with a retry action for the SnackBar.
  void Function(String message, Future<void> Function() retry)? onError;

  /// Last playback error, shown INSIDE the player sheet (the old
  /// SnackBar-only error was hidden behind the modal sheet, so a
  /// failed word tap looked like nothing happening at all).
  String? lastError;

  /// Retries the item that failed (clears [lastError] first).
  Future<void> retryLastError() async {
    if (lastError == null) return;
    lastError = null;
    notifyListeners();
    await _playCurrent();
  }

  int _itemPlays = 0;
  int _scopePlays = 0;
  int _playToken = 0;
  // The _playToken value whose finish was already handled: the word
  // end (position listener) and the file end (state stream) can both
  // fire for the same item — the second must be ignored.
  int _finishedToken = -1;

  /// The token of the play whose audio actually STARTED (load + play
  /// succeeded). A finish (the `completed` state) is only honoured
  /// for that play: without this, a STALE finish — the previous
  /// item's file completing while the next item is still downloading
  /// on a weak connection — advances the NEW queue or stops the NEW
  /// load (v13.2 bugs 1+2: wrong ayah playing, spinner stuck). The
  /// token is set at each successful play start and cleared
  /// (`-1`) whenever a new play begins or playback stops, so a
  /// finish can never act on a play that has not started yet.
  int _finishToken = -1;

  /// True while one finish is being handled (a replay / advance /
  /// stop is in flight). The two listeners can fire for the same
  /// item end — and the platform can emit the completed state twice
  /// (playing true→false) — so a duplicate finish must be ignored
  /// even though the replay it triggered already advanced
  /// [_playToken] (the [_finishedToken] check alone races with
  /// that: the replay's `_playCurrent` increments the token
  /// synchronously, so the duplicate looks like a new finish,
  /// consumes a repeat count and kills the replay — verified in
  /// tests, v13.1). Cleared when the handling returns, i.e. once
  /// the next item has started (or failed to) or playback stopped.
  bool _handlingFinish = false;

  /// Repeat settings are persisted (SharedPreferences) and restored
  /// by [restorePlaybackSettings]: the count must survive leaving
  /// the reader and restarting the app (v13.2 bug B — the count
  /// reset to the default every time the screen was recreated).
  static const String _repeatItemKey = 'audio_repeat_item';
  static const String _repeatScopeKey = 'audio_repeat_scope';
  static const String _repeatCountKey = 'audio_repeat_count';
  static const String _speedKey = 'audio_speed';
  static const String _wordAutoPlayKey = 'word_autoplay';

  /// Plays remaining for the CURRENT item while [repeatItem] is on,
  /// counting the play in progress (so "3" at the start of play 1,
  /// "2" during play 2). -1 when repeat is off or endless (count 0).
  /// The sheet and the mini bar show it while repeating, so the user
  /// can see the repeat working and when it will stop (v13.2 bug B).
  int get repeatRemaining {
    if (!repeatItem || repeatCount == 0) return -1;
    final left = repeatCount - _itemPlays + 1;
    return left < 0 ? 0 : left;
  }

  /// Download progress of the file currently being fetched (0..1),
  /// or null when no download is in progress or the server gives no
  /// length. The sheet, the mini bar and the word card show it while
  /// loading, so the user sees the download moving instead of a bare
  /// spinner (v13.3, FIX A). Updated from the download service's
  /// per-chunk callback; notifications are throttled to whole
  /// percent steps so the UI is not rebuilt on every chunk.
  double? downloadProgress;
  double _lastNotifiedProgress = -1;

  /// Feeds [downloadProgress] from the download service (v13.3).
  /// A null [total] means the server streams without a length: the
  /// UI then shows an indeterminate bar.
  void _onDownloadProgress(int received, int? total) {
    if (_disposed) return;
    if (total == null || total <= 0) {
      downloadProgress = null;
    } else {
      downloadProgress = (received / total).clamp(0.0, 1.0);
    }
    final p = downloadProgress;
    if (p == null) return;
    if ((p - _lastNotifiedProgress).abs() >= 0.01 || p >= 1.0) {
      _lastNotifiedProgress = p;
      notifyListeners();
    }
  }

  bool _disposed = false;

  (int, int)? get currentAyah => queue.isEmpty ? null : queue[queueIndex];

  Reciter get reciter => reciters[reciterIndex];

  AudioPlayerController({this.downloads}) {
    // The ONLY finish signal: the file's `completed` state. (The
    // v12/v13.1 position listener that stopped a word at its segment
    // end is gone with the segment path — a wbw word file IS the
    // word, it plays to its own completion.)
    _player.playerStateStream.listen((state) {
      if (_disposed) return;
      final playing = state.playing;
      if (playing != isPlaying) {
        isPlaying = playing;
        notifyListeners();
      }
      if (state.processingState == ProcessingState.completed) {
        _onItemFinished();
      }
    });
  }

  /// Restores the persisted repeat / speed settings (called once by
  /// the reader after creating the controller). The reciter has its
  /// own restore ([setInitialReciterIndex]).
  Future<void> restorePlaybackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    repeatItem = prefs.getBool(_repeatItemKey) ?? false;
    repeatScope = prefs.getBool(_repeatScopeKey) ?? false;
    repeatCount = prefs.getInt(_repeatCountKey) ?? 3;
    speed = prefs.getDouble(_speedKey) ?? 1.0;
    wordAutoPlay = prefs.getBool(_wordAutoPlayKey) ?? false;
    notifyListeners();
  }

  Future<void> _persistPlaybackSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_repeatItemKey, repeatItem);
    await prefs.setBool(_repeatScopeKey, repeatScope);
    await prefs.setInt(_repeatCountKey, repeatCount);
    await prefs.setDouble(_speedKey, speed);
    await prefs.setBool(_wordAutoPlayKey, wordAutoPlay);
  }

  /// Word-card gear setting (v13.6): tapping a word plays it at once
  /// (true) or only opens the card (false, the default since v13.8).
  void setWordAutoPlay(bool value) {
    wordAutoPlay = value;
    notifyListeners();
    unawaited(_persistPlaybackSettings());
  }

  /// Sets the reciter without playing or persisting (initial restore).
  void setInitialReciterIndex(int index) {
    reciterIndex = index.clamp(0, reciters.length - 1);
    notifyListeners();
  }

  Future<void> setReciter(int index) async {
    if (index < 0 || index >= reciters.length) return;
    reciterIndex = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reciter_index', index);
    notifyListeners();
    // Rebuild the current item with the new reciter's folder and
    // resume from the same ayah / word, not from the start.
    if (queue.isNotEmpty) {
      await _playCurrent();
    }
  }

  /// Pure repeat decision, pinned by unit tests: [repeatCount] 0 =
  /// endless, otherwise the item / scope replays until it has played
  /// that many times in total — [plays] counts the play that just
  /// finished, starting at 1. (So count 3 replays after plays 1 and
  /// 2, and stops after play 3; count 1 never replays.)
  static bool shouldRepeat({
    required bool enabled,
    required int repeatCount,
    required int plays,
  }) =>
      enabled && (repeatCount == 0 || plays < repeatCount);

  void setRepeatCount(int count) {
    repeatCount = count;
    // Picking a count IS asking to repeat (v13.2 bug B): the count
    // menu used to set the number while the repeat toggle stayed
    // off, so "3 مرات" did nothing at all. Count 1 = play once =
    // repeat off; any other count turns repeat-item on.
    repeatItem = count != 1;
    notifyListeners();
    unawaited(_persistPlaybackSettings());
  }

  void toggleRepeatItem() {
    repeatItem = !repeatItem;
    notifyListeners();
    unawaited(_persistPlaybackSettings());
  }

  void toggleRepeatScope() {
    repeatScope = !repeatScope;
    notifyListeners();
    unawaited(_persistPlaybackSettings());
  }

  Future<void> setSpeed(double value) async {
    speed = value;
    await _player.setSpeed(value);
    notifyListeners();
    unawaited(_persistPlaybackSettings());
  }

  /// [word] is the 1-based QCF position (the index the reader
  /// reports for the tapped glyph). The audio position is derived
  /// from it ([audioPositionForQcfWord]) — in the 4 merged ayahs
  /// the QCF and audio numberings differ (2:181, 8:6, 13:37, 37:130).
  Future<void> playWord(int surah, int ayah, int word) async {
    scope = PlayerScope.word;
    queue = [(surah, ayah)];
    queueIndex = 0;
    wordIndex = word;
    wordUsesWbw = false;
    wordCount = _qcfWordCount(surah, ayah);
    _scopePlays = 1;
    await _playCurrent();
  }

  /// The word card's repeat button (v13.6): plays JUST this word
  /// [repeatCount] times (the count the user picked in the word
  /// settings; if it is 1 — "play once" — repeat 3 times, the
  /// default, so the button always repeats). Reuses [setRepeatCount]
  /// so the repeat flags and persistence follow the pinned path.
  Future<void> repeatWord(int surah, int ayah, int word) async {
    setRepeatCount(repeatCount == 1 ? 3 : repeatCount);
    await playWord(surah, ayah, word);
  }

  Future<void> playAyah(int surah, int ayah) async {
    scope = PlayerScope.ayah;
    queue = [(surah, ayah)];
    queueIndex = 0;
    wordIndex = null;
    _scopePlays = 1;
    await _playCurrent();
  }

  Future<void> playPages(int from, int to) async {
    scope = PlayerScope.page;
    fromPage = from;
    toPage = to;
    queue = ayahsOfPages(from, to);
    queueIndex = 0;
    wordIndex = null;
    _scopePlays = 1;
    // v13.12 — whole-page preload, restructured (the user's
    // order, 2026-11-18, corrected the same day): the page plays
    // ONLY after ALL its ayahs are downloaded; no sound until
    // the page is fully cached, no ayah-by-ayah loading
    // mid-playback. Silent: no progress UI (the user chose no
    // download display at all); the play button spinner is the only
    // sign. The v13.11 preload failed the WHOLE page on the FIRST
    // failed ayah, so one bad file killed a page even when the
    // other ayahs were already cached — now [AudioDownloadService.
    // preloadAyahs] collects the missing ayahs first and runs
    // the full per-ayah chain ONCE MORE for them, and only ayahs
    // STILL missing after both passes fail the page. There is NO
    // whole-surah ZIP in the playback path at all (the user's
    // correction: one page plays by itself, without the whole
    // surah). Cached ayahs return at once, so a replay / retry
    // costs nothing. stop() aborts the preload via the token
    // (see stop()).
    // v13.14 — the preload is still ATTEMPTED first (a fully
    // cached page plays from local files, exactly as before), but
    // it is no longer a GATE: when it fails, playback falls
    // through to [_playCurrent] instead of erroring out. The
    // user's phone fails EVERY Dart http download, so the gate
    // meant the page scope never played at all — while the ayah
    // scope streams fine through the native player. See the
    // fall-through below.
    final token = ++_playToken;
    lastError = null;
    isLoading = true;
    downloadProgress = null;
    notifyListeners();
    final dl = downloads;
    var preloaded = true;
    if (dl != null) {
      preloaded = await dl.preloadAyahs(
        reciter,
        queue,
        isCancelled: () => token != _playToken,
      );
    }
    if (token != _playToken || _disposed) return;
    if (!preloaded) {
      // v13.14 — fall through to _playCurrent() instead of
      // reporting the error: the preload gate was the single point
      // of failure on the user's phone. His phone fails EVERY Dart
      // http download (all hosts, all versions), so the page scope
      // NEVER played — it errored without ever trying the native
      // player. _playCurrent plays ayah-by-ayah from the cache when
      // present and otherwise streams each ayah through the native
      // player (ExoPlayer, the path SurahApp/Wahy use), trying
      // every host in order — and reports the error itself if the
      // first ayah fails on every path. The spinner state is
      // reset here first; _playCurrent sets its own loading state.
      isLoading = false;
      downloadProgress = null;
      notifyListeners();
    }
    await _playCurrent();
  }

  Future<void> playSurah(int surah) async {
    scope = PlayerScope.surah;
    queue = ayahsOfSurah(surah);
    queueIndex = 0;
    wordIndex = null;
    _scopePlays = 1;
    await _playCurrent();
  }

  /// استمرار (v13.6, the word card's "continue" button): play the
  /// surah from THIS ayah onward, in Mushaf order — the recitation
  /// continues past the ayah instead of stopping at it (the ayah
  /// scope repeats one ayah; the surah scope starts at ayah 1).
  /// At the last ayah the queue is just that ayah, so it behaves
  /// like playAyah there.
  Future<void> playFromAyah(int surah, int ayah) async {
    scope = PlayerScope.surah;
    final all = ayahsOfSurah(surah);
    final start = all.indexWhere((a) => a.$1 == surah && a.$2 == ayah);
    queue = start < 0 ? [(surah, ayah)] : all.sublist(start);
    queueIndex = 0;
    wordIndex = null;
    _scopePlays = 1;
    await _playCurrent();
  }

  /// Replays the current item from its start, whether it is playing
  /// or already finished (the mini bar's replay button). A manual
  /// replay restarts the repeat count: the replayed play is play 1
  /// again, so a repeat count of 3 still means 3 plays from here.
  /// A no-op with an empty queue (safe to tap before anything plays).
  Future<void> replayCurrent() async {
    if (queue.isEmpty) return;
    await _playCurrent();
  }

  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await _player.pause();
      return;
    }
    if (queue.isEmpty) return;
    if (_player.processingState == ProcessingState.completed) {
      await _playCurrent();
    } else {
      await _player.play();
    }
  }

  Future<void> next() async {
    _cancelRepeat();
    if (scope == PlayerScope.word) {
      await _nextWord();
      return;
    }
    if (queueIndex < queue.length - 1) {
      queueIndex++;
      _itemPlays = 1;
      onAyahChanged?.call(queue[queueIndex]);
      await _playCurrent();
    }
  }

  Future<void> previous() async {
    _cancelRepeat();
    if (scope == PlayerScope.word) {
      await _previousWord();
      return;
    }
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }
    if (queueIndex > 0) {
      queueIndex--;
      _itemPlays = 1;
      onAyahChanged?.call(queue[queueIndex]);
      await _playCurrent();
    }
  }

  /// A manual tap (next / prev / stop / close) cancels repeat
  /// immediately (v13.2 bug B / best-apps rule 3): the user asked
  /// for something else, so the repeat must not carry over to the
  /// next item. Automatic advance (queue end / repeat itself) never
  /// calls this.
  void _cancelRepeat() {
    if (repeatItem || repeatScope) {
      repeatItem = false;
      repeatScope = false;
      notifyListeners();
      unawaited(_persistPlaybackSettings());
    }
  }

  Future<void> stop() async {
    // Invalidate any in-flight _playCurrent: without this, a load
    // that finishes after the user closed the sheet would seek + play
    // with no UI at all (ghost audio), and its finally{} would clear
    // the next load's spinner.
    final token = ++_playToken;
    _finishToken = -1;
    _cancelRepeat();
    await _player.stop();
    if (!_disposed && token == _playToken) {
      isPlaying = false;
      // A load invalidated by stop() must not leave the spinner up
      // (v13.2 bug 2): the in-flight _playCurrent's finally{} skips
      // clearing when its token no longer matches — so stop() itself
      // clears it. The token check above keeps a NEWER load's
      // spinner (started after this stop) untouched. The download
      // progress goes away with the load (v13.3, FIX A); the
      // in-flight download itself aborts via the token check the
      // controller passed to the download service.
      isLoading = false;
      downloadProgress = null;
      notifyListeners();
    }
  }

  /// Mutes / unmutes the player (the word popup's mute button).
  /// Just sets the volume to 0 / back to 1 — the playback position
  /// and state are untouched, so unmuting resumes the sound in place.
  Future<void> toggleMute() async {
    isMuted = !isMuted;
    await _player.setVolume(isMuted ? 0.0 : 1.0);
    notifyListeners();
  }

  // -- internals -------------------------------------------------------

  /// Word count of an ayah in DISPLAY numbering (the QCF word list
  /// the reader taps): the bound for next/previous word, so it can
  /// never walk past the last word. This is the count the user sees
  /// (4 words in 37:130), NOT the morphology/audio count (3 there —
  /// إِلۡ يَاسِينَ is one audio word): with the audio count, next-word
  /// from word 3 jumped to the next ayah and skipped يَاسِينَ
  /// entirely (v13.2 bug 1). Synchronous — the QCF map is built from
  /// bundled data only.
  int _qcfWordCount(int surah, int ayah) =>
      buildQcfWordMap(surah, ayah).wordCount;

  Future<void> _nextWord() async {
    final ayah = currentAyah;
    final word = wordIndex;
    if (ayah == null || word == null) return;
    if (word < wordCount) {
      wordIndex = word + 1;
      await _playCurrent();
      return;
    }
    final nextAyah = _adjacentAyah(ayah, 1);
    if (nextAyah == null) return;
    queue = [nextAyah];
    queueIndex = 0;
    wordIndex = 1;
    wordCount = _qcfWordCount(nextAyah.$1, nextAyah.$2);
    onAyahChanged?.call(nextAyah);
    await _playCurrent();
  }

  Future<void> _previousWord() async {
    final ayah = currentAyah;
    final word = wordIndex;
    if (ayah == null || word == null) return;
    if (word > 1) {
      wordIndex = word - 1;
      await _playCurrent();
      return;
    }
    final prevAyah = _adjacentAyah(ayah, -1);
    if (prevAyah == null) return;
    queue = [prevAyah];
    queueIndex = 0;
    wordCount = _qcfWordCount(prevAyah.$1, prevAyah.$2);
    wordIndex = wordCount;
    onAyahChanged?.call(prevAyah);
    await _playCurrent();
  }

  /// The ayah after/before [ayah] in Mushaf order, or null at the ends.
  (int, int)? _adjacentAyah((int, int) ayah, int step) {
    var (surah, verse) = ayah;
    verse += step;
    if (verse < 1) {
      surah -= 1;
      if (surah < 1) return null;
      verse = quran.getVerseCount(surah);
    } else if (verse > quran.getVerseCount(surah)) {
      surah += 1;
      if (surah > 114) return null;
      verse = 1;
    }
    return (surah, verse);
  }

  Future<void> _onItemFinished() async {
    if (_disposed || queue.isEmpty) return;
    // Only the play that actually STARTED may finish: a stale
    // `completed` (the previous item's file ending while the next
    // item is still downloading) must not advance the new queue or
    // stop the new load (v13.2 bugs 1+2 — see [_finishToken]).
    if (_playToken != _finishToken) return;
    if (_handlingFinish) return;
    if (_finishedToken == _playToken) return;
    _finishedToken = _playToken;
    _handlingFinish = true;
    try {
      if (shouldRepeat(
          enabled: repeatItem,
          repeatCount: repeatCount,
          plays: _itemPlays)) {
        _itemPlays++;
        await _playCurrent(isReplay: true);
        return;
      }
      if (queueIndex < queue.length - 1) {
        queueIndex++;
        onAyahChanged?.call(queue[queueIndex]);
        await _playCurrent();
        return;
      }
      if (shouldRepeat(
          enabled: repeatScope,
          repeatCount: repeatCount,
          plays: _scopePlays)) {
        _scopePlays++;
        queueIndex = 0;
        onAyahChanged?.call(queue[queueIndex]);
        await _playCurrent();
        return;
      }
      await stop();
    } finally {
      _handlingFinish = false;
    }
  }

  /// One play attempt (load + play). v13.3 (FIX A): there is NO
  /// wall-clock budget on an attempt any more — the 60 s budget was
  /// killing slow-but-working downloads, which is exactly what the
  /// user forbade ("words must download at ANY speed, even the
  /// slowest"). Every step still ends: downloads fail only on a
  /// stall (no bytes for 30 s, see [AudioDownloadService]) or a
  /// cancel (stop / a newer play, via the token check), and the
  /// just_audio steps keep their own short timeouts below. A
  /// superseded attempt's failure is never the user's error (see the
  /// catches below).
  Future<void> _playCurrent({bool isReplay = false}) async {
    final ayah = currentAyah;
    if (ayah == null) return;
    final token = ++_playToken;
    _finishToken = -1;
    if (!isReplay) _itemPlays = 1;
    lastError = null;
    isLoading = true;
    downloadProgress = null;
    _lastNotifiedProgress = -1;
    notifyListeners();

    // Stop the previous audio FIRST, before any download await: the
    // old file must not complete mid-load and fire a stale finish
    // that advances the NEW queue or stops the NEW load (v13.2 bugs
    // 1+2). Without this, the old ayah finishing during a slow
    // download on weak internet was the wrong-ayah / stuck-spinner
    // race.
    await _player.stop();
    if (token != _playToken || _disposed) return;

    try {
      if (scope == PlayerScope.word) {
        await _playWordCurrent(token, ayah);
      } else {
        // Cache-on-play (v13): the ayah file is downloaded once and
        // played from disk after that — clear, pure and complete on
        // a weak connection, instant on repeat, offline after.
        // A failed download falls back to streaming below. The
        // download reports honest progress and aborts when this
        // attempt is superseded (v13.3, FIX A).
        final local = await downloads?.cacheAyahFile(
          reciter,
          ayah.$1,
          ayah.$2,
          onProgress: _onDownloadProgress,
          isCancelled: () => token != _playToken,
        );
        if (token != _playToken || _disposed) return;
        // Bounded: the old bare setUrl could hang forever on a
        // stalled connection, leaving the spinner up with no sound
        // and no error.
        if (local != null) {
          await _player
              .setFilePath(local.path)
              .timeout(const Duration(seconds: 20));
          if (token != _playToken || _disposed) return;
          await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
          await _player.play().timeout(const Duration(seconds: 10));
        } else {
          // Streaming fallback (v13.12 — the user's correction,
          // 2026-11-18): Wahy plays ONE ayah directly, without
          // the whole surah — and the word path already streams
          // from every host in order. The ayah path streamed
          // ONLY the bare everyayah URL (blocked from Syria).
          // Now it tries every host in order
          // ([ayahStreamUrlsInOrder]): www first, then the
          // alternate hosts, then islamic.network, bare last —
          // via [_loadAndPlay], which returns false on timeout
          // or error, like the word path. All hosts failed:
          // report the error, never silence.
          var streamed = false;
          for (final url
              in ayahStreamUrlsInOrder(reciter, ayah.$1, ayah.$2)) {
            if (token != _playToken || _disposed) return;
            if (await _loadAndPlay(url, Duration.zero, token)) {
              streamed = true;
              break;
            }
          }
          if (!streamed) {
            if (token == _playToken) _reportError(_playCurrent);
            return;
          }
        }
        _finishToken = token;
        // Prefetch the next ayah while this one plays, so page /
        // surah playback has no gap between ayahs on a weak
        // connection. Best-effort: failures are ignored, the next
        // play falls back to streaming. v13.10: the prefetch and
        // the next play share one in-flight download per file (the
        // download service dedupes by target path), so the prefetch
        // can never corrupt the foreground load.
        final dl = downloads;
        if (dl != null && queueIndex + 1 < queue.length) {
          final nextAyah = queue[queueIndex + 1];
          unawaited(
            dl.cacheAyahFile(reciter, nextAyah.$1, nextAyah.$2).then((_) {}),
          );
        }
      }
    } on TimeoutException {
      // A superseded attempt's failure is not the user's error
      // (v13.2 bug 2): the load this attempt was waiting on was
      // abandoned by stop() / a newer play, and just_audio reports
      // the cancelled load as an error — swallowing it keeps stop()
      // silent instead of flashing a bogus "check your internet".
      if (token == _playToken) _reportError(_playCurrent);
    } on PlayerException {
      if (token == _playToken) _reportError(_playCurrent);
    } catch (_) {
      if (token == _playToken) _reportError(_playCurrent);
    } finally {
      // A stale token's finally must not clear the newer load's
      // spinner (the old code did, so the spinner vanished while
      // the new word was still loading).
      if (!_disposed && token == _playToken) {
        isLoading = false;
        downloadProgress = null;
        notifyListeners();
      }
    }
  }

  /// Word scope (v13.2): the word plays ONLY from Quran.com's
  /// dedicated per-word recording (wbw) — one fixed teaching voice,
  /// complete and clear by construction, exactly like the world
  /// apps. No segments, no cutting, no ayah file: the v13/v13.1
  /// segment fallback loaded the ayah file and cut the word out of
  /// it, and whenever the seek failed the tap played the whole ayah
  /// (the user's #1 complaint) — so the fallback is GONE, not
  /// demoted. If the wbw file cannot be fetched, the sheet shows
  /// the error with a retry. The download itself has no wall-clock
  /// limit (v13.3, FIX A): it fails only on a stall or a cancel.
  Future<void> _playWordCurrent(int token, (int, int) ayah) async {
    final qcfWord = wordIndex ?? 1;
    if (await _playWbwWord(token, ayah, qcfWord)) return;
    // wbw failed on every host (and not cached): nothing else to
    // play — report the error, never an ayah file.
    wordUsesWbw = false;
    _reportError(_playCurrent);
  }

  /// Plays one word from its dedicated wbw recording (v13.2).
  /// Returns true when the word really plays (cached file, or the
  /// new CDN, or the legacy host, or SurahPedia), false when every
  /// wbw attempt failed — the caller then reports the error. The
  /// wbw file has no seek and no word end: it plays to its own
  /// completion, so the `completed` state is its only finish.
  /// [wordUsesWbw] is set ONLY on success.
  ///
  /// [qcfWord] is the 1-based QCF position (the reader's tap index);
  /// [audioPositionForQcfWord] translates it to the audio word
  /// position (in the 4 merged ayahs the two differ) — which IS
  /// the wbw file number (v13.4, no shift table).
  Future<bool> _playWbwWord(int token, (int, int) ayah, int qcfWord) async {
    final tokens = await QuranWordData.wordsForAyah(ayah.$1, ayah.$2);
    if (token != _playToken || _disposed) return false;
    final audioPos = audioPositionForQcfWord(ayah.$1, ayah.$2, qcfWord);
    if (audioPos < 1 || audioPos > tokens.length) return false;
    // v13.4: the wbw file number IS the audio position — the files
    // are numbered by word position only (pause marks do not count;
    // the Quran.com API's audio_url counts them and is wrong
    // relative to its own files — proven by transcription). No
    // shift table any more: it encoded the API's wrong numbers.
    final fileNumber = audioPos;
    final wbwLocal = await downloads?.cacheWbwFile(
      ayah.$1,
      ayah.$2,
      fileNumber,
      onProgress: _onDownloadProgress,
      isCancelled: () => token != _playToken,
    );
    if (token != _playToken || _disposed) return false;
    if (wbwLocal != null &&
        await _loadLocal(wbwLocal, Duration.zero, token)) {
      wordUsesWbw = true;
      _finishToken = token;
      return true;
    }
    // No cached file (or a corrupt one): stream, in the same order
    // as the cache path — SurahPedia first (v13.6), then the Quran.com
    // CDN, then the legacy host ([wbwWordUrlsInOrder]).
    for (final url in wbwWordUrlsInOrder(ayah.$1, ayah.$2, fileNumber)) {
      if (await _loadAndPlay(url, Duration.zero, token)) {
        wordUsesWbw = true;
        _finishToken = token;
        return true;
      }
    }
    return false;
  }

  /// Same as [_loadAndPlay] but for a downloaded local file
  /// (setFilePath instead of setUrl). Returns false on any error so
  /// the caller can fall back to streaming. The [token] is checked
  /// after every await: a superseded load must bail BEFORE playing
  /// (no ghost audio after a stop / timeout invalidated it).
  Future<bool> _loadLocal(File file, Duration seekTo, int token) async {
    try {
      await _player.setFilePath(file.path).timeout(const Duration(seconds: 10));
      if (token != _playToken) return false;
      await _player.seek(seekTo).timeout(const Duration(seconds: 5));
      if (token != _playToken) return false;
      await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
      await _player.play().timeout(const Duration(seconds: 10));
      if (token != _playToken) {
        await _player.stop();
        return false;
      }
      return await _waitForPositionBeyond(seekTo);
    } catch (_) {
      return false;
    }
  }

  /// Loads [url], seeks when [seekTo] is given, plays, and waits
  /// until the position actually moves past the seek point — a
  /// stalled buffer leaves the position frozen, which is exactly
  /// the "spinner forever, no sound" failure. Returns false on any
  /// timeout or error instead of throwing; the caller decides the
  /// fallback. The [token] is checked after every await (see
  /// [_loadLocal]).
  Future<bool> _loadAndPlay(String url, Duration seekTo, int token) async {
    try {
      await _player.setUrl(url).timeout(const Duration(seconds: 10));
      if (token != _playToken) return false;
      await _player.seek(seekTo).timeout(const Duration(seconds: 5));
      if (token != _playToken) return false;
      await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
      await _player.play().timeout(const Duration(seconds: 10));
      if (token != _playToken) {
        await _player.stop();
        return false;
      }
      return await _waitForPositionBeyond(seekTo);
    } catch (_) {
      return false;
    }
  }

  /// True once the player position has moved past [target] (+100 ms
  /// of slack), or the item already finished (a very short word can
  /// complete before the first position event arrives — it did play).
  /// False after 6 s with no movement (buffering stall). The timer
  /// lives inside, so timing out cannot leak the subscription.
  Future<bool> _waitForPositionBeyond(Duration target) async {
    final beyond = target + const Duration(milliseconds: 100);
    if (_player.position > beyond ||
        _player.processingState == ProcessingState.completed) {
      return true;
    }
    final completer = Completer<bool>();
    void done(bool value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    late final StreamSubscription<Duration> sub;
    sub = _player.positionStream.listen((position) {
      if (position > beyond) done(true);
    });
    final timer = Timer(const Duration(seconds: 6), () => done(false));
    try {
      return await completer.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  /// The plain failure message (v13.3, FIX A — the approved sample's
  /// exact wording). The old message that blamed the user's
  /// connection is GONE: the user was right to be angry at it —
  /// most people in the region have weak internet, and a word file
  /// must download at any speed. This message says only that the
  /// download failed and offers a retry; it never mentions strong
  /// or weak internet.
  void _reportError(Future<void> Function() retry) {
    isPlaying = false;
    lastError = 'تعذّر تحميل الصوت — تحقق من الاتصال وحاول مجدداً';
    notifyListeners();
    onError?.call(
      'تعذّر تحميل الصوت — تحقق من الاتصال وحاول مجدداً',
      retry,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    super.dispose();
  }
}
