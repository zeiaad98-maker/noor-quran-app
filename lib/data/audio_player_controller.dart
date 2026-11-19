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

  /// v13.15 (DIAGNOSTIC): the real error behind the last failed
  /// native-player load ([_loadAndPlay] / [_loadLocal]) — the URL
  /// plus the exception (`"<url> — <runtimeType>: <message>"`).
  /// The generic [lastError] never says why; this does. Shown via
  /// [lastDiagnostic] in the player sheet. Cleared at the start of
  /// each [_playCurrent] and on a successful load.
  String? lastStreamError;

  /// v13.15 (DIAGNOSTIC): the detail line shown under [lastError]
  /// in the player sheet — "stage: real error", e.g.
  /// `"تشغيل: <url> — PlatformException: ..."` and, when a download
  /// also failed, `"تنزيل: <host> — ..."`. Set by [_reportError]
  /// from [lastStreamError] and the download service's
  /// [AudioDownloadService.lastDownloadError]; null when there is
  /// nothing to diagnose (e.g. a superseded attempt).
  String? lastDiagnostic;

  /// Retries the item that failed (clears [lastError] first).
  Future<void> retryLastError() async {
    if (lastError == null) return;
    lastError = null;
    // v13.15: the retry starts a fresh diagnosis.
    lastDiagnostic = null;
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

  /// v13.18 — SLOW-HOST SWITCH: how long [_loadAndPlay] waits for
  /// the FIRST buffered data from one host before abandoning it
  /// for the next host in the chain — and how long its `setUrl`
  /// gets. HARD REQUIREMENT (his words, 2026-11-19: «لازم ثانية
  /// او ثانيتين يكون جاهز — يا ثانية يا ثانيتين»): first audio
  /// within 1–2 s per ayah. The user's phone waited the full 30 s
  /// stall window on SurahPedia for EVERY ayah (~30 s pause
  /// between ayahs) even though a faster host was next in line.
  /// Mutable so tests can shrink it (the download service's
  /// [AudioDownloadService.stallTimeout] is mutable the same way).
  /// The last host in the chain never uses it (full 30 s stall
  /// window as the weakest-net backstop), and neither does a local
  /// file.
  Duration firstDataTimeout = const Duration(seconds: 2);

  /// v13.18 — stall window for [_waitForPositionBeyond]: no
  /// buffered progress at all for this long fails the wait. Every
  /// buffered advance re-arms it, so a slow-but-progressing
  /// stream is never failed for being slow (weakest-net rule).
  /// Mutable so tests can shrink it.
  Duration positionStallTimeout = const Duration(seconds: 30);

  /// v13.18 — COMPLETION WATCHDOG grace: once the player is
  /// playing and the position has reached the item's duration
  /// (within 500 ms) with no `completed` event, this long is
  /// allowed before the item is treated as finished and the
  /// playback advances. Mutable so tests can shrink it.
  Duration advanceWatchdogGrace = const Duration(seconds: 5);

  /// The completion watchdog's timer (v13.18, see
  /// [_armAdvanceWatchdog]). Null when no item is playing.
  Timer? _advanceWatchdog;

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
    // v13.17 — DIRECT STREAM (the user's order, 2026-11-19:
    // «خلي الكلمة والاية والصفحة خليها دغري يجيبها من النت»):
    // the page streams DIRECTLY from the internet through the
    // native player — NO whole-page preload, NO Dart download
    // gate. The v13.12–v13.16 preload (download the whole page
    // before any sound) spun for 14+ minutes on the user's phone
    // with no sound and no error, because the Dart downloads
    // crawl there. A cached ayah still plays from disk when it
    // is already present ([_playCurrent] checks the local file
    // first); the background prefetch warms the cache while the
    // page plays, so replays and offline benefit. The surah
    // scope is the exception: it still downloads first (the
    // user's order — «خلي الصورة اذا بدنا نحملها»). There is NO
    // whole-surah ZIP in the playback path.
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
    _cancelAdvanceWatchdog();
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

  /// Completion watchdog (v13.18): a streamed ayah can play its
  /// sound to the end while the platform never emits `completed`
  /// — the page then sits on the first ayah forever with the
  /// pause icon showing. Once an item really started, this
  /// watches for its end: if the player is still playing and the
  /// position has reached the item's duration (within 500 ms)
  /// but no `completed` arrives within [advanceWatchdogGrace],
  /// the item is treated as finished and [_onItemFinished] runs
  /// exactly as if the platform had completed it (repeat logic
  /// included — it is reused, not duplicated). A pause resets
  /// the grace clock (the player must be playing for the grace
  /// to count); a new play, a stop, or a dispose cancels the
  /// watch. It can only fire for the play that started it (the
  /// token + finish-token guard), and [_onItemFinished]'s own
  /// guards dedupe it against a real `completed` event.
  void _armAdvanceWatchdog(int token) {
    _cancelAdvanceWatchdog();
    DateTime? endReachedAt;
    _advanceWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || token != _playToken || token != _finishToken) {
        _cancelAdvanceWatchdog();
        return;
      }
      final duration = _player.duration;
      final atEnd = _player.playing &&
          duration != null &&
          duration > Duration.zero &&
          _player.position >= duration - const Duration(milliseconds: 500);
      if (!atEnd) {
        endReachedAt = null;
        return;
      }
      endReachedAt ??= DateTime.now();
      if (DateTime.now().difference(endReachedAt!) >=
          advanceWatchdogGrace) {
        _cancelAdvanceWatchdog();
        _onItemFinished();
      }
    });
  }

  void _cancelAdvanceWatchdog() {
    _advanceWatchdog?.cancel();
    _advanceWatchdog = null;
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
  /// just_audio steps keep their own 30 s stall timeouts below
  /// (v13.17 weakest-net rule: a slow-but-progressing stream is
  /// never failed for being slow — only a true stall fails). A
  /// superseded attempt's failure is never the user's error (see the
  /// catches below).
  Future<void> _playCurrent({bool isReplay = false}) async {
    final ayah = currentAyah;
    if (ayah == null) return;
    final token = ++_playToken;
    _finishToken = -1;
    _cancelAdvanceWatchdog();
    if (!isReplay) _itemPlays = 1;
    lastError = null;
    // v13.15: fresh attempt, fresh diagnosis.
    lastStreamError = null;
    lastDiagnostic = null;
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
        // v13.17 — STREAM DIRECTLY for the word / ayah / page
        // scopes (the user's order, 2026-11-19: «خلي الكلمة
        // والاية والصفحة خليها دغري يجيبها من النت»): the ayah
        // comes straight from the internet through the native
        // player — NO foreground Dart download. The local file
        // is used ONLY when it is already on disk and valid:
        // [localAyahFile] is a sync check, and the v13.16
        // validation deletes an invalid file on the spot. The
        // surah scope is the exception: it still downloads
        // first (the user's order — «خلي الصورة اذا بدنا
        // نحملها»), so it keeps the old cache-on-play path
        // below: the file is downloaded once and played from
        // disk after that — clear, pure and complete on a weak
        // connection, instant on repeat, offline after.
        File? local;
        if (scope == PlayerScope.surah) {
          local = await downloads?.cacheAyahFile(
            reciter,
            ayah.$1,
            ayah.$2,
            onProgress: _onDownloadProgress,
            isCancelled: () => token != _playToken,
          );
        } else {
          local = downloads?.localAyahFile(reciter, ayah.$1, ayah.$2);
        }
        if (token != _playToken || _disposed) return;
        // v13.16: a cached file that will not play is a POISONED
        // cache entry (a partial/corrupt file from an old stalled
        // download, reused forever because the cache trusted any
        // existing file) — delete it and fall through to
        // streaming instead of erroring out. The error is
        // reported only when streaming fails on every URL too.
        // The file's size is recorded in the diagnostic: a 0-byte
        // or few-hundred-byte file is the smoking gun.
        var played = false;
        if (local != null) {
          try {
            await _player
                .setFilePath(local.path)
                .timeout(const Duration(seconds: 20));
            if (token != _playToken || _disposed) return;
            await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
            await _player.play().timeout(const Duration(seconds: 30));
            played = true;
          } catch (e) {
            // A superseded attempt's failure is not the file's
            // fault (v13.2 bug 2): the load was abandoned by
            // stop() / a newer play, so the file stays.
            if (token != _playToken || _disposed) return;
            var size = -1;
            try {
              size = local.lengthSync();
            } catch (_) {}
            lastStreamError =
                'play — $size bytes — ${e.runtimeType}: $e';
            try {
              await local.delete();
            } catch (_) {}
            // v13.16: the failed play() left just_audio's
            // `playing` stuck true (it is set before the platform
            // call and never reverted on error) — the streaming
            // fallback below would then return at once ("if
            // (playing) return") without playing anything, while
            // the position extrapolates past the check, faking a
            // success with no sound. Stop resets the flag so the
            // fallback really plays.
            try {
              await _player.stop();
            } catch (_) {}
          }
        }
        if (!played) {
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
          final streamUrls =
              ayahStreamUrlsInOrder(reciter, ayah.$1, ayah.$2);
          for (var i = 0; i < streamUrls.length; i++) {
            if (token != _playToken || _disposed) return;
            if (await _loadAndPlay(streamUrls[i], Duration.zero, token,
                isLastHost: i == streamUrls.length - 1)) {
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
      // v13.18 — completion watchdog: arm it only once the item
      // really started (the finish token matches this attempt).
      // A failed load never reaches here (it reports the error
      // and returns), so the watch never arms for a silent play.
      if (_finishToken == token) _armAdvanceWatchdog(token);
    } on TimeoutException catch (e) {
      // A superseded attempt's failure is not the user's error
      // (v13.2 bug 2): the load this attempt was waiting on was
      // abandoned by stop() / a newer play, and just_audio reports
      // the cancelled load as an error — swallowing it keeps stop()
      // silent instead of flashing a bogus "check your internet".
      // v13.15: a timeout outside _loadAndPlay (e.g. the word
      // path) still deserves a recorded cause — keep the more
      // specific stream error when one exists.
      if (token == _playToken) {
        lastStreamError ??= 'play — TimeoutException: $e';
        _reportError(_playCurrent);
      }
    } on PlayerException catch (e) {
      if (token == _playToken) {
        lastStreamError ??= 'play — PlayerException: $e';
        _reportError(_playCurrent);
      }
    } catch (e) {
      if (token == _playToken) {
        lastStreamError ??= 'play — ${e.runtimeType}: $e';
        _reportError(_playCurrent);
      }
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
    // v13.17 — DIRECT STREAM (the user's order, 2026-11-19):
    // the word comes straight from the internet — NO foreground
    // Dart download. The cached file is used ONLY when already
    // on disk and valid: [localWbwFile] is a sync check, and the
    // v13.16 validation deletes an invalid file on the spot.
    final wbwLocal = downloads?.localWbwFile(ayah.$1, ayah.$2, fileNumber);
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
    final wbwUrls = wbwWordUrlsInOrder(ayah.$1, ayah.$2, fileNumber);
    for (var i = 0; i < wbwUrls.length; i++) {
      if (await _loadAndPlay(wbwUrls[i], Duration.zero, token,
          isLastHost: i == wbwUrls.length - 1)) {
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
      await _player.setFilePath(file.path).timeout(const Duration(seconds: 30));
      if (token != _playToken) return false;
      await _player.seek(seekTo).timeout(const Duration(seconds: 5));
      if (token != _playToken) return false;
      await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
      await _player.play().timeout(const Duration(seconds: 30));
      if (token != _playToken) {
        await _player.stop();
        return false;
      }
      final wait = await _waitForPositionBeyond(seekTo);
      if (!wait.moved) {
        // v13.15: the load "succeeded" but no audio data was
        // ever buffered — a buffering stall, not a play. Record
        // it.
        // v13.16: first failure wins (??=) — a local-file failure
        // recorded earlier in this attempt (the poisoned cache)
        // must not be overwritten by a later stream failure.
        // The stalled play also left `playing` stuck true —
        // reset it (see the catch below) so the next URL really
        // plays instead of faking success by extrapolation.
        if (token == _playToken) {
          lastStreamError ??= 'local ${file.path} — stall: no '
              'buffered data (buffering, 30s)';
          try {
            await _player.stop();
          } catch (_) {}
        }
        return false;
      }
      // Success clears any earlier failed attempt's diagnosis for
      // this item (v13.15).
      lastStreamError = null;
      return true;
    } catch (e) {
      // v13.15: record the real local-load error (corrupt file,
      // setFilePath timeout, ...) instead of swallowing it.
      // v13.16: the file proved unplayable — delete it (same
      // poisoned-cache rule as the ayah path) so the next tap
      // re-downloads it instead of failing on it again. Only for
      // the current attempt: a superseded load's failure is not
      // the file's fault. The failed play() also left `playing`
      // stuck true — reset it (see [_loadAndPlay]) so the
      // streaming fallback below really plays.
      if (token == _playToken) {
        lastStreamError ??= 'local ${file.path} — ${e.runtimeType}: $e';
        try {
          await file.delete();
        } catch (_) {}
        try {
          await _player.stop();
        } catch (_) {}
      }
      return false;
    }
  }

  /// Loads [url], seeks when [seekTo] is given, plays, and waits
  /// until REAL audio data is buffered past the seek point — a
  /// stalled buffer leaves the buffered position frozen, which is
  /// exactly the "spinner forever, no sound" failure (v13.18: the
  /// old position-only wait passed on just_audio's extrapolated
  /// position with zero data buffered). Returns false on any
  /// timeout or error instead of throwing; the caller decides the
  /// fallback. The [token] is checked after every await (see
  /// [_loadLocal]).
  ///
  /// [isLastHost] marks the last URL in the caller's chain: only
  /// a non-last host gets the slow-host switch (its `setUrl` and
  /// its wait for first buffered data each get [firstDataTimeout],
  /// ~2 s — the user's hard 1–2 s limit per ayah); the last host
  /// keeps the full stall window as the weakest-net backstop.
  Future<bool> _loadAndPlay(String url, Duration seekTo, int token,
      {bool isLastHost = false}) async {
    try {
      // v13.18 — the per-host first-data deadline (~2 s) bounds
      // `setUrl` too: on a slow host ExoPlayer's preparation
      // hangs waiting for the first bytes, so an unbounded (30 s)
      // setUrl would blow the 1–2 s goal before the buffered
      // wait even starts. The last host keeps the full stall
      // window (weakest-net backstop). A timed-out setUrl is
      // abandoned cleanly by the catch below (stop() resets the
      // stuck `playing` flag — the just_audio gotcha).
      await _player
          .setUrl(url)
          .timeout(isLastHost ? positionStallTimeout : firstDataTimeout);
      if (token != _playToken) return false;
      await _player.seek(seekTo).timeout(const Duration(seconds: 5));
      if (token != _playToken) return false;
      await _player.setSpeed(speed).timeout(const Duration(seconds: 5));
      await _player.play().timeout(const Duration(seconds: 30));
      if (token != _playToken) {
        await _player.stop();
        return false;
      }
      final wait = await _waitForPositionBeyond(
        seekTo,
        firstDataTimeout: isLastHost ? null : firstDataTimeout,
      );
      if (!wait.moved) {
        // v13.15: the load "succeeded" but no audio data was ever
        // buffered — a buffering stall, not a play. Record it: on
        // the user's phone this is indistinguishable from a load
        // failure, and the generic error hides which one it was.
        // v13.16: first failure wins (??=) — see [_loadLocal].
        // The stalled play also left `playing` stuck true —
        // reset it (see the catch below) so the next URL really
        // plays instead of faking success by extrapolation.
        // v13.18: say WHICH stall it was — abandoned by the
        // slow-host switch (no data at all) or the full stall
        // window (data started, then stopped).
        if (token == _playToken) {
          lastStreamError ??= wait.stall == 'no-data'
              ? '$url — stall: no buffered data in '
                  '${firstDataTimeout.inSeconds}s (slow host)'
              : '$url — stall: no buffered progress in '
                  '${positionStallTimeout.inSeconds}s';
          try {
            await _player.stop();
          } catch (_) {}
        }
        return false;
      }
      // Success clears any earlier failed attempt's diagnosis for
      // this item (v13.15).
      lastStreamError = null;
      return true;
    } catch (e) {
      // v13.15: record the real load error instead of swallowing
      // it — setUrl/play timeouts and PlayerExceptions are exactly
      // what the five failed versions hid.
      // v13.16: first failure wins (??=) — see [_loadLocal].
      // A failed play() leaves just_audio's `playing` stuck true
      // (set before the platform call, never reverted on error):
      // the next URL's play() would return at once without
      // playing anything, while the position extrapolates past
      // the check — a silent false success. Stop resets the flag
      // so the next attempt really plays. Only for the current
      // attempt: a superseded load must not stop the newer play.
      if (token == _playToken) {
        lastStreamError ??= '$url — ${e.runtimeType}: $e';
        try {
          await _player.stop();
        } catch (_) {}
      }
      return false;
    }
  }

  /// True once REAL audio data has been buffered past [target]
  /// (+100 ms of slack), or the item already finished (a very
  /// short word can complete before the first buffered event
  /// arrives — it did play).
  ///
  /// v13.18 — THE SILENT-PLAYING HOLE (proven reading just_audio
  /// 0.9.46: `position` is EXTRAPOLATED from wall-clock time
  /// while `playing && ready`, and `positionStream` emits those
  /// extrapolated values on a timer): the old position-only wait
  /// passed with ZERO audio data actually decoded — `_loadAndPlay`
  /// returned true while ExoPlayer had buffered nothing: no
  /// sound, no completion, pause icon showing, and the failover
  /// to the next host never ran. The wait now watches
  /// `bufferedPosition` — fed straight from the platform's
  /// playback events, never extrapolated — so only real buffered
  /// data passes it. A local file reports its whole duration as
  /// buffered at once, so local playback is unaffected.
  ///
  /// Two windows, both stall-based (weakest-net rule: a
  /// slow-but-progressing stream is never failed for being slow):
  /// * [firstDataTimeout] — when set, no buffered data at all
  ///   within that window abandons the wait at once (the
  ///   slow-host switch: the next host is tried instead of
  ///   burning the full stall window on a host that is not
  ///   delivering — the user's phone waited ~30 s per ayah on
  ///   SurahPedia). Null disables the switch (the last host
  ///   keeps the full stall window as the backstop, and so does
  ///   a local file).
  /// * [positionStallTimeout] — no buffered progress at all for
  ///   this long fails the wait; every buffered advance re-arms
  ///   it, so a trickling stream never fails for being slow.
  /// Returns a record: [moved] and the stall kind on failure
  /// (`'no-data'` for the first-data switch, `'stalled'` for the
  /// stall window, null on success) — the caller puts the real
  /// reason in the diagnostic. Timers and subscriptions are
  /// cancelled in `finally`, so timing out cannot leak them.
  Future<({bool moved, String? stall})> _waitForPositionBeyond(
    Duration target, {
    Duration? firstDataTimeout,
  }) async {
    final beyond = target + const Duration(milliseconds: 100);
    if (_player.bufferedPosition > beyond ||
        _player.processingState == ProcessingState.completed) {
      return (moved: true, stall: null);
    }
    final completer = Completer<({bool moved, String? stall})>();
    void done(bool moved, String? stall) {
      if (!completer.isCompleted) {
        completer.complete((moved: moved, stall: stall));
      }
    }

    final startBuffered = _player.bufferedPosition;
    var sawBufferedAdvance = false;
    Timer? stallTimer;
    Timer? firstDataTimer;
    void armStall() {
      stallTimer?.cancel();
      stallTimer =
          Timer(positionStallTimeout, () => done(false, 'stalled'));
    }

    late final StreamSubscription<Duration> bufferedSub;
    late final StreamSubscription<PlayerState> stateSub;
    bufferedSub = _player.bufferedPositionStream.listen((buffered) {
      if (buffered > startBuffered) {
        // Real data arrived — the slow-host switch no longer
        // applies, and the stall window restarts: slow but
        // progressing is never failed for being slow.
        sawBufferedAdvance = true;
        firstDataTimer?.cancel();
        firstDataTimer = null;
        armStall();
      }
      if (buffered > beyond) done(true, null);
    });
    stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        done(true, null);
      }
    });
    armStall();
    if (firstDataTimeout != null) {
      firstDataTimer = Timer(firstDataTimeout, () {
        if (!sawBufferedAdvance) done(false, 'no-data');
      });
    }
    try {
      return await completer.future;
    } finally {
      stallTimer?.cancel();
      firstDataTimer?.cancel();
      await bufferedSub.cancel();
      await stateSub.cancel();
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
    // v13.15 (DIAGNOSTIC): the real cause, shown under the generic
    // line in the sheet — the stream (native player) error first,
    // then the download (Dart http) error when one was recorded.
    // Either may be null (superseded attempt, or a failure with no
    // recorded cause); the generic line still shows on its own.
    // The download error is the service's most recent failure —
    // in the ayah/page/surah path the cache attempt runs in this
    // same _playCurrent call, just before streaming, so it is the
    // failure of this very item.
    final parts = <String>[];
    if (lastStreamError != null) parts.add('تشغيل: $lastStreamError');
    final dlError = downloads?.lastDownloadError;
    if (dlError != null) parts.add('تنزيل: $dlError');
    lastDiagnostic = parts.isEmpty ? null : parts.join('\n');
    notifyListeners();
    onError?.call(
      'تعذّر تحميل الصوت — تحقق من الاتصال وحاول مجدداً',
      retry,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAdvanceWatchdog();
    _player.dispose();
    super.dispose();
  }
}
